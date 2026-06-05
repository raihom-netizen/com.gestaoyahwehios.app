import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Resolve o ID do tenant ou igreja para carregar membros.
/// Suporta tenants e igrejas (quando membros estão em igrejas/{id}/membros).
/// Normalização: "Brasil para Cristo" = "brasilparacristo" = "brasil-para-cristo".
class TenantResolverService {
  TenantResolverService._();

  static FirebaseFirestore get _firestore => firebaseDefaultFirestore;
  static const int _scanLimit = 350;

  static Future<void> _ensureFirestore() => ensureFirebaseReadyForPanelRead();

  static String _normalize(String s) {
    if (s.isEmpty) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
  }

  /// Resolve o ID efetivo: tenant ou igreja. Se o id for de um doc em igrejas, retorna o próprio id.
  static Future<String> resolveEffectiveTenantId(String id) async {
    final raw = id.trim();
    if (raw.isEmpty) return id;

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

    String operational = bound;
    try {
      final prefer = claimId.isNotEmpty ? claimId : null;
      operational = await resolveChurchDocIdPreferringRichestCluster(
        bound,
        preferId: prefer,
      ).timeout(const Duration(seconds: 22));
    } catch (_) {}

    _operationalByKey[cacheKey] =
        _OperationalTenantCacheEntry(operational, DateTime.now());
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
    bump('logoUrl');
    bump('logoProcessedUrl');
    if (data['registrationComplete'] == true) score += 3;
    return score;
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

    final opData = await readCacheDoc(operational);
    if (opData != null) {
      return (operationalId: operational, profile: opData);
    }
    if (operational != seed) {
      final seedData = await readCacheDoc(seed);
      if (seedData != null) {
        return (operationalId: seed, profile: seedData);
      }
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
    final profile = await _richestProfileInCluster(operational);
    _registrationByKey[cacheKey] = _RegistrationContextCacheEntry(
      operationalId: operational,
      profile: Map<String, dynamic>.from(profile),
      resolvedAt: DateTime.now(),
    );
    return (operationalId: operational, profile: profile);
  }

  static const int _richProfileEarlyExitScore = 14;

  /// Doc irmão com mais campos de cadastro (evita formulário vazio no «Cadastro da Igreja»).
  static Future<Map<String, dynamic>> _richestProfileInCluster(
    String operationalId, {
    bool scanSiblings = true,
  }) async {
    var best = <String, dynamic>{};
    var bestScore = -1;

    Future<void> consider(
      String id, {
      Source source = Source.serverAndCache,
      Duration timeout = const Duration(seconds: 8),
    }) async {
      final t = id.trim();
      if (t.isEmpty) return;
      try {
        final snap = await _firestore
            .collection('igrejas')
            .doc(t)
            .get(GetOptions(source: source))
            .timeout(timeout);
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final sc = _churchProfileScore(data);
        if (sc > bestScore) {
          bestScore = sc;
          best = Map<String, dynamic>.from(data);
        }
      } catch (_) {}
    }

    await consider(
      operationalId,
      source: Source.cache,
      timeout: const Duration(milliseconds: 700),
    );
    if (bestScore >= _richProfileEarlyExitScore) return best;

    await consider(operationalId);
    if (bestScore >= _richProfileEarlyExitScore || !scanSiblings) return best;

    try {
      final siblings = await getAllRelatedIgrejaDocIds(operationalId)
          .timeout(const Duration(seconds: 10));
      final others = siblings
          .where((s) => s.trim().isNotEmpty && s.trim() != operationalId.trim())
          .toList();
      if (others.isNotEmpty) {
        await Future.wait(others.map((s) => consider(s)));
      }
    } catch (_) {}

    return best;
  }

  /// IDs em `igrejas/` ligados ao mesmo slug/alias + variantes `_sistema`/`_bpc`.
  /// Evita ler centenas de documentos (antes: 2× scan em Membros e painel).
  static Future<List<String>> getAllRelatedIgrejaDocIds(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return const [];

    await _ensureFirestore();
    final result = <String>{raw};

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
        final snap = await _firestore
            .collection('igrejas')
            .doc(t)
            .collection('departamentos')
            .limit(1)
            .get(GetOptions(source: src))
            .timeout(const Duration(seconds: 14));
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
