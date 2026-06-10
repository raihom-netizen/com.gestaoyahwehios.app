import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/debug/agent_debug_log.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resolve slug/alias legado → doc canónico `igrejas/{churchId}`.
/// Coleção `tenants/` **não** é lida pelo app — só `igrejas/{churchId}`.
/// Após login, preferir [ChurchContextService.currentChurchId].
class TenantResolverService {
  TenantResolverService._();

  static FirebaseFirestore get _firestore => firebaseDefaultFirestore;
  static const int _scanLimit = 350;

  /// Doc Firestore + Storage canónico da Igreja Brasil para Cristo (BPC).
  static const String kBpcCanonicalIgrejaDocId =
      'igreja_o_brasil_para_cristo_jardim_goiano';

  /// IDs legados — migrados para [kBpcCanonicalIgrejaDocId]; redirecionados via `church_aliases`.
  static const List<String> kBpcLegacyTenantIds = [
    'brasilparacristo',
    'brasilparacristo_sistema',
    'iobpc-jardim-goiano',
    'o-brasil-cristo-jardim-goiano',
  ];

  /// Cluster operacional — após consolidação BPC, só o doc canónico.
  static const Map<String, List<String>> _anchoredChurchClusters = {
    kBpcCanonicalIgrejaDocId: [kBpcCanonicalIgrejaDocId],
  };

  /// Slugs públicos (URL `/igreja/{slug}/cadastro-membro`) → doc canónico operacional.
  static const Map<String, String> _publicSlugToCanonicalDocId = {
    'o-brasil-cristo-jardim-goiano': kBpcCanonicalIgrejaDocId,
    'iobpc-jardim-goiano': kBpcCanonicalIgrejaDocId,
    'brasil-para-cristo': kBpcCanonicalIgrejaDocId,
    'brasilparacristo': kBpcCanonicalIgrejaDocId,
  };

  /// ID operacional do cluster ancorado (Storage + subcoleções).
  static String? _anchoredCanonicalOperationalId(Set<String> candidates) {
    for (final entry in _anchoredChurchClusters.entries) {
      final canonical = entry.key.trim();
      if (canonical.isEmpty) continue;
      final clusterIds = <String>{canonical, ...entry.value};
      for (final c in candidates) {
        if (clusterIds.contains(c.trim())) return canonical;
      }
    }
    return null;
  }

  static void _addAnchoredClusterMembers(String raw, Set<String> result) {
    final t = raw.trim();
    if (t.isEmpty) return;
    if (t == kBpcCanonicalIgrejaDocId || kBpcLegacyTenantIds.contains(t)) {
      result.add(kBpcCanonicalIgrejaDocId);
    }
    for (final entry in _anchoredChurchClusters.entries) {
      if (entry.key == t || entry.value.contains(t)) {
        result.add(entry.key);
        result.addAll(entry.value);
      }
    }
  }

  /// Path Storage/Firestore — ID directo da sessão ou do parâmetro.
  static String syncStorageTenantId(String seedId) {
    final panel = ChurchContextService.panelChurchId(seedId);
    if (panel.isNotEmpty) return panel;
    return seedId.trim();
  }

  /// IDs do cluster ancorado — BPC consolidado = só canónico; legado via `church_aliases`.
  static List<String> anchoredClusterIdsFor(String id) {
    final t = id.trim();
    if (t.isEmpty) return const [];
    if (t == kBpcCanonicalIgrejaDocId || kBpcLegacyTenantIds.contains(t)) {
      return const [kBpcCanonicalIgrejaDocId];
    }
    for (final entry in _anchoredChurchClusters.entries) {
      if (entry.key == t || entry.value.contains(t)) {
        final out = <String>[entry.key, ...entry.value];
        return out.where((x) => x.trim().isNotEmpty).toSet().toList();
      }
    }
    return const [];
  }

