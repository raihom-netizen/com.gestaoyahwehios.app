import 'dart:async';

/// Limita uploads de mídia do chat em paralelo (evita saturar rede — estilo WhatsApp estável).
abstract final class ChurchChatMediaUploadCoordinator {
  ChurchChatMediaUploadCoordinator._();

  static const int maxConcurrent = 3;

  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  static Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
    _active++;
  }

  static void _release() {
    _active = (_active - 1).clamp(0, maxConcurrent);
    if (_waiters.isEmpty) return;
    _waiters.removeAt(0).complete();
  }
}
