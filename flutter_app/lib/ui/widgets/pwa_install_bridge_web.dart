import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

Future<bool> canInstallPwa() async {
  try {
    final gyh = js.context['gyhPwa'];
    if (gyh == null) return false;
    final r = (gyh as js.JsObject).callMethod('canInstall', []);
    return r == true;
  } catch (_) {
    return false;
  }
}

Future<bool> promptInstallPwa() async {
  try {
    final gyh = js.context['gyhPwa'];
    if (gyh == null) return false;
    final res = (gyh as js.JsObject).callMethod('promptInstall', []);
    if (res == null) return false;
    return await _awaitJsBool(res);
  } catch (_) {
    return false;
  }
}

Future<bool> _awaitJsBool(dynamic maybePromise) {
  if (maybePromise is bool) return Future.value(maybePromise);
  final c = Completer<bool>();
  final p = maybePromise as js.JsObject;
  p.callMethod('then', [
    js_util.allowInterop((dynamic value) {
      if (!c.isCompleted) {
        c.complete(value == true);
      }
    }),
    js_util.allowInterop((dynamic _) {
      if (!c.isCompleted) c.complete(false);
    }),
  ]);
  return c.future;
}
