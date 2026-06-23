import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/panel_public_site_snapshot_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Igreja resolvida a partir do slug da URL pública (`/igreja/{slug}`).
class PublicChurchResolved {
  const PublicChurchResolved({
    required this.churchId,
    required this.profile,
    this.slugKey = '',
    this.logoUrl,
    this.fromIndexOnly = false,
  });

  final String churchId;
  final Map<String, dynamic> profile;
  final String slugKey;
  final String? logoUrl;

  /// `true` quando ainda falta perfil completo (endereço, contactos, …).
  final bool fromIndexOnly;
}

/// Resolução rápida slug → igreja — índice `public_church_slugs` + doc directo (sem cluster).
abstract final class PublicChurchSlugResolver {
  PublicChurchSlugResolver._();

  static final Map<String, _RamEntry> _ram = {};
  static const Duration _ramTtl = Duration(minutes: 20);

  /// Normaliza entradas vindas de URL/path (`/igreja/{slug}`, URL completa,
  /// slug simples) para a chave de slug público.
  static String normalizePublicSlugInput(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return '';
    try {
      input = Uri.decodeComponent(input);
    } catch (_) {}
    input = input.replaceAll('\\', '/');
    if (input.startsWith('http://') || input.startsWith('https://')) {
      final uri = Uri.tryParse(input);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        input = uri.pathSegments.join('/');
      }
    }
    input = input.split('?').first.split('#').first.trim();
    final segments = input
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isNotEmpty) {
      final idxIgreja = segments.lastIndexWhere(
        (s) => s.toLowerCase() == 'igreja',
      );
      if (idxIgreja >= 0 && idxIgreja + 1 < segments.length) {
        input = segments[idxIgreja + 1];
      } else {
        input = segments.last;
      }
    }
    return normalizeSlugKey(input);
  }

  static String normalizeSlugKey(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\s_]+'), '-');
    s = s.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    s = s.replaceAll(RegExp(r'-+'), '-');
    return s.replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Leitura instantânea da RAM (sem rede).
  static PublicChurchResolved? peek(String rawSlug) {
    final cached = _peekRam(rawSlug);
    if (cached != null && !cached.fromIndexOnly) return cached;
    return cached;
  }

  static PublicChurchResolved? _peekRam(String slug) {
    final key = normalizeSlugKey(slug);
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return hit.value;
  }

  static void _putRam(String slug, PublicChurchResolved value) {
    final key = normalizeSlugKey(slug);
    if (key.isEmpty) return;
    _ram[key] = _RamEntry(value, DateTime.now());
  }

  static bool _profileLooksComplete(Map<String, dynamic> p) {
    final nome = (p['nome'] ?? p['name'] ?? '').toString().trim();
    if (nome.isEmpty) return false;
    return (p['endereco'] ?? p['rua'] ?? '').toString().trim().isNotEmpty ||
        (p['whatsapp'] ??
                p['telefone'] ??
                p['whatsappIgreja'] ??
                p['telefoneIgreja'] ??
                '')
            .toString()
            .trim()
            .isNotEmpty ||
        (p['gestorEmail'] ?? p['email'] ?? '').toString().trim().isNotEmpty ||
        (p['cidade'] ?? '').toString().trim().isNotEmpty;
  }

  static Map<String, dynamic> _mergeProfiles(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final out = Map<String, dynamic>.from(base);
    for (final e in overlay.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      out[e.key] = v;
    }
    return out;
  }

  static PublicChurchResolved _fromIndexMap({
    required String slug,
    required String churchId,
    required Map<String, dynamic> d,
  }) {
    final indexName = (d['churchName'] ?? '').toString().trim();
    final logo = (d['logoUrl'] ?? '').toString().trim();
    final endereco = (d['churchAddress'] ?? d['endereco'] ?? '').toString().trim();
    final cidade = (d['cidade'] ?? '').toString().trim();
    final estado = (d['estado'] ?? '').toString().trim();
    final profile = <String, dynamic>{
      if (indexName.isNotEmpty) ...{'nome': indexName, 'name': indexName},
      if (logo.isNotEmpty) 'logoUrl': logo,
      if (endereco.isNotEmpty) 'endereco': endereco,
      if (cidade.isNotEmpty) 'cidade': cidade,
      if (estado.isNotEmpty) 'estado': estado,
      'slug': normalizeSlugKey(slug),
    };
    return PublicChurchResolved(
      churchId: churchId,
      profile: profile,
      slugKey: normalizeSlugKey(slug),
      logoUrl: logo.isNotEmpty ? logo : null,
      fromIndexOnly: true,
    );
  }

  static Future<({String churchId, Map<String, dynamic> index})?> _readSlugIndex(
    String slug,
    String canonical,
  ) async {
    for (final key in <String>{
      normalizeSlugKey(slug),
      normalizeSlugKey(canonical),
    }..removeWhere((e) => e.isEmpty)) {
      try {
        final snap = await firebaseDefaultFirestore
            .collection('public_church_slugs')
            .doc(key)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 3));
        if (!snap.exists || snap.data() == null) continue;
        final d = snap.data()!;
        final cid = (d['churchId'] ?? '').toString().trim();
        if (cid.isNotEmpty) return (churchId: cid, index: d);
      } catch (_) {}
    }
    return null;
  }

  /// 1 leitura no índice — first paint imediato (site + cadastro membro).
  static Future<PublicChurchResolved?> resolveFast(String rawSlug) async {
    final slug = rawSlug.trim();
    if (slug.isEmpty) return null;

    final cached = _peekRam(slug);
    if (cached != null) return cached;

    if (kIsWeb) {
      unawaited(FirestoreWebGuard.ensurePanelReadReady().catchError((_) {}));
    }

    final canonical =
        TenantResolverService.mapLegacySeedToCanonical(slug) ?? slug;

    final indexHit = await _readSlugIndex(slug, canonical);
    if (indexHit == null) return null;

    var out = _fromIndexMap(
      slug: slug,
      churchId: indexHit.churchId,
      d: indexHit.index,
    );

    try {
      final panel = await PanelPublicSiteSnapshotService.readOnce(out.churchId)
          .timeout(const Duration(seconds: 2));
      if (panel.hasData) {
        final overlay = <String, dynamic>{
          if (panel.churchName.isNotEmpty) ...{
            'nome': panel.churchName,
            'name': panel.churchName,
          },
          if ((panel.churchLogoUrl ?? '').isNotEmpty)
            'logoUrl': panel.churchLogoUrl,
          if (panel.churchSlug.isNotEmpty) 'slug': panel.churchSlug,
        };
        out = PublicChurchResolved(
          churchId: out.churchId,
          profile: _mergeProfiles(out.profile, overlay),
          slugKey: out.slugKey,
          logoUrl: panel.churchLogoUrl ?? out.logoUrl,
          fromIndexOnly: true,
        );
      }
    } catch (_) {}

    _putRam(slug, out);
    return out;
  }

  /// Completa perfil público em background (doc `igrejas/{id}`).
  static Future<PublicChurchResolved?> resolveEnrich(
    String rawSlug, {
    PublicChurchResolved? seed,
  }) async {
    final slug = rawSlug.trim();
    if (slug.isEmpty) return seed;

    final base = seed ?? await resolveFast(slug);
    if (base == null) return null;
    if (!base.fromIndexOnly && _profileLooksComplete(base.profile)) {
      return base;
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    var churchId = base.churchId;
    var profile = Map<String, dynamic>.from(base.profile);

    try {
      final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(
        churchId,
      ).timeout(const Duration(seconds: 10));
      if (hit != null && hit.data.isNotEmpty) {
        profile = _mergeProfiles(profile, hit.data);
        churchId = hit.docId;
      }
    } catch (_) {}

    if (!_profileLooksComplete(profile) && churchId != slug) {
      try {
        final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(slug)
            .timeout(const Duration(seconds: 6));
        if (hit != null && hit.data.isNotEmpty) {
          profile = _mergeProfiles(profile, hit.data);
          churchId = hit.docId;
        }
      } catch (_) {}
    }

    if (!_profileLooksComplete(profile)) {
      try {
        final q = await firebaseDefaultFirestore
            .collection('igrejas')
            .where('slug', isEqualTo: slug)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
        if (q.docs.isNotEmpty) {
          profile = _mergeProfiles(profile, q.docs.first.data());
          churchId = q.docs.first.id;
        }
      } catch (_) {}
    }

    if (profile.isEmpty) return base.fromIndexOnly ? base : null;

    final out = PublicChurchResolved(
      churchId: churchId,
      profile: profile,
      slugKey: base.slugKey.isNotEmpty ? base.slugKey : normalizeSlugKey(slug),
      logoUrl: (profile['logoUrl'] ?? base.logoUrl)?.toString(),
      fromIndexOnly: false,
    );
    _putRam(slug, out);
    return out;
  }

  /// Caminho completo (fast + enrich) — compatível com callers legados.
  static Future<PublicChurchResolved?> resolve(String rawSlug) async {
    final fast = await resolveFast(rawSlug);
    if (fast == null) return null;
    return resolveEnrich(rawSlug, seed: fast);
  }
}

class _RamEntry {
  _RamEntry(this.value, this.at);
  final PublicChurchResolved value;
  final DateTime at;
}
