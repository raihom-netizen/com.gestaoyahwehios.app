import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

/// Garante **1 listener por chave** — criar em initState, cancelar em dispose.
abstract final class StreamListenerRegistry {
  StreamListenerRegistry._();

  static final Map<String, StreamSubscription<dynamic>> _active = {};

  static bool register({
    required String key,
    required StreamSubscription<dynamic> subscription,
    bool replaceExisting = true,
  }) {
    final k = key.trim();
    if (k.isEmpty) return false;
    final existing = _active[k];
    if (existing != null) {
      if (!replaceExisting) {
        debugPrint('STREAM_GUARD: listener duplicado bloqueado — $k');
        subscription.cancel();
        return false;
      }
      unawaited(existing.cancel());
    }
    _active[k] = subscription;
    return true;
  }

  static Future<void> cancel(String key) async {
    final sub = _active.remove(key.trim());
    await sub?.cancel();
  }

  static Future<void> cancelAll() async {
    final subs = _active.values.toList();
    _active.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  static int get activeCount => _active.length;

  static List<String> activeKeys() => _active.keys.toList(growable: false);
}
