import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Extrai um JPEG do primeiro frame (web) para miniatura no mural — mesmo fluxo do app móvel.
Future<Uint8List?> captureVideoFirstFrameJpeg(
  Uint8List videoBytes, {
  String mimeType = 'video/mp4',
}) async {
  if (videoBytes.isEmpty) return null;
  final blob = html.Blob([videoBytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final video = html.VideoElement()
    ..src = url
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..setAttribute('crossorigin', 'anonymous');
  video.style
    ..position = 'fixed'
    ..left = '-9999px'
    ..top = '0'
    ..width = '2px'
    ..height = '2px'
    ..opacity = '0.01';
  html.document.body?.append(video);

  try {
    try {
      await video.onLoadedData.first.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return null;
    }
    if (video.videoWidth < 2 || video.videoHeight < 2) {
      try {
        await video.onLoadedMetadata.first.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        return null;
      }
    }
    if (video.videoWidth < 2 || video.videoHeight < 2) return null;

    video.currentTime = 0.05;
    try {
      await video.onSeeked.first.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    }

    var w = video.videoWidth;
    var h = video.videoHeight;
    const maxW = 720;
    if (w > maxW) {
      h = (h * maxW / w).round();
      w = maxW;
    }

    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    ctx.drawImageScaled(video, 0, 0, w, h);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.82);
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || comma >= dataUrl.length - 1) return null;
    return Uint8List.fromList(base64Decode(dataUrl.substring(comma + 1)));
  } catch (_) {
    return null;
  } finally {
    video.remove();
    html.Url.revokeObjectUrl(url);
  }
}
