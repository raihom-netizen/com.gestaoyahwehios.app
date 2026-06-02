import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Logs obrigatórios — publicação aviso / evento / chat (diagnóstico no console).
abstract final class ChurchPublishFlowLog {
  ChurchPublishFlowLog._();

  static void _out(String message) {
    // ignore: avoid_print
    print(message);
    if (kDebugMode) debugPrint(message);
  }

  static void logCatch(Object e, StackTrace st, {String? label}) {
    if (label != null) _out('PUBLISH_ERROR $label');
    // ignore: avoid_print
    print(e);
    // ignore: avoid_print
    print(st);
  }

  // —— Avisos ——
  static void avisoStart() => _out('AVISO START');
  static void avisoFirestoreOk() => _out('AVISO FIRESTORE OK');
  static void avisoUploadOk() => _out('AVISO UPLOAD OK');
  static void avisoFinalOk() => _out('AVISO SUCCESS');
  static void avisoError(Object e, [StackTrace? st]) {
    _out('AVISO ERROR $e');
    if (st != null) logCatch(e, st);
  }

  // —— Eventos ——
  static void eventoStart() => _out('EVENTO START');
  static void eventoFirestoreOk() => _out('EVENTO FIRESTORE OK');
  static void eventoUploadOk() => _out('EVENTO UPLOAD OK');
  static void eventoFinalOk() => _out('EVENT SUCCESS');
  static void eventoError(Object e, [StackTrace? st]) {
    _out('EVENT ERROR $e');
    if (st != null) logCatch(e, st);
  }

  // —— Chat ——
  static void chatStart() => _out('CHAT START');
  static void chatMessageCreated() => _out('CHAT MESSAGE CREATED');
  static void chatFileUploaded() => _out('CHAT FILE UPLOADED');
  static void chatMessageUpdated() => _out('CHAT MESSAGE UPDATED');
  static void chatFinalOk() => _out('CHAT SUCCESS');
  static void chatSuccess() => chatFinalOk();
  static void chatError(Object e, [StackTrace? st]) {
    _out('CHAT ERROR $e');
    if (st != null) logCatch(e, st);
  }

  // —— Foto membro ——
  static void memberPhotoStart() => _out('MEMBER PHOTO START');
  static void memberPhotoFirestoreOk() => _out('MEMBER PHOTO FIRESTORE OK');
  static void memberPhotoUploadOk() => _out('MEMBER PHOTO UPLOAD OK');
  static void memberPhotoSuccess() => _out('MEMBER PHOTO SUCCESS');
  static void memberPhotoError(Object e, [StackTrace? st]) {
    _out('MEMBER PHOTO ERROR $e');
    if (st != null) logCatch(e, st);
  }

  /// Compatibilidade com chamadas anteriores.
  static void noticeSaveStart() => avisoStart();
  static void noticeSaveOk() => avisoFirestoreOk();
  static void eventSaveStart() => eventoStart();
  static void eventSaveOk() => eventoFirestoreOk();
  static void chatSendStart() => chatStart();
  static void chatSendOk() => chatFinalOk();

  static void uploadStart([String? detail]) =>
      _out('UPLOAD START${detail != null ? ' $detail' : ''}');
  static void uploadOk([String? detail]) =>
      _out('UPLOAD SUCCESS${detail != null ? ' $detail' : ''}');

  static void uploadError(Object e, [StackTrace? st]) {
    _out('UPLOAD ERROR $e');
    if (st != null) logCatch(e, st);
  }

  static void firestoreError(Object e, [StackTrace? st]) {
    _out('FIRESTORE ERROR $e');
    if (st != null) logCatch(e, st);
  }

  static void phase(String label) => _out('PUBLISH_PHASE $label');

  static void moduleFirestoreOk({required bool isEvento}) {
    if (isEvento) {
      eventoFirestoreOk();
    } else {
      avisoFirestoreOk();
    }
  }

  static void moduleUploadOk({required bool isEvento}) {
    if (isEvento) {
      eventoUploadOk();
    } else {
      avisoUploadOk();
    }
  }

  static void moduleFinalOk({required bool isEvento}) {
    if (isEvento) {
      eventoFinalOk();
    } else {
      avisoFinalOk();
    }
  }
}
