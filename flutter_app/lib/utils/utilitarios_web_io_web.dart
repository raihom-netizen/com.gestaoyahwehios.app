// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Abre o share sheet nativo (WhatsApp, e-mail…) com o **arquivo**.
/// Nunca dispara download — nem em PowerPoint/Excel.
Future<bool> utilitariosWebShareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  // 1) Bridge JS nativa (index.html → window.ctShareFile).
  final viaBridge = await _shareViaJsBridge(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
  if (viaBridge) return true;

  // 2) Fallback Dart — share direto, sem canShare rígido.
  return _shareViaDart(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}

Future<bool> _shareViaJsBridge({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final fn = (html.window as dynamic).ctShareFile;
    if (fn == null) return false;
    // List<int> + await thenable (Promise JS do index.html).
    final dynamic raw = fn(bytes.toList(), fileName, mimeType);
    final dynamic resolved = await raw;
    return resolved == true;
  } catch (_) {
    return false;
  }
}

Future<bool> _shareViaDart({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final attempts = <String>[
    mimeType,
    if (mimeType != 'application/octet-stream') 'application/octet-stream',
  ];
  for (final mime in attempts) {
    try {
      final nav = html.window.navigator as dynamic;
      if (nav.share == null) return false;
      final blob = html.Blob([bytes], mime);
      final file = html.File([blob], fileName, {'type': mime});
      // Sem canShare — no Chrome, PPTX/XLSX falham no canShare mas o share abre.
      await nav.share(<String, dynamic>{
        'files': [file],
        'title': fileName,
      });
      return true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('aborterror') || msg.contains('abort')) return true;
    }
  }
  return false;
}

/// Download local (somente botão "Baixar local").
void utilitariosWebDownloadFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
}
