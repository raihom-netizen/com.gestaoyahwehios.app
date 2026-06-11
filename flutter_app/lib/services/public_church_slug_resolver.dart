import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Igreja resolvida a partir do slug da URL pública (`/igreja/{slug}`).
class PublicChurchResolved {
  const PublicChurchResolved({
    required this.churchId,
    required this.profile,
    this.slugKey = '',
    this.logoUrl,
  });

  final String churchId;
  final Map<String, dynamic> profile;
  final String slugKey;
  final String? logoUrl;
}

/// Resolução rápida slug → igreja — índice `public_church_slugs` + doc directo (sem cluster).
abstract final class PublicChurchSlugResolver {
  PublicChurchSlugResolver._();

  static final Map<String, _RamEntry> _ram = {};
  static const Duration _ramTtl = Duration(minutes: 20);

  static String normalizeSlugKey(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\s_]+'), '-');
    s = s.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    s = s.replaceAll(RegExp(r'-+'), '-');
    return s.replaceAll(RegExp(r'^-|-$'), '');
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

  /// Caminho único para site público, cadastro membro e deep links.
  static Future<PublicChurchResolved?> resolve(String rawSlug) async {
    final slug = rawSlug.trim();
    if (slug.isEmpty) return null;

    final cached = _peekRam(slug);
    if (cached != null) return cached;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final canonical =
        TenantResolverService.mapLegacySeedToCanonical(slug) ?? slug;

    String churchId = canonical;
    String? indexName;
    String? indexLogo;

    try {
      for (final key in <String>{
        normalizeSlugKey(slug),
        normalizeSlugKey(canonical),
      }..removeWhere((e) => e.isEmpty)) {
        final snap = await firebaseDefaultFirestore
            .collection('public_church_slugs')
            .doc(key)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 4));
        if (!snap.exists || snap.data() == null) continue;
        final d = snap.data()!;
        final cid = (d['churchId'] ?? '').toString().trim();
        if (cid.isNotEmpty) {
          churchId = cid;
          indexName = (d['churchName'] ?? '').toString().trim();
          final logo = (d['logoUrl'] ?? '').toString().trim();
          indexLogo = logo.isNotEmpty ? logo : null;
          break;
        }
      }
    } catch (_) {}

    Map<String, dynamic> profile = {};
    try {
      final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(
        churchId,
      ).timeout(const Duration(seconds: kIsWeb ? 10 : 8));
      if (hit != null && hit.data.isNotEmpty) {
        profile = hit.data;
        churchId = hit.docId;
      }
    } catch (_) {}

    if (profile.isEmpty && churchId != slug) {
      try {
        final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(slug)
            .timeout(const Duration(seconds: 6));
        if (hit != null && hit.data.isNotEmpty) {
          profile = hit.data;
          churchId = hit.docId;
        }
      } catch (_) {}
    }

    if (profile.isEmpty) {
      try {
        final q = await firebaseDefaultFirestore
            .collection('igrejas')
            .where('slug', isEqualTo: slug)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
        if (q.docs.isNotEmpty) {
          profile = Map<String, dynamic>.from(q.docs.first.data());
          churchId = q.docs.first.id;
        }
      } catch (_) {}
    }

    if (profile.isEmpty) return null;

    if (indexName != null && indexName.isNotEmpty) {
      profile.putIfAbsent('name', () => indexName);
      profile.putIfAbsent('nome', () => indexName);
    }

    final out = PublicChurchResolved(
      churchId: churchId,
      profile: profile,
      slugKey: normalizeSlugKey(slug),
      logoUrl: indexLogo,
    );
    _putRam(slug, out);
    return out;
  }
}

class _RamEntry {
  _RamEntry(this.value, this.at);
  final PublicChurchResolved value;
  final DateTime at;
}
