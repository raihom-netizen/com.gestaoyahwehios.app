import 'dart:async';
import 'dart:html' as html;

/// PWA / Chrome: ao voltar de outro app, o canvas WebGL (CanvasKit) pode ficar preto até um novo frame.
Timer? _debounce;
void Function()? _callback;
final List<StreamSubscription<dynamic>> _subs = [];

void registerWebResumeRepaint(void Function() onResume) {
  unregisterWebResumeRepaint();
  _callback = onResume;
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      _callback?.call();
    });
  }

  _subs.add(html.window.onFocus.listen((_) => schedule()));
  _subs.add(html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      schedule();
    }
  }));
  _subs.add(html.window.onPageShow.listen((_) => schedule()));
}

void unregisterWebResumeRepaint() {
  _debounce?.cancel();
  _debounce = null;
  for (final s in _subs) {
    s.cancel();
  }
  _subs.clear();
  _callback = null;
}
