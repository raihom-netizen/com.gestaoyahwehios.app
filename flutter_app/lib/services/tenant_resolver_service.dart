import 'dart:async' show TimeoutException;

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

  /// IDs em `igrejas/` ligados ao mesmo slug/alias + variantes `_sistema`/`_bpc`.
  /// Evita ler centenas de documentos (antes: 2× scan em Membros e painel).
  static Future<List<String>> getAllRelatedIgrejaDocIds(String resolvedId) async {
    final raw = resolvedId.trim();
    if (raw.isEmpty) return const [];

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
