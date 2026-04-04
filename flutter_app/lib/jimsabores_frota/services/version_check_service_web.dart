import 'dart:html' as html;

Future<void> reloadWithCacheBust(String serverVersion) async {
  final uri = html.window.location;
  final base = '${uri.origin}${uri.pathname}';
  final separator = base.contains('?') ? '&' : '?';
  html.window.location.href = '$base${separator}v=$serverVersion&_=${DateTime.now().millisecondsSinceEpoch}';
}
