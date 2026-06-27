import 'dart:html' as html;
import 'dart:typed_data';

/// Lê bytes de um blob URL gerado pelo [AudioRecorder] na web.
Future<Uint8List?> readRecordingBlob(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  try {
    final request = await html.HttpRequest.request(
      trimmed,
      responseType: 'arraybuffer',
    );
    final buffer = request.response;
    if (buffer is ByteBuffer && buffer.lengthInBytes > 0) {
      return Uint8List.view(buffer);
    }
  } catch (_) {}
  return null;
}
