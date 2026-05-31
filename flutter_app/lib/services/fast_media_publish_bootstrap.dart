import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Pré-aquecimento paralelo — evita fila de `await` antes de cada upload (Controle Total).
abstract final class FastMediaPublishBootstrap {
  FastMediaPublishBootstrap._();

  static Future<void> warmForFeedPublish() async {
    await Future.wait([
      ensureFirebaseReadyForPublishUpload().catchError((_) {}),
      FeedPostMediaUpload.warmAuthToken().catchError((_) {}),
    ]);
  }

  static Future<void> warmForChatSend() async {
    await Future.wait([
      ensureFirebaseReadyForChatSend().catchError((_) {}),
      FeedPostMediaUpload.warmAuthToken().catchError((_) {}),
    ]);
  }

  static Future<void> warmForPatrimonioSave() async {
    await Future.wait([
      ensureFirebaseReadyForPublishUpload().catchError((_) {}),
      FeedPostMediaUpload.warmAuthToken().catchError((_) {}),
    ]);
  }
}
