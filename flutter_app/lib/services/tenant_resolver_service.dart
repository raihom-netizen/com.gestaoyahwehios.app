import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/debug/agent_debug_log.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resolve o ID do tenant ou igreja para carregar membros.
/// Suporta tenants e igrejas (quando membros estão em igrejas/{id}/membros).
/// Normalização: "Brasil para Cristo" = "brasilparacristo" = "brasil-para-cristo".
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

  /// Normalização síncrona para paths Storage (antes do resolver async terminar).
  static String syncStorageTenantId(String seedId) {
    final t = seedId.trim();
    if (t.isEmpty) return t;
    if (t == kBpcCanonicalIgrejaDocId) return t;
    if (kBpcLegacyTenantIds.contains(t)) return kBpcCanonicalIgrejaDocId;
    final slugCanon = _publicSlugToCanonicalDocId[t.toLowerCase()];
    if (slugCanon != null && slugCanon.isNotEmpty) return slugCanon;
    return t;
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
    final operational = await resolveOperationalChurchDocId(
      seedId,
      userUid: userUid,
    );
    final op = operational.trim();
    if (op.isEmpty) return op;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final withDepts = await resolveChurchDocIdPreferringNonEmptyDepartments(op)
          .timeout(const Duration(seconds: 12));
      final deptId = withDepts.trim();
      if (deptId.isNotEmpty && deptId != op) return deptId;
    } catch (_) {}

    try {
      final rich = await resolveChurchDocIdPreferringRichestCluster(
        op,
        preferId: op,
      ).timeout(const Duration(seconds: 12));
      if (rich.trim().isNotEmpty) return rich.trim();
    } catch (_) {}

    return op;
  }

  /// Irmãos para leitura com fallback — `_sistema` e cluster ancorado primeiro; teto evita N× queries lentas.
  static List<String> orderedSiblingsForReadFallback(
    String primary,
    List<String> siblings, {
    int maxExtra = 8,
  }) {
    final p = primary.trim();
    if (p.isEmpty || siblings.isEmpty || maxExtra <= 0) return const [];

    final priority = <String>[];
    final rest = <String>[];

    void addUnique(List<String> bucket, String id) {
      final t = id.trim();
      if (t.isEmpty || t == p) return;
      if (priority.contains(t) || rest.contains(t)) return;
      bucket.add(t);
    }

    for (final entry in _anchoredChurchClusters.entries) {
      addUnique(priority, entry.key);
      for (final id in entry.value) {
        addUnique(priority, id);
      }
    }
    for (final s in siblings) {
      addUnique(rest, s);
    }
    for (final s in siblings) {
      if (s.trim().endsWith('_sistema')) addUnique(rest, s);
    }

    return <String>[...priority, ...rest].take(maxExtra).toList();
  }

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

  static const String _aliasesCollection = 'church_aliases';
  static final Map<String, _AliasCacheEntry> _aliasByKey = {};
  static const Duration _aliasCacheTtl = Duration(hours: 6);

  /// Mapa `church_aliases/{alias}` → `canonicalId` (fonte da verdade Firestore).
  static Future<String?> resolveChurchAlias(String rawAlias) async {
    final alias = rawAlias.trim();
    if (alias.isEmpty) return null;

    final hit = _aliasByKey[alias];
    if (hit != null &&
        DateTime.now().difference(hit.resolvedAt) < _aliasCacheTtl) {
      return hit.canonicalId;
    }

    await _ensureFirestore();
    try {
      final snap = await _firestore
          .collection(_aliasesCollection)
          .doc(alias)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      if (!snap.exists || snap.data() == null) return null;
      final canonical =
          (snap.data()!['canonicalId'] ?? '').toString().trim();
      if (canonical.isEmpty) return null;
      _aliasByKey[alias] = _AliasCacheEntry(canonical, DateTime.now());
      return canonical;
    } catch (_) {
      final mem = _aliasByKey[alias];
      return mem?.canonicalId;
    }
  }

  static void invalidateAliasCache({String? alias}) {
    if (alias == null || alias.trim().isEmpty) {
      _aliasByKey.clear();
      return;
    }
    _aliasByKey.remove(alias.trim());
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

  /// Resolve `igrejas/{id}` a partir do slug da URL pública (cadastro de membro / site).
  static Future<String?> resolveIgrejaDocIdFromPublicSlug(String rawSlug) async {
    final slugTrim = rawSlug.trim();
    if (slugTrim.isEmpty) return null;

    final slugLower = slugTrim.toLowerCase();
    final anchored = _publicSlugToCanonicalDocId[slugLower];
    if (anchored != null && anchored.isNotEmpty) return anchored;

    final fromAlias = await resolveChurchAlias(slugTrim);
    if (fromAlias != null && fromAlias.isNotEmpty) return fromAlias;

    await _ensureFirestore();
    for (final field in const ['slug', 'alias', 'slugId']) {
      try {
        final q = await _firestore
            .collection('igrejas')
            .where(field, isEqualTo: slugTrim)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) return q.docs.first.id;
      } catch (_) {}
    }

    final norm = slugLower.replaceAll(RegExp(r'[\s_\-]+'), '');
    for (final entry in _publicSlugToCanonicalDocId.entries) {
      final kNorm = entry.key.replaceAll(RegExp(r'[\s_\-]+'), '');
      if (kNorm == norm) return entry.value;
    }
    return null;
  }

  static String _normalize(String s) {
    if (s.isEmpty) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
  }

  /// Resolve o ID efetivo: tenant ou igreja. Se o id for de um doc em igrejas, retorna o próprio id.
  static Future<String> resolveEffectiveTenantId(String id) async {
    final raw = id.trim();
    if (raw.isEmpty) return id;

    final fromAlias = await resolveChurchAlias(raw);
    if (fromAlias != null && fromAlias.isNotEmpty) return fromAlias;

    await _ensureFirestore();
    try {
      final doc = await _firestore.collection('igrejas').doc(raw).get();
      if (doc.exists) return raw;
    } catch (_) {}

    final suffixFutures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    for (final suffix in ['_sistema', '_bpc']) {
      final withSuffix = raw.endsWith(suffix) ? raw : '$raw$suffix';
      if (withSuffix != raw) {
        suffixFutures.add(
            _firestore.collection('igrejas').doc(withSuffix).get());
      }
    }
    if (suffixFutures.isNotEmpty) {
      try {
        final snaps = await Future.wait(suffixFutures);
        for (final d in snaps) {
          if (d.exists) return d.id;
        }
      } catch (_) {}
    }

    final normalized = _normalize(raw);
    final slugQueries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    void q(String field, String value) {
      if (value.isEmpty) return;
      slugQueries.add(
        _firestore.collection('igrejas').where(field, isEqualTo: value).limit(1).get(),
      );
    }

    q('slug', raw);
    q('alias', raw);
    q('slugId', raw);
    q('churchId', raw);
    if (normalized.isNotEmpty) {
      q('slug', normalized);
      q('alias', normalized);
      q('slugId', normalized);
    }

    if (slugQueries.isNotEmpty) {
      try {
        final snaps = await Future.wait(slugQueries);
        for (final qs in snaps) {
          if (qs.docs.isNotEmpty) return qs.docs.first.id;
        }
      } catch (_) {}
    }

    if (normalized.isEmpty) return raw;

    try {
      final snapshot = await _firestore.collection('igrejas').limit(_scanLimit).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final slug = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
        final alias = (data['alias'] ?? '').toString().trim();
        final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
        final nSlug = _normalize(slug);
        final nAlias = _normalize(alias);
        final nNome = _normalize(nome);
        if (nSlug == normalized || nAlias == normalized || nNome == normalized) {
          return doc.id;
        }
        if (normalized.length >= 8 &&
            (nNome.contains(normalized) ||
                (nNome.isNotEmpty && normalized.contains(nNome)))) {
          return doc.id;
        }
      }
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
  static const Duration _operationalCacheTtl = Duration(minutes: 45);

  static String _operationalCacheKey(String seedId, String? userUid) =>
      '${(userUid ?? '').trim()}\x00${seedId.trim()}';

  /// ID canónico para subcoleções (`membros`, `escalas`, `agenda`, `event_templates`, …):
  /// vínculo em `users` + doc irmão com mais dados no cluster (slug / `_sistema`).
  static Future<String> resolveOperationalChurchDocId(
    String seedId, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final seed = seedId.trim();
    if (seed.isEmpty) return seed;

    final cacheKey = _operationalCacheKey(seed, userUid);
    if (!forceRefresh) {
      final hit = _operationalByKey[cacheKey];
      if (hit != null &&
          DateTime.now().difference(hit.resolvedAt) < _operationalCacheTtl) {
        return hit.id;
      }
    }

    String bound = seed;
    String claimId = '';
    try {
      bound = await resolveEffectiveTenantIdPreferringUserBinding(
        seed,
        userUid: userUid,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {}

    final uid = (userUid ?? '').trim();
    if (uid.isNotEmpty) {
      try {
        final u = await _firestore.collection('users').doc(uid).get();
        claimId =
            (u.data()?['igrejaId'] ?? u.data()?['tenantId'] ?? '').toString().trim();
      } catch (_) {}
    }

    List<String> siblings = const [];
    try {
      siblings = await getAllRelatedIgrejaDocIds(bound)
          .timeout(const Duration(seconds: 10));
    } catch (_) {}

    String operational = bound;
    try {
      operational = await _resolveCanonicalOperationalId(
        bound,
        claimId,
        siblings,
      ).timeout(const Duration(seconds: 14));
    } catch (_) {}

    _operationalByKey[cacheKey] =
        _OperationalTenantCacheEntry(operational, DateTime.now());
    AgentDebugLog.log(
      location: 'tenant_resolver_service.dart:resolveOperational',
      message: 'operational_id_resolved',
      hypothesisId: 'A',
      data: {
        'seed': seed,
        'bound': bound,
        'claimId': claimId,
        'operational': operational,
        'siblingsCount': siblings.length,
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
      return;
    }
    _operationalByKey.remove(_operationalCacheKey(seedId, userUid));
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
    bump('logoUrl');
    bump('logoProcessedUrl');
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
      preferServer: kIsWeb,
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
    final ordered = orderedSiblingsForReadFallback(primary, siblings, maxExtra: 8);
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

  /// IDs em `igrejas/` ligados ao mesmo slug/alias + variantes `_sistema`/`_bpc`.
  /// Evita ler centenas de documentos (antes: 2× scan em Membros e painel).
  static Future<List<String>> getAllRelatedIgrejaDocIds(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return const [];

    await _ensureFirestore();
    final result = <String>{raw};
    _addAnchoredClusterMembers(raw, result);

    Map<String, dynamic>? data;
    try {
      final snap = await _firestore.collection('igrejas').doc(raw).get();
      if (snap.exists) data = snap.data();
    } catch (_) {}

    var slug = '';
    var slugId = '';
    var alias = '';
    if (data != null) {
      slug = (data['slug'] ?? '').toString().trim();
      slugId = (data['slugId'] ?? '').toString().trim();
      alias = (data['alias'] ?? '').toString().trim();
    }

    final seenPairs = <String>{};
    final qFutures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    void addQ(String field, String value) {
      if (value.isEmpty) return;
      final key = '$field\x00$value';
      if (!seenPairs.add(key)) return;
      qFutures.add(
        _firestore.collection('igrejas').where(field, isEqualTo: value).limit(45).get(),
      );
    }

    addQ('slug', slug);
    addQ('slug', slugId);
    addQ('alias', alias);
    addQ('slugId', slugId);
    if (data == null) {
      addQ('slug', raw);
      addQ('alias', raw);
      addQ('slugId', raw);
    }

    if (qFutures.isNotEmpty) {
      try {
        final snaps = await Future.wait(qFutures);
        for (final s in snaps) {
          for (final d in s.docs) {
            result.add(d.id);
          }
        }
      } catch (_) {}
    }

    final docFutures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    for (final suffix in ['_sistema', '_bpc']) {
      final withSuffix = raw.endsWith(suffix) ? raw : '$raw$suffix';
      if (withSuffix != raw) {
        docFutures.add(_firestore.collection('igrejas').doc(withSuffix).get());
      }
      if (raw.endsWith(suffix)) {
        final baseId = raw.substring(0, raw.length - suffix.length).trim();
        if (baseId.isNotEmpty) {
          docFutures.add(_firestore.collection('igrejas').doc(baseId).get());
        }
      }
    }

    if (docFutures.isNotEmpty) {
      try {
        final snaps = await Future.wait(docFutures);
        for (final d in snaps) {
          if (d.exists) result.add(d.id);
        }
      } catch (_) {}
    }

    for (final id in List<String>.from(result)) {
      _addAnchoredClusterMembers(id, result);
    }

    return result.toList();
  }

  /// Hub de Departamentos / Escalas: se `igrejas/{resolved}/departamentos` estiver vazio mas um doc
  /// “irmão” (mesmo slug, [id]_sistema, [id]_bpc) tiver itens, usa esse id.
  ///
  /// **Performance:** antes lia `igrejas` (até 350 docs) e depois N leituras **sequenciais** a `departamentos`
  /// sempre em [Source.server] — o módulo Departamentos ficava minutos em loading. Agora: provas em **paralelo**
  /// com cache primeiro; o scan pesado de slug só corre se o id principal e variantes estiverem vazios.
  static Future<String> resolveChurchDocIdPreferringNonEmptyDepartments(
      String seedId) async {
    final resolved = await resolveEffectiveTenantId(seedId);
    final raw = resolved.trim();
    if (raw.isEmpty) return resolved;

    Future<String?> _probeDept(String tid, Source src) async {
      final t = tid.trim();
      if (t.isEmpty) return null;
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(() async {
          return _firestore
              .collection('igrejas')
              .doc(t)
              .collection('departamentos')
              .limit(1)
              .get(GetOptions(source: src))
              .timeout(const Duration(seconds: 14));
        });
        return snap.docs.isNotEmpty ? t : null;
      } on TimeoutException {
        return null;
      } catch (_) {
        return null;
      }
    }

    Future<String?> _firstNonEmptyParallel(
        List<String> ids, Source src) async {
      if (ids.isEmpty) return null;
      final out = await Future.wait(ids.map((id) => _probeDept(id, src)));
      for (final h in out) {
        if (h != null) return h;
      }
      return null;
    }

    final phase1 = <String>[];
    void addUnique(String x) {
      final t = x.trim();
      if (t.isEmpty) return;
      if (!phase1.contains(t)) phase1.add(t);
    }

    addUnique(raw);
    for (final suf in ['_sistema', '_bpc']) {
      if (raw.endsWith(suf)) {
        addUnique(raw.substring(0, raw.length - suf.length));
      } else {
        addUnique('$raw$suf');
      }
    }
    for (final anchoredId in anchoredClusterIdsFor(raw)) {
      addUnique(anchoredId);
    }

    var hit = await _firstNonEmptyParallel(phase1, Source.serverAndCache);
    if (hit != null) return hit;

    List<String> siblings = const [];
    try {
      siblings = await getAllRelatedIgrejaDocIds(raw);
    } catch (_) {
      siblings = const [];
    }
    final extra = siblings.where((id) => !phase1.contains(id)).toList();
    hit = await _firstNonEmptyParallel(extra, Source.serverAndCache);
    if (hit != null) return hit;

    hit = await _firstNonEmptyParallel(phase1, Source.server);
    if (hit != null) return hit;

    hit = await _firstNonEmptyParallel(extra, Source.server);
    if (hit != null) return hit;

    return raw;
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

  /// Retorna todos os IDs (tenants + igrejas) que compartilham slug/alias (consultas indexadas).
  static Future<List<String>> getAllTenantIdsWithSameSlugOrAlias(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return [raw];
    return getAllRelatedIgrejaDocIds(raw);
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
