import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Pré-aquecimento paralelo — evita fila de `await` antes de cada upload (Controle Total).
abstract final class FastMediaPublishBootstrap {
  FastMediaPublishBootstrap._();

  static Future<void>? _sessionWarm;

  /// Uma vez por sessão — evita N× warm antes de cada upload (chat/mural/património).
  static Future<void> warmForFeedPublish() async {
    if (FirebaseBootstrapService.isStorageUploadBootstrapFresh) return;
    if (_sessionWarm != null) {
      await _sessionWarm;
      return;
    }
    _sessionWarm = _runWarm();
    try {
      await _sessionWarm;
    } catch (_) {
      _sessionWarm = null;
      rethrow;
    }
  }

  static Future<void> _runWarm() async {
    await FirebaseBootstrapService.ensureReadyForStorageUpload(requireAuth: true)
        .timeout(const Duration(seconds: 60));
    await FeedPostMediaUpload.warmAuthToken()
        .timeout(const Duration(seconds: 30));
  }

  static void resetSessionWarm() {
    _sessionWarm = null;
  }

  static Future<void> warmForChatSend() => warmForFeedPublish();

  static Future<void> warmForPatrimonioSave() => warmForFeedPublish();
}
