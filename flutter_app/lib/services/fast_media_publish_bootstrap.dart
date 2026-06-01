import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Pré-aquecimento paralelo — evita fila de `await` antes de cada upload (Controle Total).
abstract final class FastMediaPublishBootstrap {
  FastMediaPublishBootstrap._();

  static Future<void> warmForFeedPublish() async {
    await Future.wait([
      FirebaseBootstrapService.ensureReadyForStorageUpload(requireAuth: true)
          .catchError((_) {}),
      FeedPostMediaUpload.warmAuthToken().catchError((_) {}),
    ]);
  }

  static Future<void> warmForChatSend() async {
    await warmForFeedPublish();
  }

  static Future<void> warmForPatrimonioSave() async {
    await warmForFeedPublish();
  }
}
