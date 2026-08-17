import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/marketing_public_site_service.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Publicação controlada pelo Master na Galeria de Clientes.
abstract final class MasterChurchPublicationService {
  MasterChurchPublicationService._();

  static DocumentReference<Map<String, dynamic>> _churchRef(String id) =>
      firebaseDefaultFirestore.collection('igrejas').doc(id);

  static Future<bool> isPublished(String churchId) async {
    final id = churchId.trim();
    if (id.isEmpty) return false;
    final snap = await _churchRef(
      id,
    ).get(const GetOptions(source: Source.serverAndCache));
    final data = snap.data() ?? const <String, dynamic>{};
    final marketing = data['marketing'] is Map
        ? Map<String, dynamic>.from(data['marketing'] as Map)
        : const <String, dynamic>{};
    return marketing['publishedInClientGallery'] == true ||
        data['publicarGaleriaClientes'] == true;
  }

  static Future<void> setPublished({
    required String churchId,
    required Map<String, dynamic> churchData,
    required bool published,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) throw ArgumentError('Igreja inválida.');

    await FirestoreWebGuard.runWithWebRecovery(() async {
      final galleryRef = MarketingPublicSiteService.marketingClientesDocRef;
      final current = await galleryRef.get(
        const GetOptions(source: Source.serverAndCache),
      );
      final raw = current.data() ?? const <String, dynamic>{};
      final existing = raw['items'] is List
          ? (raw['items'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) {
                  final itemId =
                      (item['igrejaTenantId'] ??
                              item['tenantId'] ??
                              item['id'] ??
                              '')
                          .toString()
                          .trim();
                  return itemId != id;
                })
                .toList()
          : <Map<String, dynamic>>[];

      final next = <Map<String, dynamic>>[...existing];
      if (published) {
        next.add(_publicItem(id, churchData));
      }

      final batch = YahwehBatch();
      batch.set(galleryRef, <String, dynamic>{
        'items': next,
        'updatedAt': YahwehFv.serverTimestamp,
      }, merge: true);
      batch.set(_churchRef(id), <String, dynamic>{
        'publicarGaleriaClientes': published,
        'marketing': <String, dynamic>{
          'publishedInClientGallery': published,
          'publishedAt': published
              ? YahwehFv.serverTimestamp
              : YahwehFv.deleteField,
        },
        'updatedAt': YahwehFv.serverTimestamp,
      }, merge: true);
      await batch.commit();
    });
  }

  static Map<String, dynamic> _publicItem(
    String id,
    Map<String, dynamic> source,
  ) {
    String value(List<String> keys) {
      for (final key in keys) {
        final value = source[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final nome = value(['nome', 'name']);
    return <String, dynamic>{
      'id': id,
      'igrejaTenantId': id,
      'tenantId': id,
      'nomeIgreja': nome.isEmpty ? id : nome,
      'pastor': value(['pastor', 'pastorNome', 'responsavel']),
      'gestor': value(['gestorNome', 'responsavel', 'gestor']),
      'whatsapp': value(['whatsapp', 'telefone', 'phone']),
      'site': value(['sitePublico', 'siteUrl', 'website']),
      'localizacao': value([
        'localizacao',
        'enderecoCompleto',
        'endereco',
        'cidade',
      ]),
      'logoUrl': value(['logoUrl', 'urlLogo', 'logo']),
      'logoPath': value(['logoPath', 'storageLogoPath']),
      'published': true,
      'ativo': true,
    };
  }
}
