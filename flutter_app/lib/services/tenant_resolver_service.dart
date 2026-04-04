import 'package:cloud_firestore/cloud_firestore.dart';

/// Resolve o ID do tenant ou igreja para carregar membros.
/// Suporta tenants e igrejas (quando membros estão em igrejas/{id}/membros).
/// Normalização: "Brasil para Cristo" = "brasilparacristo" = "brasil-para-cristo".
class TenantResolverService {
  TenantResolverService._();

  static final _firestore = FirebaseFirestore.instance;
  static const int _scanLimit = 350;

  static String _normalize(String s) {
    if (s.isEmpty) return '';
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
  }

  /// Resolve o ID efetivo: tenant ou igreja. Se o id for de um doc em igrejas, retorna o próprio id.
  static Future<String> resolveEffectiveTenantId(String id) async {
    final raw = id.trim();
    if (raw.isEmpty) return id;

    // 1) Existe em tenants
    try {
      final doc = await _firestore.collection('igrejas').doc(raw).get();
      if (doc.exists) return raw;
    } catch (_) {}

    // 2) Existe em igrejas (membros podem estar em igrejas/{id}/membros)
    try {
      final igrejaDoc = await _firestore.collection('igrejas').doc(raw).get();
      if (igrejaDoc.exists) return raw;
    } catch (_) {}

    // 2b) Brasil para Cristo e similares: tenant pode ser id_sistema (ex.: brasilparacristo_sistema)
    for (final suffix in ['_sistema', '_bpc']) {
      final withSuffix = raw.endsWith(suffix) ? raw : '$raw$suffix';
      if (withSuffix == raw) continue;
      try {
        final t = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (t.exists) return withSuffix;
      } catch (_) {}
      try {
        final i = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (i.exists) return withSuffix;
      } catch (_) {}
    }

    // 3) Busca por slug/alias em tenants
    try {
      final bySlug = await _firestore.collection('igrejas').where('slug', isEqualTo: raw).limit(1).get();
      if (bySlug.docs.isNotEmpty) return bySlug.docs.first.id;
    } catch (_) {}
    try {
      final byAlias = await _firestore.collection('igrejas').where('alias', isEqualTo: raw).limit(1).get();
      if (byAlias.docs.isNotEmpty) return byAlias.docs.first.id;
    } catch (_) {}

    final normalized = _normalize(raw);
    if (normalized.isEmpty) return raw;

    try {
      final bySlugNorm = await _firestore.collection('igrejas').where('slug', isEqualTo: normalized).limit(1).get();
      if (bySlugNorm.docs.isNotEmpty) return bySlugNorm.docs.first.id;
    } catch (_) {}
    try {
      final byAliasNorm = await _firestore.collection('igrejas').where('alias', isEqualTo: normalized).limit(1).get();
      if (byAliasNorm.docs.isNotEmpty) return byAliasNorm.docs.first.id;
    } catch (_) {}

    // 4) Varredura tenants (nome pode ser "Igreja Brasil para Cristo" -> normalizado contém "brasilparacristo")
    try {
      final snapshot = await _firestore.collection('igrejas').limit(_scanLimit).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final slug = (data['slug'] ?? '').toString().trim();
        final alias = (data['alias'] ?? '').toString().trim();
        final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
        final nSlug = _normalize(slug);
        final nAlias = _normalize(alias);
        final nNome = _normalize(nome);
        if (nSlug == normalized || nAlias == normalized || nNome == normalized) return doc.id;
        if (normalized.length >= 8 && (nNome.contains(normalized) || (nNome.isNotEmpty && normalized.contains(nNome)))) return doc.id;
      }
    } catch (_) {}

