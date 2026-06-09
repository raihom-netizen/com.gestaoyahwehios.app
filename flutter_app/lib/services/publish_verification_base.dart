import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/core/church_publish_state.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Base compartilhada por todos os `*PublishVerificationService`.
abstract class PublishVerificationBase {
  const PublishVerificationBase();

  String get moduleName;

  String get publishVerifyFailedMessage;

  String get storageVerifyFailedMessage;

  String? get lastError;

  void rememberLastError(Object error);

  void clearLastError();

  /// Resolve tenant operacional — ponto único de entrada.
  Future<String> resolveTenantForPublish({
    required String seedTenantId,
    String? userUid,
  }) async {
    final resolved = ChurchPublishContext.churchIdForPublish(seedTenantId);
    debugPrint('CHURCH_ID ($moduleName): $resolved');
    return resolved;
  }

  void assertOperationalWriteTenant(String igrejaId) {
    final t = igrejaId.trim();
    if (!t.startsWith('igreja_') && t.length < 4) {
      throw StateError('churchId inválido para gravação: $t');
    }
  }

  /// Rascunho → upload → verificação → sucesso (falha mantém rascunho).
  Future<void> runPublishPipeline({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Future<void> Function() uploadStep,
    required Future<void> Function() verifyStep,
    Future<void> Function(Object error)? onFailure,
  }) async {
    await docRef.set(ChurchPublishState.draftPatch(), SetOptions(merge: true));
    try {
      await docRef.set(
        ChurchPublishState.uploadingPatch(),
        SetOptions(merge: true),
      );
      await uploadStep();
      await docRef.set(
        ChurchPublishState.verifyingPatch(),
        SetOptions(merge: true),
      );
      await verifyStep();
      await docRef.set(
        ChurchPublishState.successPatch(),
        SetOptions(merge: true),
      );
    } catch (e) {
      await docRef.set(
        ChurchPublishState.failedPatch(reason: e.toString()),
        SetOptions(merge: true),
      );
      await onFailure?.call(e);
      rethrow;
    }
  }

  Future<void> verifyStoragePaths({
    Iterable<String> paths = const [],
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertAllExist(paths);
    } catch (e) {
      rememberLastError(storageVerifyFailedMessage);
      rethrow;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
    void Function(DocumentReference<Map<String, dynamic>> ref)? assertPath,
  }) async {
    assertPath?.call(docRef);
    final check = await docRef.get(
      GetOptions(
        source: preferServer ? Source.server : Source.serverAndCache,
      ),
    );
    if (!check.exists) {
      rememberLastError(publishVerifyFailedMessage);
      throw StateError(publishVerifyFailedMessage);
    }
    return check;
  }
}
