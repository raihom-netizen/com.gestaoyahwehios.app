import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/storage/firebase_storage_listing_support.dart';

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
        .map(
          (w) => w.length <= 2
              ? w.toUpperCase()
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
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
      final root = firebaseDefaultStorage.ref(
        MarketingStorageLayout.clientesRootPrefix,
      );
      // Windows/Linux: listagem nao existe no SDK C++ e o processo morre.
      if (!firebaseStorageListingSupported) return const [];
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
          // (sem guarda aqui: a do topo de loadFromStorageLegacy já impediu
          // de chegar a este ponto em Windows/Linux)
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
                fotoPath = MarketingStorageLayout.normalizeObjectPath(
                  r.fullPath,
                );
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

  /// Recarrega cada item da galeria a partir de `igrejas/{id}` — o que o gestor
  /// preenche no cadastro aparece no site de divulgação sem republicar.
  static Future<List<Map<String, dynamic>>> hydrateFromChurchDocs(
    List<Map<String, dynamic>> items,
  ) => _refreshPublishedItems(items);

  static Future<List<Map<String, dynamic>>> _refreshPublishedItems(
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return items;
    return Future.wait(
      items.map((item) async {
        final id =
            (item['tenantId'] ?? item['igrejaTenantId'] ?? item['id'] ?? '')
                .toString()
                .trim();
        if (id.isEmpty) return item;
        try {
          final snap = await ChurchRepository.churchDoc(
            id,
          ).get().timeout(const Duration(seconds: 5));
          final source = snap.data();
          if (source == null || source.isEmpty) return item;
          final out = <String, dynamic>{...item};
          String value(List<String> keys) {
            for (final key in keys) {
              final v = source[key]?.toString().trim() ?? '';
              if (v.isNotEmpty) return v;
            }
            return '';
          }

          void setIfPresent(String key, List<String> aliases) {
            final v = value(aliases);
            if (v.isNotEmpty) out[key] = v;
          }

          setIfPresent('nomeIgreja', ['nome', 'name', 'nomeIgreja']);
          setIfPresent('pastor', [
            'pastor',
            'pastorNome',
            'pastor_nome',
            'nomePastor',
            'pastorPrincipal',
            'PASTOR',
            'responsavel',
          ]);
          setIfPresent('gestor', [
            'gestorNome',
            'gestor_nome',
            'nomeGestor',
            'gestor',
            'responsavel',
          ]);
          setIfPresent('whatsapp', [
            'whatsapp',
            'whatsappChatUrl',
            'telefone',
            'telefone1',
            'celular',
            'phone',
          ]);
          setIfPresent('site', ['sitePublico', 'siteUrl', 'website', 'site']);
          setIfPresent('localizacao', [
            'localizacao',
            'enderecoCompleto',
            'endereco',
            'ENDERECO',
            'cidade',
          ]);
          setIfPresent('logoUrl', ['logoUrl', 'urlLogo', 'logo']);
          setIfPresent('logoPath', [
            'logoPath',
            'logoStoragePath',
            'storageLogoPath',
          ]);
          setIfPresent('slug', ['slug', 'slugId']);
          // Sem campo de site guardado: o site público da igreja é derivado do
          // slug — assim o botão «Site» aparece assim que o slug existe.
          if ((out['site']?.toString().trim() ?? '').isEmpty) {
            final slug = value(['slug', 'slugId']);
            if (slug.isNotEmpty) {
              out['site'] = 'https://gestaoyahweh.com.br/$slug';
            }
          }
          return out;
        } catch (_) {
          return item;
        }
      }),
    );
  }

  /// Firestore → se vazio, Storage legado `public/gestao_yahweh/clientes/`.
  static Future<
    ({
      List<Map<String, dynamic>> items,
      Map<String, dynamic>? docData,
      String? warning,
    })
  >
  loadResolved() async {
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
    items = await _refreshPublishedItems(items);
    if (items.isNotEmpty) {
      return (items: items, docData: docData, warning: null);
    }

    final legacy = await loadFromStorageLegacy();
    if (legacy.isNotEmpty) {
      return (items: legacy, docData: docData, warning: null);
    }

    return (
      items: <Map<String, dynamic>>[],
      docData: docData,
      warning:
          'Nenhuma igreja em destaque. Cadastre em Divulgação → Clientes ou envie capas para '
          '${MarketingStorageLayout.clientesRootPrefix}/[id]/capa.jpg no Storage.',
    );
  }
}
