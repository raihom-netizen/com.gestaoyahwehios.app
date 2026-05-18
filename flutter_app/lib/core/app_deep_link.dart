import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Deep link inicial (Android App Links / iOS URL ao abrir o app).
abstract final class AppDeepLink {
  AppDeepLink._();

  static const MethodChannel _channel =
      MethodChannel('com.gestaoyahweh.app/deep_link');

  static final StreamController<String> _warmLinks =
      StreamController<String>.broadcast();

  static Stream<String> get warmLinks => _warmLinks.stream;

  static bool _handlerReady = false;

  static void registerWarmLinkHandler() {
    if (_handlerReady || kIsWeb) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final path = call.arguments?.toString();
        if (path != null && path.isNotEmpty) {
          _warmLinks.add(path);
        }
      }
    });
  }

  /// Path + query (ex. `/igreja/foo/cadastro-membro`) ou null.
  static Future<String?> initialPath() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialPath');
    } catch (_) {
      return null;
    }
  }
}
