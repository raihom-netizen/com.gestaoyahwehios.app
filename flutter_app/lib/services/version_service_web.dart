// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void reloadWeb() {
  // Recarga simples não fura service worker/CacheStorage antigos — usar hard.
  hardReloadWeb();
}

/// Recarga garantida do bundle novo: remove service workers, limpa o
/// CacheStorage e navega com query de cache-bust (`gyhUpd`).
Future<void> hardReloadWeb() async {
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try {
          await r.unregister();
        } catch (_) {}
      }
    }
  } catch (_) {}
  try {
    final caches = html.window.caches;
    if (caches != null) {
      final keys = await caches.keys();
      if (keys is List) {
        for (final k in keys) {
          try {
            await caches.delete('$k');
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
  final loc = html.window.location;
  final uri = Uri.parse(loc.href);
  final qp = Map<String, String>.from(uri.queryParameters);
  qp['gyhUpd'] = DateTime.now().millisecondsSinceEpoch.toString();
  loc.replace(uri.replace(queryParameters: qp).toString());
}

/// Build publicado no Hosting (`version.json`) — 0 se indisponível.
Future<int> fetchServerBuildNumber() async {
  try {
    final res = await html.HttpRequest.request(
      'version.json?t=${DateTime.now().millisecondsSinceEpoch}',
      method: 'GET',
    );
    final txt = res.responseText ?? '';
    final m = RegExp(r'"build_number"\s*:\s*"?(\d+)"?').firstMatch(txt);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  } catch (_) {
    return 0;
  }
}

String readLocalFlag(String key) {
  try {
    return html.window.localStorage[key] ?? '';
  } catch (_) {
    return '';
  }
}

void writeLocalFlag(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}
