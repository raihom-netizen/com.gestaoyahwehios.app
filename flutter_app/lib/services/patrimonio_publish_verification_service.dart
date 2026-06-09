import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Verificação obrigatória pós-gravação de patrimônio — evita falso sucesso.
abstract final class PatrimonioPublishVerificationService {
  PatrimonioPublishVerificationService._();

  static const String kPublishVerifyFailedMessage =
      'Falha ao salvar patrimônio.\nDocumento não localizado no Firestore.';

  static const String kStorageVerifyFailedMessage =
      'Falha ao salvar patrimônio.\nFoto não confirmada no Storage.';

  static String? _lastError;

  static String? get lastError => _lastError;

  static void rememberLastError(Object error) {
    _lastError = error.toString();
  }

  static void clearLastError() => _lastError = null;

  static Future<String> resolveTenantForPublish({
    required String seedTenantId,
    String? userUid,
  }) async {
    final resolved = ChurchPublishContext.churchIdForPublish(seedTenantId);
    debugPrint('CHURCH_ID (patrimônio): $resolved');
    return resolved;
  }

  static void assertPatrimonioDocPath(
    DocumentReference<Map<String, dynamic>> ref,
  ) {
    final parts = ref.path.split('/');
    if (parts.length < 4 ||
        parts[0] != 'igrejas' ||
        parts[2] != 'patrimonio') {
      throw StateError(
        'Coleção incorreta: ${ref.path}. '
        'Esperado: igrejas/{igrejaId}/patrimonio/{id}',
      );
    }
    if (parts[1].trim().isEmpty) {
      throw StateError('churchId inválido: ${ref.path}');
    }
  }

  static DocumentReference<Map<String, dynamic>> patrimonioDocRef({
    required String igrejaId,
    required String itemId,
  }) {
    final ref = ChurchOperationalPaths.churchDoc(igrejaId.trim())
        .collection('patrimonio')
        .doc(itemId.trim());
    assertPatrimonioDocPath(ref);
    return ref;
  }

  static String collectionPathFor(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/patrimonio';

  static String photoStoragePath({
    required String igrejaId,
    required String itemId,
    required int slot,
  }) =>
      ChurchStorageLayout.patrimonioPhotoPath(igrejaId, itemId, slot);

  static Future<void> verifyStorageMetadata({
    Iterable<String> photoPaths = const [],
    Iterable<String> thumbPaths = const [],
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertAllExist(photoPaths);
      await ChurchStorageMetadataVerify.assertAllExist(thumbPaths);
    } catch (e) {
      rememberLastError(kStorageVerifyFailedMessage);
      rethrow;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
  }) async {
    assertPatrimonioDocPath(docRef);
    final check = await docRef.get(
      GetOptions(
        source: preferServer ? Source.server : Source.serverAndCache,
      ),
    );
    if (!check.exists) {
      rememberLastError(kPublishVerifyFailedMessage);
      throw StateError(kPublishVerifyFailedMessage);
    }
    return check;
  }

  static Future<void> logPublishPhase({
    required String phase,
    required String igrejaId,
    required String itemId,
    String? nome,
    Iterable<String>? storagePaths,
  }) async {
    await SystemLogService.record(
      module: 'patrimonio',
      message: 'publish_$phase',
      tenantId: igrejaId,
      canonicalId: igrejaId,
      severity: phase == 'after' ? 'info' : 'debug',
      extra: <String, dynamic>{
        'igrejaId': igrejaId,
        'itemId': itemId,
        if (nome != null && nome.isNotEmpty) 'nome': nome,
        if (storagePaths != null) 'storagePaths': storagePaths.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
