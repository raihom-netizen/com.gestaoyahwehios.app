import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Verificação obrigatória pós-gravação de foto de perfil — evita falso sucesso.
abstract final class MembroPublishVerificationService {
  MembroPublishVerificationService._();

  static const String kPublishVerifyFailedMessage =
      'Falha ao salvar foto do membro.\nDocumento não localizado no Firestore.';

  static const String kStorageVerifyFailedMessage =
      'Falha ao salvar foto.\nArquivo não confirmado no Storage.';

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
    debugPrint('CHURCH_ID (membro): $resolved');
    return resolved;
  }

  static void assertMembroDocPath(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length < 4 ||
        parts[0] != 'igrejas' ||
        parts[2] != 'membros') {
      throw StateError(
        'Coleção incorreta: ${ref.path}. '
        'Esperado: igrejas/{igrejaId}/membros/{id}',
      );
    }
    if (parts[1].trim().isEmpty) {
      throw StateError('churchId inválido: ${ref.path}');
    }
  }

  static DocumentReference<Map<String, dynamic>> membroDocRef({
    required String igrejaId,
    required String memberDocId,
  }) {
    final ref = ChurchOperationalPaths.churchDoc(igrejaId.trim())
        .collection('membros')
        .doc(memberDocId.trim());
    assertMembroDocPath(ref);
    return ref;
  }

  static String collectionPathFor(String igrejaId) =>
      FirebasePaths.membros(igrejaId);

  static String profilePhotoPath({
    required String igrejaId,
    required String memberDocId,
  }) =>
      ChurchStorageLayout.memberProfilePhotoPath(igrejaId, memberDocId);

  static String profileThumbPath({
    required String igrejaId,
    required String memberDocId,
  }) =>
      ChurchStorageLayout.memberProfileThumbPath(igrejaId, memberDocId);

  static Future<void> verifyStorageMetadata({
    required String fullStoragePath,
    String? thumbStoragePath,
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertExists(fullStoragePath);
      final thumb = thumbStoragePath?.trim() ?? '';
      if (thumb.isNotEmpty && thumb != fullStoragePath.trim()) {
        await ChurchStorageMetadataVerify.assertExists(thumb);
      }
    } catch (e) {
      rememberLastError(kStorageVerifyFailedMessage);
      rethrow;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
    String? expectedStoragePath,
  }) async {
    assertMembroDocPath(docRef);
    final check = await docRef.get(
      GetOptions(
        source: preferServer ? Source.server : Source.serverAndCache,
      ),
    );
    if (!check.exists) {
      rememberLastError(kPublishVerifyFailedMessage);
      throw StateError(kPublishVerifyFailedMessage);
    }
    if (expectedStoragePath != null && expectedStoragePath.trim().isNotEmpty) {
      final data = check.data() ?? {};
      final sp = (data['photoStoragePath'] ?? data['fotoPath'] ?? '')
          .toString()
          .trim();
      if (sp.isEmpty) {
        rememberLastError('Membro sem fotoPath após upload.');
        throw StateError(kPublishVerifyFailedMessage);
      }
    }
    return check;
  }

  static Future<void> logPublishPhase({
    required String phase,
    required String igrejaId,
    required String memberDocId,
    String? storagePath,
  }) async {
    await SystemLogService.record(
      module: 'membros',
      message: 'publish_$phase',
      tenantId: igrejaId,
      canonicalId: igrejaId,
      severity: phase == 'after' ? 'info' : 'debug',
      extra: <String, dynamic>{
        'igrejaId': igrejaId,
        'memberDocId': memberDocId,
        if (storagePath != null && storagePath.isNotEmpty)
          'storagePath': storagePath,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
