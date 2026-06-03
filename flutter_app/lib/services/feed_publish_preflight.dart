import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';

/// Pré-publicação — só núcleo Firebase (padrão Controle Total, sem warmup/fila).
abstract final class FeedPublishPreflight {
  FeedPublishPreflight._();

  /// [inFlightCount] mantido por compatibilidade de API; ignorado (sem drain/warm).
  static Future<void> prepareForFirestoreSave({
    int Function()? inFlightCount,
  }) async {
    YahwehFlowLog.start('AVISOS_PREFLIGHT');
    try {
      await ensureFirebaseCore(requireAuth: true)
          .timeout(const Duration(seconds: 12));
      YahwehFlowLog.success('AVISOS_PREFLIGHT');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FIREBASE APPS=${Firebase.apps.length} (preflight)');
        debugPrint('ERROR=$e');
        debugPrint('$st');
      }
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
  }

  static void firestoreSaveOk({required bool isEvento}) {
    ChurchPublishFlowLog.moduleFirestoreOk(isEvento: isEvento);
  }
}
