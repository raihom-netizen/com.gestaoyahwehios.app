import 'dart:async';

/// Fila global para vários uploads de mídia — evita 5 compressões/upload em paralelo no UI thread.
///
/// Usa no máximo [maxConcurrent] uploads simultâneos; o resto espera na fila.
abstract final class MediaBatchUploadQueue {
  MediaBatchUploadQueue._();

  static const int maxConcurrent = 2;
  static int _active = 0;
  static final List<_Job> _pending = [];

  static Future<T> enqueue<T>(Future<T> Function() task) {
    final c = Completer<T>();
    _pending.add(_Job(() async {
      try {
        final r = await task();
        c.complete(r);
      } catch (e, st) {
        c.completeError(e, st);
      }
    }));
    unawaited(_pump());
    return c.future;
  }

  static Future<void> _pump() async {
    while (_active < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      _active++;
      unawaited(() async {
        try {
          await job.run();
        } finally {
          _active--;
          await _pump();
        }
      }());
    }
  }
}

class _Job {
  _Job(this.run);
  final Future<void> Function() run;
}

/// Helper para N fotos do mural/chat.
Future<List<T>> uploadAllSequentiallyLimited<T>({
  required List<Future<T> Function()> tasks,
}) async {
  final out = <T>[];
  for (final t in tasks) {
    out.add(await MediaBatchUploadQueue.enqueue(t));
  }
  return out;
}
