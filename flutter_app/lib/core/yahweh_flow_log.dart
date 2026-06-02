import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/yahweh_catch_log.dart';
import 'package:gestao_yahweh/services/yahweh_observability.dart';

/// Logs globais START / SUCCESS / ERROR por módulo (produção premium).
abstract final class YahwehFlowLog {
  YahwehFlowLog._();

  static void _out(String message) {
    // ignore: avoid_print
    print(message);
    if (kDebugMode) debugPrint(message);
  }

  static void _module(String module, String phase) => _out('$module $phase');

  static void start(String module) => _module(module, 'START');

  static void success(String module) => _module(module, 'SUCCESS');

  static void error(String module, Object e, StackTrace s) {
    _module(module, 'ERROR');
    YahwehCatchLog.log(e, s, tag: module);
  }

  // —— Módulos nomeados ——
  static void dashboardStart() => start('DASHBOARD');
  static void dashboardSuccess() => success('DASHBOARD');

  static void membrosStart() => start('MEMBROS');
  static void membrosSuccess() => success('MEMBROS');

  static void eventoStart() => start('EVENTOS');
  static void eventoFirestoreOk() => _out('EVENTOS FIRESTORE OK');
  static void eventoUploadOk() => _out('EVENTOS UPLOAD OK');
  static void eventoSuccess() => _out('EVENTOS FINAL OK');

  static void avisoStart() => start('AVISOS');
  static void avisoFirestoreOk() => _out('AVISOS FIRESTORE OK');
  static void avisoUploadOk() => _out('AVISOS UPLOAD OK');
  static void avisoSuccess() => _out('AVISOS FINAL OK');

  static void chatStart() => start('CHAT');
  static void chatMessageCreated() => _out('CHAT MESSAGE CREATED');
  static void chatFileUploaded() => _out('CHAT FILE UPLOADED');
  static void chatMessageUpdated() => _out('CHAT MESSAGE UPDATED');
  static void chatSuccess() => _out('CHAT FINAL OK');
  static void chatAutoRecover(int count) => _out('CHAT AUTO RECOVER $count');

  static void patrimonioStart() => start('PATRIMONIO');
  static void patrimonioFirestoreOk() => _out('PATRIMONIO FIRESTORE OK');
  static void patrimonioUploadOk() => _out('PATRIMONIO UPLOAD OK');
  static void patrimonioSuccess() => success('PATRIMONIO');

  static void memberPhotoStart() => _out('MEMBER PHOTO START');
  static void memberPhotoFirestoreOk() => _out('MEMBER PHOTO FIRESTORE OK');
  static void memberPhotoUploadOk() => _out('MEMBER PHOTO UPLOAD OK');
  static void memberPhotoSuccess() => _out('MEMBER PHOTO SUCCESS');
  static void memberPhotoError(Object e, StackTrace s) => error('MEMBER PHOTO', e, s);

  static void uploadStart([String? detail]) =>
      _out('UPLOAD START${detail != null ? ' $detail' : ''}');
  static void uploadSuccess([String? detail]) =>
      _out('UPLOAD SUCCESS${detail != null ? ' $detail' : ''}');
  static void uploadError(Object e, StackTrace s) => error('UPLOAD', e, s);

  static void cartaoStart() => start('CARTAO');
  static void cartaoSuccess() => success('CARTAO');

  static void cartaStart() => start('CARTA');
  static void cartaSuccess() => success('CARTA');

  static void relatorioStart() => start('RELATORIO');
  static void relatorioSuccess() => success('RELATORIO');

  /// Trace Firebase Performance + Analytics (não bloqueia).
  static Future<T> trace<T>(
    String module,
    Future<T> Function() fn,
  ) async {
    start(module);
    try {
      final r = await YahwehObservability.traceAsync(
        'flow_$module',
        fn,
      );
      success(module);
      return r;
    } catch (e, s) {
      error(module, e, s);
      rethrow;
    }
  }
}
