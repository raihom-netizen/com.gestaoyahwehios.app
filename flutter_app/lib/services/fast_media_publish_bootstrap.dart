import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Pré-aquecimento paralelo — evita fila de `await` antes de cada upload (Controle Total).
abstract final class FastMediaPublishBootstrap {
  FastMediaPublishBootstrap._();

  static Future<void>? _sessionWarm;
  static Future<void>? _chatWarm;

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
        .timeout(const Duration(seconds: 8));
    await FeedPostMediaUpload.warmAuthToken()
        .timeout(const Duration(seconds: 5));
  }

  static void resetSessionWarm() {
    _sessionWarm = null;
  }

  /// Chat: só núcleo Firebase + token (~segundos), sem health check de 60s.
  static Future<void> warmForChatSend() async {
    if (FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      try {
        await firebaseDefaultAuth.currentUser
            ?.getIdToken(false)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
      return;
    }
    if (_chatWarm != null) {
      await _chatWarm;
      return;
    }
    _chatWarm = _runChatWarm();
    try {
      await _chatWarm;
    } catch (_) {
      _chatWarm = null;
    }
  }

  static Future<void> _runChatWarm() async {
    await ensureFirebaseCore(requireAuth: true);
    await FeedPostMediaUpload.warmAuthToken()
        .timeout(const Duration(seconds: 5));
    await FirebaseBootstrapService.ensureReadyForStorageUpload(
      requireAuth: true,
    );
  }

  static Future<void> warmForPatrimonioSave() => warmForFeedPublish();
}
