import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';

/// Logs detalhados de gravação (Firestore + Storage) — identificar falhas no fluxo.
abstract final class ChurchTenantWriteLog {
  ChurchTenantWriteLog._();

  static void firestoreSetStart(String path, {String? module}) {
    logFirebasePublishPhase(
      'FIRESTORE_SET_START',
      '${module ?? 'tenant'}|$path',
    );
  }

  static void firestoreSetOk(String path, {String? module}) {
    logFirebasePublishPhase(
      'FIRESTORE_SET_OK',
      '${module ?? 'tenant'}|$path',
    );
  }

  static void firestoreSetFail(
    String path,
    Object error, {
    StackTrace? stack,
    String? module,
  }) {
    logFirebasePublishPhase(
      'FIRESTORE_SET_FAIL',
      '${module ?? 'tenant'}|$path',
      error: error,
      stack: stack,
    );
  }

  static void firestoreUpdateStart(String path, {String? module}) {
    logFirebasePublishPhase(
      'FIRESTORE_UPDATE_START',
      '${module ?? 'tenant'}|$path',
    );
  }

  static void firestoreUpdateOk(String path, {String? module}) {
    logFirebasePublishPhase(
      'FIRESTORE_UPDATE_OK',
      '${module ?? 'tenant'}|$path',
    );
  }

  static void firestoreUpdateFail(
    String path,
    Object error, {
    StackTrace? stack,
    String? module,
  }) {
    logFirebasePublishPhase(
      'FIRESTORE_UPDATE_FAIL',
      '${module ?? 'tenant'}|$path',
      error: error,
      stack: stack,
    );
  }

  static void storageUploadStart(String storagePath, {String? module}) {
    logFirebasePublishPhase(
      'STORAGE_UPLOAD_START',
      '${module ?? 'storage'}|$storagePath',
    );
  }

  static void storageUploadOk(String storagePath, {String? module}) {
    logFirebasePublishPhase(
      'STORAGE_UPLOAD_OK',
      '${module ?? 'storage'}|$storagePath',
    );
  }

  static void storageUploadFail(
    String storagePath,
    Object error, {
    StackTrace? stack,
    String? module,
  }) {
    logFirebasePublishPhase(
      'STORAGE_UPLOAD_FAIL',
      '${module ?? 'storage'}|$storagePath',
      error: error,
      stack: stack,
    );
  }

  /// Fase alto nível: doc gravado, UI pode fechar; upload segue em background.
  static void publishStubCommitted(String firestorePath, {String? module}) {
    logFirebasePublishPhase(
      'PUBLISH_STUB_OK',
      '${module ?? 'publish'}|$firestorePath',
    );
  }

  static void publishBackgroundStart(String firestorePath, {String? module}) {
    logFirebasePublishPhase(
      'PUBLISH_BG_START',
      '${module ?? 'publish'}|$firestorePath',
    );
  }

  static void publishBackgroundDone(String firestorePath, {String? module}) {
    logFirebasePublishPhase(
      'PUBLISH_BG_DONE',
      '${module ?? 'publish'}|$firestorePath',
    );
  }
}