  /// Doc com subcoleções/perfil reais — canónico de escrita + irmão com dados (BPC).
  static Future<String> resolveModuleReadTenantId(
    String seedId, {
    String? userUid,
  }) async {
    final seed = seedId.trim();
    if (seed.isEmpty) return seed;

    final cached = peekModuleReadTenantId(seed, userUid: userUid);
    if (cached != null && cached.isNotEmpty) return cached;

    final operational = await resolveOperationalChurchDocId(
      seed,
      userUid: userUid,
    );
    final op = operational.trim();
    if (op.isEmpty) return op;

    final cachedOp = peekModuleReadTenantId(op, userUid: userUid);
    if (cachedOp != null && cachedOp.isNotEmpty) return cachedOp;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    var resolved = op;
    // Fonte única: igrejas/{operationalId} — sem redirecionar para doc «mais rico» do cluster.
    rememberModuleReadTenantId(seed, resolved, userUid: userUid);
    return resolved;
  }

  /// SaaS directo — cada igreja isolada; sem fallback para docs irmãos.
  static List<String> orderedSiblingsForReadFallback(
    String primary,
    List<String> siblings, {
    int maxExtra = 8,
  }) =>
      const [];

  /// Doc canónico para **escritas** e Storage — cluster ancorado + doc com mais dados.
  static Future<String> _resolveCanonicalOperationalId(
    String bound,
    String claimId,
    List<String> siblings,
  ) async {
    final candidates = <String>{bound.trim()};
    if (claimId.trim().isNotEmpty) candidates.add(claimId.trim());
    for (final s in siblings) {
      final t = s.trim();
      if (t.isNotEmpty) candidates.add(t);
    }

    final anchored = _anchoredCanonicalOperationalId(candidates);
    if (anchored != null) return anchored;

    if (claimId.trim().isNotEmpty && candidates.contains(claimId.trim())) {
      return claimId.trim();
    }

    try {
      return await resolveChurchDocIdPreferringRichestCluster(
        bound,
        preferId: claimId.trim().isEmpty ? bound.trim() : claimId.trim(),
      );
    } catch (_) {
      return bound.trim().isEmpty ? claimId.trim() : bound.trim();
    }
  }

  static Future<void> _ensureFirestore() => ensureFirebaseReadyForPanelRead();

  static final Map<String, _AliasCacheEntry> _directDocIdCache = {};
  static const Duration _directDocIdCacheTtl = Duration(hours: 6);

