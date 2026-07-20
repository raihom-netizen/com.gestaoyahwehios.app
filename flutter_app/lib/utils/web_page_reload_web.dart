import 'dart:html' as html;

/// Recarrega a aba (única forma segura de recuperar Firestore JS após assert/terminated).
void reloadWebPageHard() {
  try {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = html.window.location.origin;
    final path = html.window.location.pathname ?? '/';
    final pathNorm = path.endsWith('/') ? path : '$path/';
    html.window.location.href = '$base$pathNorm?_r=$ts';
  } catch (_) {
    html.window.location.reload();
  }
}
