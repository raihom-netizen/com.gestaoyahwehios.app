import 'dart:async';
import 'dart:html' as html;

/// PWA / Chrome: ao voltar de outro app, o canvas WebGL (CanvasKit) pode ficar preto até um novo frame.
Timer? _debounce;
final List<void Function()> _callbacks = [];
final List<StreamSubscription<dynamic>> _subs = [];

void _scheduleFire() {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 100), () {
    for (final cb in List<void Function()>.from(_callbacks)) {
      cb();
    }
  });
}

void _ensureHooks() {
  if (_subs.isNotEmpty) return;
  _subs.add(html.window.onFocus.listen((_) => _scheduleFire()));
  _subs.add(html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      _scheduleFire();
    }
  }));
  _subs.add(html.window.onPageShow.listen((_) => _scheduleFire()));
}

void _teardownHooks() {
  _debounce?.cancel();
  _debounce = null;
  for (final s in _subs) {
    s.cancel();
  }
  _subs.clear();
}

void registerWebResumeRepaint(void Function() onResume) {
  if (!_callbacks.contains(onResume)) {
    _callbacks.add(onResume);
  }
  _ensureHooks();
}

void unregisterWebResumeRepaint([void Function()? onResume]) {
  if (onResume != null) {
    _callbacks.remove(onResume);
  } else {
    _callbacks.clear();
  }
  if (_callbacks.isEmpty) {
    _teardownHooks();
  }
}