  /// Resolve para o **doc ID** em `igrejas/{id}` — sem `church_aliases`.
  /// 1) doc existe com esse id; 2) campo `churchId`/`igrejaId`/`tenantId` no doc raiz.
  static Future<String?> resolveChurchAlias(String rawAlias) async {
    final alias = rawAlias.trim();
    if (alias.isEmpty) return null;

    final hit = _directDocIdCache[alias];
    if (hit != null &&
        DateTime.now().difference(hit.resolvedAt) < _directDocIdCacheTtl) {
      return hit.canonicalId;
    }

    await _ensureFirestore();
    try {
      final direct = await _firestore.collection('igrejas').doc(alias).get();
      if (direct.exists) {
        _directDocIdCache[alias] =
            _AliasCacheEntry(alias, DateTime.now());
        return alias;
      }
      for (final field in const ['churchId', 'igrejaId', 'tenantId']) {
        final q = await _firestore
            .collection('igrejas')
            .where(field, isEqualTo: alias)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final id = q.docs.first.id;
          _directDocIdCache[alias] = _AliasCacheEntry(id, DateTime.now());
          return id;
        }
      }
    } catch (_) {
      final mem = _directDocIdCache[alias];
      return mem?.canonicalId;
    }
    return null;
  }

  static void invalidateAliasCache({String? alias}) {
    if (alias == null || alias.trim().isEmpty) {
      _directDocIdCache.clear();
      return;
    }
    _directDocIdCache.remove(alias.trim());
  }

  /// Contexto operacional completo — alias → canónico + perfil (Regra 3).
  static Future<({
    String canonicalId,
    String seedId,
    String? resolvedAlias,
    Map<String, dynamic> profile,
  })> resolveOperationalChurch(
    String seedId, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final seed = seedId.trim();
    if (seed.isEmpty) {
      return (
        canonicalId: '',
        seedId: '',
        resolvedAlias: null,
        profile: <String, dynamic>{},
      );
    }

    String? aliasHit;
    final fromAlias = await resolveChurchAlias(seed);
    if (fromAlias != null && fromAlias.isNotEmpty) {
      aliasHit = seed;
    }

    final canonical = await resolveOperationalChurchDocId(
      fromAlias ?? seed,
      userUid: userUid,
      forceRefresh: forceRefresh,
    );

    var profile = await loadIgrejaCadastroDocDirect(
      canonical,
      preferServer: kIsWeb,
    );
    if (profile.isEmpty) {
      final peek = peekRegistrationContext(seed, userUid: userUid);
      if (peek != null && peek.profile.isNotEmpty) {
        profile = Map<String, dynamic>.from(peek.profile);
      }
    }

    return (
      canonicalId: canonical,
      seedId: seed,
      resolvedAlias: aliasHit,
      profile: profile,
    );
  }

  /// Regra 6 — alinha `users/{uid}` ao ID canónico sem intervenção manual.
  static Future<bool> syncUserToCanonicalChurchId({
    required String userUid,
    required String canonicalId,
  }) async {
    final uid = userUid.trim();
    final canonical = canonicalId.trim();
    if (uid.isEmpty || canonical.isEmpty) return false;

    try {
      final ref = _firestore.collection('users').doc(uid);
      final snap = await ref
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) return false;
      final data = snap.data() ?? {};
      final stored =
          (data['igrejaId'] ?? data['tenantId'] ?? '').toString().trim();
      if (stored == canonical) return false;

      final siblings = await getAllRelatedIgrejaDocIds(canonical)
          .timeout(const Duration(seconds: 8));
      final cluster = <String>{canonical, ...siblings};
      if (stored.isNotEmpty && !cluster.contains(stored)) return false;

      await ref.set(
        {
          'igrejaId': canonical,
          'tenantId': canonical,
          'churchCanonicalId': canonical,
          if (stored.isNotEmpty && stored != canonical) 'legacyIgrejaId': stored,
          'tenantSyncedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      invalidateOperationalChurchDocCache(seedId: stored, userUid: uid);
      invalidateOperationalChurchDocCache(seedId: canonical, userUid: uid);
      invalidateRegistrationContextCache(seedId: stored, userUid: uid);
      invalidateRegistrationContextCache(seedId: canonical, userUid: uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// URL pública → doc `igrejas/{churchId}` (directo; sem `church_aliases`).
  static Future<String?> resolveIgrejaDocIdFromPublicSlug(String rawSlug) async {
    final slugTrim = rawSlug.trim();
    if (slugTrim.isEmpty) return null;

    await _ensureFirestore();
    try {
      final direct = await _firestore.collection('igrejas').doc(slugTrim).get();
      if (direct.exists) return slugTrim;
    } catch (_) {}

    final fromDirect = await resolveChurchAlias(slugTrim);
    if (fromDirect != null && fromDirect.isNotEmpty) return fromDirect;

    for (final field in const ['churchId', 'igrejaId', 'tenantId']) {
      try {
        final q = await _firestore
            .collection('igrejas')
            .where(field, isEqualTo: slugTrim)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) return q.docs.first.id;
      } catch (_) {}
    }
    return null;
  }

  static String _normalize(String s) {
    if (s.isEmpty) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
  }

  /// ID operacional da sessão — contexto bound ou resolução única.
  static Future<String> operationalChurchId({
    String? seed,
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final ctx = ChurchContextService.currentChurchId;
    if (!forceRefresh && ctx != null && ctx.isNotEmpty) {
      final s = (seed ?? ChurchContextService.seedId ?? ctx).trim();
      if (s.isEmpty || s == ctx || s == ChurchContextService.seedId) {
        return ctx;
      }
    }
    final s = (seed ?? ctx ?? '').trim();
    if (s.isEmpty) return '';
    return resolveOperationalChurchDocId(
      s,
      userUid: userUid,
      forceRefresh: forceRefresh,
    );
  }

  /// Resolve o ID efetivo — directo `igrejas/{churchId}` (sem alias/cluster).
  static Future<String> resolveEffectiveTenantId(String id) async {
    final raw = id.trim();
    if (raw.isEmpty) return id;
    final panel = ChurchContextService.panelChurchId(raw);
    if (panel.isNotEmpty) return panel;
    await _ensureFirestore();
    try {
      final doc = await _firestore.collection('igrejas').doc(raw).get();
      if (doc.exists) return raw;
    } catch (_) {}
    return raw;
  }

  /// Para queries em `igrejas/{id}/…`, prefere o ID que consta em `users/{uid}.igrejaId` /
  /// `tenantId` quando esse doc for **irmão** do resolvido (mesmo slug — via [getAllRelatedIgrejaDocIds]).
  ///
  /// Evita `permission-denied` ou coleções aparentemente vazias: o resolver pode devolver um
  /// documento canónico enquanto o vínculo do utilizador aponta para outro id da mesma igreja.
  static Future<String> resolveEffectiveTenantIdPreferringUserBinding(
    String seedId, {
    String? userUid,
  }) async {
    final resolved = await resolveEffectiveTenantId(seedId.trim());
    final uid = (userUid ?? '').trim();
    if (uid.isEmpty) return resolved;

    String claimId = '';
    try {
      final u = await _firestore.collection('users').doc(uid).get();
      claimId =
          (u.data()?['igrejaId'] ?? u.data()?['tenantId'] ?? '').toString().trim();
    } catch (_) {}

    if (claimId.isEmpty || claimId == resolved) return resolved;

    try {
      final siblings = await getAllRelatedIgrejaDocIds(resolved);
      if (siblings.contains(claimId)) return claimId;
    } catch (_) {}

    return resolved;
  }

  static final Map<String, _OperationalTenantCacheEntry> _operationalByKey = {};
  static final Map<String, String> _moduleReadByKey = {};
  static const Duration _operationalCacheTtl = Duration(minutes: 45);

  static String _operationalCacheKey(String seedId, String? userUid) =>
      '${(userUid ?? '').trim()}\x00${seedId.trim()}';

  /// Shell grava o doc com subcoleções reais — módulos leem sem re-scan do cluster.
  static void rememberModuleReadTenantId(
    String seed,
    String moduleReadId, {
    String? userUid,
  }) {
    final op = moduleReadId.trim();
    if (op.isEmpty) return;
    for (final id in {seed.trim(), op}) {
      if (id.isEmpty) continue;
      _moduleReadByKey[_operationalCacheKey(id, userUid)] = op;
    }
  }

  static String? peekModuleReadTenantId(String seed, {String? userUid}) {
    final s = seed.trim();
    if (s.isEmpty) return null;
    return _moduleReadByKey[_operationalCacheKey(s, userUid)];
  }

  /// ID canónico para subcoleções (`membros`, `escalas`, `agenda`, `event_templates`, …):
  /// vínculo em `users` + doc irmão com mais dados no cluster (slug / `_sistema`).
  static Future<String> resolveOperationalChurchDocId(
    String seedId, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final seed = seedId.trim();
    if (seed.isEmpty) return seed;

    if (!forceRefresh) {
      final ctx = ChurchContextService.currentChurchId;
      if (ctx != null &&
          ctx.isNotEmpty &&
          (seed == ctx ||
              seed == ChurchContextService.seedId ||
              ChurchContextService.seedId == seed)) {
        return ctx;
      }
    }

    final cacheKey = _operationalCacheKey(seed, userUid);
    if (!forceRefresh) {
      final hit = _operationalByKey[cacheKey];
      if (hit != null &&
          DateTime.now().difference(hit.resolvedAt) < _operationalCacheTtl) {
        return hit.id;
      }
    }

    final sw = Stopwatch()..start();
    final panel = ChurchContextService.panelChurchId(seed);
    final operational = panel.isNotEmpty ? panel : seed;
    sw.stop();
    ChurchOperationalFirestoreTrace.record(
      origin: 'TenantResolverService.resolveOperationalChurchDocId',
      firestorePath: 'igrejas/$operational',
      churchId: operational,
      durationMs: sw.elapsedMilliseconds,
    );

    _operationalByKey[cacheKey] =
        _OperationalTenantCacheEntry(operational, DateTime.now());
    AgentDebugLog.log(
      location: 'tenant_resolver_service.dart:resolveOperational',
      message: 'operational_id_resolved',
      hypothesisId: 'A',
      data: {
        'seed': seed,
        'operational': operational,
        'forceRefresh': forceRefresh,
      },
    );
    return operational;
  }

  static void invalidateOperationalChurchDocCache({
    String? seedId,
    String? userUid,
  }) {
    if (seedId == null) {
      _operationalByKey.clear();
      _moduleReadByKey.clear();
      return;
    }
    final key = _operationalCacheKey(seedId, userUid);
    _operationalByKey.remove(key);
    _moduleReadByKey.remove(key);
  }

  static String _slugFromIgrejaData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return '';
    return (data['slug'] ?? data['slugId'] ?? data['alias'] ?? '')
        .toString()
        .trim();
  }

  /// Slug público — doc canónico + irmãos (evita banner «Configure o slug» falso).
  static Future<String> resolveChurchPublicSlug(String churchDocId) async {
    final raw = churchDocId.trim();
    if (raw.isEmpty) return '';

    await _ensureFirestore();

    Future<String> slugFromDoc(String id) async {
      final t = id.trim();
      if (t.isEmpty) return '';
      try {
        final snap = await _firestore
            .collection('igrejas')
            .doc(t)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 8));
        return _slugFromIgrejaData(snap.data());
      } catch (_) {
        return '';
      }
    }

    var slug = await slugFromDoc(raw);
    if (slug.isNotEmpty) return slug;

    List<String> siblings;
    try {
      siblings = await getAllRelatedIgrejaDocIds(raw);
    } catch (_) {
      siblings = const [];
    }
    final extra = siblings.where((id) => id.trim().isNotEmpty && id != raw);
    if (extra.isEmpty) return '';

    final hits = await Future.wait(extra.map(slugFromDoc));
    for (final s in hits) {
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static int _churchProfileScore(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return 0;
    var score = 0;
    void bump(String k) {
      if ((data[k] ?? '').toString().trim().isNotEmpty) score += 2;
    }

    bump('nome');
    bump('name');
    if (_slugFromIgrejaData(data).isNotEmpty) score += 4;
    bump('cidade');
    bump('estado');
    bump('telefone');
    bump('phone');
    bump('rua');
    bump('bairro');
    bump('cep');
    bump('cnpj');
    bump('CNPJ');
    bump('gestorNome');
    bump('gestorEmail');
    bump('gestorTelefone');
    bump('gestorCpf');
    bump('endereco');
    bump('instagramUrl');
    bump('logoPath');
    if (data['registrationComplete'] == true ||
        data['RegistrationComplete'] == true) {
      score += 3;
    }
    return score;
  }

  /// Leitura directa do doc canónico `igrejas/{id}` — cadastro web (sem `tenants/`).
  static Future<Map<String, dynamic>> loadIgrejaCadastroDocDirect(
    String churchDocId, {
    bool preferServer = false,
  }) async {
    final id = churchDocId.trim();
    if (id.isEmpty) return {};
    await _ensureFirestore();
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final ref = _firestore.collection('igrejas').doc(id);

    Future<Map<String, dynamic>> readDoc(String docId) async {
      final t = docId.trim();
      if (t.isEmpty) return {};
      final docRef = t == id ? ref : _firestore.collection('igrejas').doc(t);
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => FirestoreReadResilience.getDocument(
            docRef,
            cacheKey: 'igreja_cadastro_$t',
            maxAttempts: kIsWeb ? 3 : 2,
            attemptTimeout: Duration(
              seconds: preferServer || kIsWeb ? 18 : 10,
            ),
          ),
        );
        if (snap.exists && snap.data() != null) {
          return Map<String, dynamic>.from(snap.data()!);
        }
      } catch (_) {}
      return {};
    }

    var data = await readDoc(id);
    if (data.isNotEmpty &&
        _churchProfileScore(data) >= _richProfileEarlyExitScore) {
      return data;
    }

    for (final sibling in anchoredClusterIdsFor(id)) {
      if (sibling == id) continue;
      final alt = await readDoc(sibling);
      if (_churchProfileScore(alt) > _churchProfileScore(data)) {
        data = alt;
      }
      if (_churchProfileScore(data) >= _richProfileEarlyExitScore) break;
    }

    if (data.isNotEmpty) return data;

    final peek = peekRegistrationContext(id);
    if (peek != null && peek.profile.isNotEmpty) {
      return Map<String, dynamic>.from(peek.profile);
    }
    return {};
  }

  /// Score público — módulo Cadastro da Igreja decide se re-hidrata com doc mais completo.
  static int churchProfileRichnessScore(Map<String, dynamic>? data) =>
      _churchProfileScore(data);

  static final Map<String, _RegistrationContextCacheEntry> _registrationByKey =
      {};
  static const Duration _registrationCacheTtl = Duration(minutes: 25);

  static void invalidateRegistrationContextCache({
    String? seedId,
    String? userUid,
  }) {
    if (seedId == null || seedId.trim().isEmpty) {
      _registrationByKey.clear();
      return;
    }
    _registrationByKey.remove(_operationalCacheKey(seedId.trim(), userUid));
  }

  /// RAM — abertura instantânea do Cadastro da Igreja (sem rede).
  static ({String operationalId, Map<String, dynamic> profile})?
      peekRegistrationContext(
    String seedId, {
    String? userUid,
  }) {
    final seed = seedId.trim();
    if (seed.isEmpty) return null;
    final cacheKey = _operationalCacheKey(seed, userUid);
    final hit = _registrationByKey[cacheKey];
    if (hit != null &&
        DateTime.now().difference(hit.resolvedAt) < _registrationCacheTtl) {
      return (
        operationalId: hit.operationalId,
        profile: Map<String, dynamic>.from(hit.profile),
      );
    }
    final opHit = _operationalByKey[cacheKey];
    if (opHit != null &&
        DateTime.now().difference(opHit.resolvedAt) < _operationalCacheTtl) {
      return (operationalId: opHit.id, profile: <String, dynamic>{});
    }
    return null;
  }

  /// Um doc Firestore em cache local — pinta o formulário no 1.º frame (<1 s).
  static Future<({String operationalId, Map<String, dynamic> profile})>
      loadChurchRegistrationContextFast(
    String seedId, {
    String? userUid,
  }) async {
    final seed = seedId.trim();
    if (seed.isEmpty) {
      return (operationalId: '', profile: <String, dynamic>{});
    }
    final peek = peekRegistrationContext(seed, userUid: userUid);
    if (peek != null) return peek;

    final cacheKey = _operationalCacheKey(seed, userUid);
    final opHit = _operationalByKey[cacheKey];
    final operational = (opHit?.id ?? seed).trim();

    Future<Map<String, dynamic>?> readCacheDoc(String id) async {
      final t = id.trim();
      if (t.isEmpty) return null;
      try {
        final snap = await _firestore
            .collection('igrejas')
            .doc(t)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(milliseconds: 700));
        if (snap.exists && snap.data() != null) {
          return Map<String, dynamic>.from(snap.data()!);
        }
      } catch (_) {}
      return null;
    }

    Map<String, dynamic>? bestData;
    var bestScore = -1;

    final cacheCandidates = <String>{
      operational,
      if (seed.isNotEmpty) seed,
    };
    for (final members in _anchoredChurchClusters.values) {
      cacheCandidates.addAll(members);
    }
    for (final id in cacheCandidates) {
      final data = await readCacheDoc(id);
      if (data == null || data.isEmpty) continue;
      final sc = _churchProfileScore(data);
      if (sc > bestScore) {
        bestScore = sc;
        bestData = data;
      }
    }
    if (bestData != null && bestScore >= 4) {
      return (operationalId: operational, profile: bestData!);
    }
    return (operationalId: operational, profile: <String, dynamic>{});
  }

  /// Perfil do cadastro (nome, slug, morada) + id operacional (Storage + subcoleções).
  static Future<({String operationalId, Map<String, dynamic> profile})>
      loadChurchRegistrationContext(
    String seedId, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final seed = seedId.trim();
    final cacheKey = _operationalCacheKey(seed, userUid);
    if (!forceRefresh) {
      final hit = _registrationByKey[cacheKey];
      if (hit != null &&
          DateTime.now().difference(hit.resolvedAt) < _registrationCacheTtl) {
        return (operationalId: hit.operationalId, profile: hit.profile);
      }
    }
    final operational = await resolveOperationalChurchDocId(
      seed,
      userUid: userUid,
      forceRefresh: forceRefresh,
    );
    final profile = await _richestProfileInCluster(
      operational,
      preferServer: false,
    );
    _registrationByKey[cacheKey] = _RegistrationContextCacheEntry(
      operationalId: operational,
      profile: Map<String, dynamic>.from(profile),
      resolvedAt: DateTime.now(),
    );
    return (operationalId: operational, profile: profile);
  }

  static const int _richProfileEarlyExitScore = 14;

  /// Perfil de cadastro mais completo no cluster (Cadastro da Igreja — web + mobile).
  static Future<Map<String, dynamic>> richestChurchProfileForCadastro(
    String seedOrOperational, {
    bool preferServer = false,
  }) =>
      _richestProfileInCluster(
        seedOrOperational,
        preferServer: preferServer,
      );

  /// Doc irmão com mais campos de cadastro (evita formulário vazio no «Cadastro da Igreja»).
  static Future<Map<String, dynamic>> _richestProfileInCluster(
    String operationalId, {
    bool scanSiblings = true,
    bool preferServer = false,
  }) async {
    var best = <String, dynamic>{};
    var bestScore = -1;
    final primary = operationalId.trim();
    if (primary.isEmpty) return best;

    final networkSource =
        preferServer ? Source.server : Source.serverAndCache;
    final networkTimeout = preferServer
        ? (kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 10))
        : const Duration(seconds: 8);

    Future<void> consider(
      String id, {
      Source source = Source.serverAndCache,
      Duration timeout = const Duration(seconds: 8),
    }) async {
      final t = id.trim();
      if (t.isEmpty) return;
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(() async {
          if (kIsWeb && (preferServer || source == Source.server)) {
            return FirestoreReadResilience.getDocument(
              _firestore.collection('igrejas').doc(t),
              cacheKey: 'igreja_profile_richest_$t',
              maxAttempts: 3,
              attemptTimeout: timeout,
            );
          }
          return _firestore
              .collection('igrejas')
              .doc(t)
              .get(GetOptions(source: source))
              .timeout(timeout);
        });
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final sc = _churchProfileScore(data);
        if (sc > bestScore) {
          bestScore = sc;
          best = Map<String, dynamic>.from(data);
        }
      } catch (_) {}
    }

    final anchored = anchoredClusterIdsFor(primary);
    if (anchored.isNotEmpty) {
      await Future.wait(
        anchored.map(
          (id) => consider(
            id,
            source: networkSource,
            timeout: networkTimeout,
          ),
        ),
      );
      if (bestScore >= _richProfileEarlyExitScore) return best;
    }

    if (!preferServer) {
      await consider(
        primary,
        source: Source.cache,
        timeout: const Duration(milliseconds: 700),
      );
      if (bestScore >= _richProfileEarlyExitScore) return best;
    }

    await consider(primary, source: networkSource, timeout: networkTimeout);
    if (bestScore >= _richProfileEarlyExitScore || !scanSiblings) return best;

    List<String> siblings;
    try {
      siblings = await getAllRelatedIgrejaDocIds(primary)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      siblings = const [];
    }
    final ordered = orderedSiblingsForReadFallback(primary, siblings, maxExtra: 8)
        .where((sid) => siblings.map((s) => s.trim()).contains(sid.trim()))
        .toList();
    if (ordered.isNotEmpty) {
      await Future.wait(
        ordered.map(
          (s) => consider(s, source: networkSource, timeout: networkTimeout),
        ),
      );
    }

    if (preferServer && bestScore < _richProfileEarlyExitScore) {
      await consider(primary, source: Source.server, timeout: networkTimeout);
      for (final s in ordered) {
        await consider(s, source: Source.server, timeout: networkTimeout);
      }
    }

    return best;
  }

  /// SaaS directo — só `igrejas/{churchId}` (sem cluster, alias ou docs irmãos).
  static Future<List<String>> getAllRelatedIgrejaDocIds(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return const [];
    return [raw];
  }

  /// Departamentos — directo `igrejas/{churchId}` (SaaS isolado).
  static Future<String> resolveChurchDocIdPreferringNonEmptyDepartments(
      String seedId) async {
    return resolveEffectiveTenantId(seedId);
  }

  static const Map<String, int> _richClusterWeights = {
    'membros': 6,
    'escalas': 6,
    'event_templates': 6,
    'agenda': 5,
    'departamentos': 5,
    'visitantes': 3,
    'cargos': 3,
    'pedidosOracao': 3,
    'fornecedores': 3,
    'finance': 2,
    'patrimonio': 2,
  };

  static const List<String> _richClusterCollections = [
    'membros',
    'escalas',
    'event_templates',
    'agenda',
    'departamentos',
    'visitantes',
    'cargos',
    'pedidosOracao',
    'fornecedores',
    'finance',
    'patrimonio',
  ];

  /// Doc irmão com mais dados (escalas, agenda, cultos fixos, membros, etc.).
  /// Substitui só «departamentos não vazio» — alinha Brasil para Cristo / `_sistema`.
  static Future<String> resolveChurchDocIdPreferringRichestCluster(
    String seedId, {
    String? preferId,
  }) async {
    final resolved = await resolveEffectiveTenantId(seedId);
    final raw = resolved.trim();
    if (raw.isEmpty) return resolved;

    final candidates = <String>[];
    void addUnique(String x) {
      final t = x.trim();
      if (t.isNotEmpty && !candidates.contains(t)) candidates.add(t);
    }

    addUnique(raw);
    final pref = (preferId ?? '').trim();
    if (pref.isNotEmpty) addUnique(pref);
    for (final suf in ['_sistema', '_bpc']) {
      if (raw.endsWith(suf)) {
        addUnique(raw.substring(0, raw.length - suf.length));
      } else {
        addUnique('$raw$suf');
      }
    }
    try {
      for (final s in await getAllRelatedIgrejaDocIds(raw)) {
        addUnique(s);
      }
    } catch (_) {}

    Future<int> scoreTenant(String tid) async {
      var total = 0;
      await Future.wait(
        _richClusterCollections.map((col) async {
          final w = _richClusterWeights[col] ?? 1;
          try {
            final snap = await _firestore
                .collection('igrejas')
                .doc(tid)
                .collection(col)
                .limit(1)
                .get(const GetOptions(source: Source.serverAndCache))
                .timeout(const Duration(seconds: 7));
            if (snap.docs.isNotEmpty) total += w;
          } catch (_) {}
        }),
      );
      return total;
    }

    var bestId = raw;
    var bestScore = -1;
    for (final tid in candidates) {
      final s = await scoreTenant(tid);
      if (s > bestScore) {
        bestScore = s;
        bestId = tid;
      } else if (s == bestScore &&
          s > 0 &&
          pref.isNotEmpty &&
          tid == pref) {
        bestId = tid;
      }
    }
    return bestScore > 0 ? bestId : raw;
  }

  /// IDs para leitura operacional — com contexto bound, só [currentChurchId].
  static Future<List<String>> getAllTenantIdsWithSameSlugOrAlias(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return [raw];
    final ctx = ChurchContextService.currentChurchId;
    if (ctx != null && ctx.isNotEmpty) return [ctx];
    return [await operationalChurchId(seed: raw)];
  }

  /// Retorna IDs em `igrejas` com o mesmo slug/alias + variantes (mesmo conjunto que [getAllTenantIdsWithSameSlugOrAlias]).
  static Future<List<String>> getIgrejaIdsWithSameSlugOrAlias(String resolvedTenantId) async {
    final raw = resolvedTenantId.trim();
    if (raw.isEmpty) return [];
    return getAllRelatedIgrejaDocIds(raw);
  }
}

class _OperationalTenantCacheEntry {
  _OperationalTenantCacheEntry(this.id, this.resolvedAt);

  final String id;
  final DateTime resolvedAt;
}

class _RegistrationContextCacheEntry {
  _RegistrationContextCacheEntry({
    required this.operationalId,
    required this.profile,
    required this.resolvedAt,
  });

  final String operationalId;
  final Map<String, dynamic> profile;
  final DateTime resolvedAt;
}

class _AliasCacheEntry {
  _AliasCacheEntry(this.canonicalId, this.resolvedAt);

  final String canonicalId;
  final DateTime resolvedAt;
}
