import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Carga da galeria de clientes (site divulgação).
///
/// Fontes (ordem):
/// 1. Firestore `app_public/marketing_clientes` → campo `items`
/// 2. Storage legado `public/gestao_yahweh/clientes/{id}/capa.jpg` (ou .webp/.png)
abstract final class MarketingClientesLoadService {
  MarketingClientesLoadService._();

  static DocumentReference<Map<String, dynamic>> get docRef =>
      firebaseDefaultFirestore
          .collection(MarketingStorageLayout.firestoreCollection)
          .doc(MarketingStorageLayout.firestoreMarketingClientesDocId);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchDoc() =>
      FirestoreStreamUtils.documentWatchBootstrap(docRef);

  static List<Map<String, dynamic>> parseItems(Map<String, dynamic>? data) {
    final raw = data?['items'];
    if (raw is! List) return [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => m['ativo'] != false)
        .toList()
      ..sort((a, b) {
        final oa = (a['ordem'] is num) ? (a['ordem'] as num).toInt() : 0;
        final ob = (b['ordem'] is num) ? (b['ordem'] as num).toInt() : 0;
        return oa.compareTo(ob);
      });
  }

  static String _humanizeFolderId(String id) {
    var s = id.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (s.isEmpty) return 'Igreja parceira';
    if (s.length <= 3) return s.toUpperCase();
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.length <= 2
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  static const _capaNames = [
    'capa.jpg',
    'capa.jpeg',
    'capa.webp',
    'capa.png',
    'logo.jpg',
    'logo.webp',
    'logo.png',
  ];

  /// Varre `public/gestao_yahweh/clientes/{pasta}/` — logos legadas no Storage.
  static Future<List<Map<String, dynamic>>> loadFromStorageLegacy({
    int maxClientes = 48,
  }) async {
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    }
    final out = <Map<String, dynamic>>[];
    try {
      final root =
          firebaseDefaultStorage.ref(MarketingStorageLayout.clientesRootPrefix);
      final listed = await root.listAll().timeout(
        const Duration(seconds: 18),
        onTimeout: () => throw TimeoutException('list clientes'),
      );
      var ordem = 0;
      for (final prefix in listed.prefixes) {
        if (out.length >= maxClientes) break;
        final folderId = prefix.name.trim();
        if (folderId.isEmpty || folderId.startsWith('.')) continue;

        String? fotoPath;
        try {
          final files = await prefix.listAll().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('list capa'),
          );
          for (final name in _capaNames) {
            final hit = files.items.where((r) => r.name.toLowerCase() == name);
            if (hit.isNotEmpty) {
              fotoPath = MarketingStorageLayout.normalizeObjectPath(
                hit.first.fullPath,
              );
              break;
            }
          }
          if (fotoPath == null) {
            for (final r in files.items) {
              final n = r.name.toLowerCase();
              if (n.endsWith('.jpg') ||
                  n.endsWith('.jpeg') ||
                  n.endsWith('.webp') ||
                  n.endsWith('.png')) {
                fotoPath =
                    MarketingStorageLayout.normalizeObjectPath(r.fullPath);
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('MarketingClientesLoadService capa $folderId: $e');
          fotoPath = MarketingStorageLayout.legacyClienteShowcasePhotoPath(
            folderId,
          );
        }

        out.add({
          'id': folderId,
          'nomeIgreja': _humanizeFolderId(folderId),
          'fotoPath': fotoPath ?? '',
          'ativo': true,
          'ordem': ordem++,
          '_source': 'storage_legacy',
        });
      }
    } catch (e, st) {
      debugPrint('MarketingClientesLoadService storage: $e\n$st');
    }
    return out;
  }

  /// Firestore → se vazio, Storage legado `public/gestao_yahweh/clientes/`.
  static Future<({
    List<Map<String, dynamic>> items,
    Map<String, dynamic>? docData,
    String? warning,
  })> loadResolved() async {
    Map<String, dynamic>? docData;
    try {
      final snap = await docRef.get().timeout(const Duration(seconds: 12));
      if (snap.exists) {
        docData = snap.data();
      }
    } catch (e) {
      debugPrint('MarketingClientesLoadService Firestore: $e');
    }

    var items = parseItems(docData);
    if (items.isNotEmpty) {
      return (items: items, docData: docData, warning: null);
    }

    final legacy = await loadFromStorageLegacy();
    if (legacy.isNotEmpty) {
      return (
        items: legacy,
        docData: docData,
        warning: null,
      );
    }

    return (
      items: <Map<String, dynamic>>[],
      docData: docData,
      warning: 'Nenhuma igreja em destaque. Cadastre em Divulgação → Clientes ou envie capas para '
          '${MarketingStorageLayout.clientesRootPrefix}/[id]/capa.jpg no Storage.',
    );
  }
}
