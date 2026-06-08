import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

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
    final igrejaId = await TenantResolverService.resolveOperationalChurchDocId(
      seedTenantId.trim(),
      userUid: userUid,
    );
    final resolved = igrejaId.trim();
    if (resolved.isEmpty) {
      throw StateError('Tenant não resolvido ($moduleName).');
    }
    assertOperationalWriteTenant(resolved);
    debugPrint('TENANT RESOLVIDO ($moduleName):');
    debugPrint(resolved);
    return resolved;
  }

  void assertOperationalWriteTenant(String igrejaId) {
    final t = igrejaId.trim();
    if (TenantResolverService.kBpcLegacyTenantIds.contains(t)) {
      throw StateError(
        'Tenant legado proibido para gravação: $t. '
        'Use ${TenantResolverService.kBpcCanonicalIgrejaDocId}.',
      );
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