    // 5) Varredura igrejas (se não achou em tenants)
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
        if (nSlug == normalized || nAlias == normalized || nNome == normalized) return doc.id;
        if (normalized.length >= 8 && (nNome.contains(normalized) || (nNome.isNotEmpty && normalized.contains(nNome)))) return doc.id;
      }
    } catch (_) {}

    return raw;
  }

  /// Hub de Departamentos / Escalas: se `igrejas/{resolved}/departamentos` estiver vazio mas um doc
  /// “irmão” (mesmo slug, [id]_sistema, [id]_bpc) tiver itens, usa esse id.
  ///
  /// Também cobre catálogo gravado sob outro id enquanto o painel resolve slug → doc principal sem subcoleção.
  static Future<String> resolveChurchDocIdPreferringNonEmptyDepartments(
      String seedId) async {
    final resolved = await resolveEffectiveTenantId(seedId);
    final raw = resolved.trim();
    if (raw.isEmpty) return resolved;

    final candidates = <String>[];
    void add(String x) {
      final t = x.trim();
      if (t.isEmpty) return;
      if (!candidates.contains(t)) candidates.add(t);
    }

    add(raw);
    for (final suf in ['_sistema', '_bpc']) {
      if (raw.endsWith(suf)) {
        add(raw.substring(0, raw.length - suf.length));
      } else {
        add('$raw$suf');
      }
    }
    try {
      for (final id in await getIgrejaIdsWithSameSlugOrAlias(raw)) {
        add(id);
      }
    } catch (_) {}

    for (final tid in candidates) {
      try {
        final snap = await _firestore
            .collection('igrejas')
            .doc(tid)
            .collection('departamentos')
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (snap.docs.isNotEmpty) {
          return tid;
        }
      } catch (_) {}
    }
    return raw;
  }

  /// Retorna todos os IDs (tenants + igrejas) que compartilham slug, alias ou nome.
  static Future<List<String>> getAllTenantIdsWithSameSlugOrAlias(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return [raw];
    final result = <String>{raw};
    String normSlug = _normalize(raw);
    String normAlias = normSlug;
    String normNome = '';

    try {
      final tenantDoc = await _firestore.collection('igrejas').doc(raw).get();
      if (tenantDoc.exists) {
        final data = tenantDoc.data() ?? {};
        final slug = (data['slug'] ?? '').toString().trim();
        final alias = (data['alias'] ?? '').toString().trim();
        final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
        normSlug = slug.isEmpty ? normSlug : _normalize(slug);
        normAlias = alias.isEmpty ? normSlug : _normalize(alias);
        normNome = _normalize(nome);
      } else {
        final igrejaDoc = await _firestore.collection('igrejas').doc(raw).get();
        if (igrejaDoc.exists) {
          final data = igrejaDoc.data() ?? {};
          final slug = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
          final alias = (data['alias'] ?? '').toString().trim();
          final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
          normSlug = slug.isEmpty ? normSlug : _normalize(slug);
          normAlias = alias.isEmpty ? normSlug : _normalize(alias);
          normNome = _normalize(nome);
        }
      }
    } catch (_) {}

    try {
      final tenantSnap = await _firestore.collection('igrejas').limit(_scanLimit).get();
      for (final d in tenantSnap.docs) {
        final id = d.id;
        if (result.contains(id)) continue;
        final data = d.data();
        final s = (data['slug'] ?? '').toString().trim();
        final a = (data['alias'] ?? '').toString().trim();
        final n = (data['nome'] ?? data['name'] ?? '').toString().trim();
        final nNorm = _normalize(n);
        if (normSlug.isNotEmpty &&
            (_normalize(s) == normSlug ||
                _normalize(a) == normSlug ||
                nNorm == normSlug)) {
          result.add(id);
        } else if (normAlias.isNotEmpty &&
            normAlias != normSlug &&
            (_normalize(s) == normAlias ||
                _normalize(a) == normAlias ||
                nNorm == normAlias)) {
          result.add(id);
        } else if (normNome.length >= 6 &&
            (nNorm == normNome ||
                nNorm.contains(normSlug) ||
                (normSlug.isNotEmpty && nNorm.contains(normSlug)))) {
          result.add(id);
        }
      }
    } catch (_) {}

    // Inclui variantes _sistema / _bpc (ex.: Brasil para Cristo)
    for (final suffix in ['_sistema', '_bpc']) {
      final withSuffix = '$raw$suffix';
      if (result.contains(withSuffix)) continue;
      try {
        final t = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (t.exists) result.add(withSuffix);
      } catch (_) {}
      try {
        final i = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (i.exists) result.add(withSuffix);
      } catch (_) {}
    }
    // Se o id tem sufixo (_sistema, _bpc), inclui o id BASE — membros podem estar em igrejas/brasilparacristo/membros
    for (final suffix in ['_sistema', '_bpc']) {
      if (!raw.endsWith(suffix)) continue;
      final baseId = raw.substring(0, raw.length - suffix.length).trim();
      if (baseId.isEmpty || result.contains(baseId)) continue;
      try {
        final t = await _firestore.collection('igrejas').doc(baseId).get();
        if (t.exists) result.add(baseId);
      } catch (_) {}
      try {
        final i = await _firestore.collection('igrejas').doc(baseId).get();
        if (i.exists) result.add(baseId);
      } catch (_) {}
    }

    return result.toList();
  }

  /// Retorna IDs em igrejas com mesmo slug/alias/nome. SEMPRE inclui raw se igrejas/raw existir.
  static Future<List<String>> getIgrejaIdsWithSameSlugOrAlias(String resolvedTenantId) async {
    final raw = resolvedTenantId.trim();
    if (raw.isEmpty) return [];
    final result = <String>{};

    String normSlug = _normalize(raw);
    String normAlias = normSlug;
    String normNome = '';
    String slug = '';
    String alias = '';

    try {
      final tenantDoc = await _firestore.collection('igrejas').doc(raw).get();
      if (tenantDoc.exists) {
        final data = tenantDoc.data() ?? {};
        slug = (data['slug'] ?? '').toString().trim();
        alias = (data['alias'] ?? '').toString().trim();
        final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
        normSlug = slug.isEmpty ? normSlug : _normalize(slug);
        normAlias = alias.isEmpty ? normSlug : _normalize(alias);
        normNome = _normalize(nome);
      } else {
        final igrejaDoc = await _firestore.collection('igrejas').doc(raw).get();
        if (igrejaDoc.exists) {
          result.add(raw);
          final data = igrejaDoc.data() ?? {};
          slug = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
          alias = (data['alias'] ?? '').toString().trim();
          final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
          normSlug = slug.isEmpty ? normSlug : _normalize(slug);
          normAlias = alias.isEmpty ? normSlug : _normalize(alias);
          normNome = _normalize(nome);
        }
      }
    } catch (_) {}

    try {
      final snapshot = await _firestore.collection('igrejas').limit(_scanLimit).get();
      for (final d in snapshot.docs) {
        final id = d.id;
        final data = d.data();
        final s = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
        final a = (data['alias'] ?? '').toString().trim();
        final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
        final nS = s.isEmpty ? '' : _normalize(s);
        final nA = a.isEmpty ? '' : _normalize(a);
        final nNome = _normalize(nome);

        if (normSlug.isNotEmpty && (nS == normSlug || nA == normSlug || nNome == normSlug)) result.add(id);
        else if (normAlias.isNotEmpty && (nS == normAlias || nA == normAlias || nNome == normAlias)) result.add(id);
        else if (slug.isNotEmpty && (s == slug || a == slug)) result.add(id);
        else if (alias.isNotEmpty && (s == alias || a == alias)) result.add(id);
        else if (normNome.length >= 6 && (nNome.contains(normSlug) || nNome == normNome)) result.add(id);
        else if (normSlug.length >= 5 && nNome.contains(normSlug.substring(0, normSlug.length > 8 ? 8 : normSlug.length))) result.add(id);
      }
    } catch (_) {}

    // Inclui variantes _sistema / _bpc (ex.: Brasil para Cristo)
    for (final suffix in ['_sistema', '_bpc']) {
      final withSuffix = '$raw$suffix';
      if (result.contains(withSuffix)) continue;
      try {
        final i = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (i.exists) result.add(withSuffix);
      } catch (_) {}
      try {
        final t = await _firestore.collection('igrejas').doc(withSuffix).get();
        if (t.exists) result.add(withSuffix);
      } catch (_) {}
    }
    // Se o id tem sufixo, inclui o id BASE — membros podem estar em igrejas/brasilparacristo/membros
    for (final suffix in ['_sistema', '_bpc']) {
      if (!raw.endsWith(suffix)) continue;
      final baseId = raw.substring(0, raw.length - suffix.length).trim();
      if (baseId.isEmpty || result.contains(baseId)) continue;
      try {
        final i = await _firestore.collection('igrejas').doc(baseId).get();
        if (i.exists) result.add(baseId);
      } catch (_) {}
      try {
        final t = await _firestore.collection('igrejas').doc(baseId).get();
        if (t.exists) result.add(baseId);
      } catch (_) {}
    }

    return result.toList();
  }
}
