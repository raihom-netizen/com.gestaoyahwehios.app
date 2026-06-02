import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';

/// Pré-publicação mural: **não** bloquear minutos em uploads paralelos.
abstract final class FeedPublishPreflight {
  FeedPublishPreflight._();

  /// Máx. 2s à espera de fotos já a subir; depois Firestore (não bloquear ~40s).
  static Future<void> prepareForFirestoreSave({
    required int Function() inFlightCount,
  }) async {
    await ImmediateMediaWarm.drainInFlight(
      inFlightCount,
      maxWait: const Duration(seconds: 2),
    );
    unawaited(ImmediateMediaWarm.warmFeed());
    try {
      await ensureFirebaseReadyForPublishUpload()
          .timeout(const Duration(seconds: 12));
    } catch (e, st) {
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
  }

  static void firestoreSaveOk({required bool isEvento}) {
    ChurchPublishFlowLog.moduleFirestoreOk(isEvento: isEvento);
  }
}
