import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:video_player/video_player.dart';

/// Cabeçalhos que melhoram compatibilidade do ExoPlayer (Android) / AVPlayer (iOS)
/// com URLs longas e tokenizadas do Firebase Storage (comportamento próximo ao player HTML).
const Map<String, String> kFirebaseStorageVideoHttpHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
  'Accept':
      'application/vnd.apple.mpegurl,application/x-mpegURL,video/mp4,video/webm,video/quicktime,video/*;q=0.9,*/*;q=0.8',
};

/// Renova a URL de download (token) — **web e mobile** (padrão EcoFire: sempre URL fresca do SDK).
Future<String> resolveFirebaseStorageVideoPlayUrl(String rawUrl) =>
    StorageMediaService.freshPlayableMediaUrl(rawUrl);

/// Controller de rede com headers adequados para Storage (mobile).
VideoPlayerController networkVideoControllerForUrl(String url) {
  final t = url.trim();
  final uri = Uri.tryParse(t) ?? Uri.parse(t);
  final Map<String, String> headers = StorageMediaService.isFirebaseStorageMediaUrl(t)
      ? kFirebaseStorageVideoHttpHeaders
      : const <String, String>{};
  return VideoPlayerController.networkUrl(uri, httpHeaders: headers);
}
