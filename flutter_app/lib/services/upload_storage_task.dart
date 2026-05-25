import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';

/// Mensagem amigável para SnackBar / «Tentar de novo» (evita «Bad state: …» cru).
String formatUploadErrorForUser(Object error) {
  if (error is TimeoutException) {
    final m = error.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return 'Tempo esgotado no envio. Use Wi‑Fi ou tente de novo.';
  }
  if (error is FirebaseException) {
    final m = error.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return 'Falha no envio (${error.code}). Tente de novo.';
  }
  final raw = '$error';
  if (raw.contains('Tempo esgotado')) {
    return 'Tempo esgotado no envio. Reduza o tamanho da foto ou use Wi‑Fi.';
  }
  if (raw.contains('network') || raw.contains('Network')) {
    return 'Sem conexão estável. Verifique a internet e tente de novo.';
  }
  if (raw.length > 160) {
    return 'Não foi possível enviar o ficheiro. Tente de novo.';
  }
  return raw.replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
}

Duration uploadMaxDurationForPayloadBytes(int bytes) {
  final mb = bytes <= 0 ? 1 : (bytes / (1024 * 1024)).ceil();
  final minutes = (5 + mb * 2).clamp(5, 20);
  return Duration(minutes: minutes);
}

/// Aguarda [UploadTask] com progresso, timeout por tamanho e deteção de paragem (rede lenta).
Future<TaskSnapshot> awaitStorageUploadTask(
  UploadTask task, {
  required int payloadBytes,
  void Function(double progress)? onProgress,
  Duration stallAfter = const Duration(seconds: 90),
}) async {
  final maxDuration = uploadMaxDurationForPayloadBytes(payloadBytes);
  final completer = Completer<TaskSnapshot>();
  StreamSubscription<TaskSnapshot>? sub;
  Timer? stallTimer;
  var lastTransferred = -1;

  void armStallWatchdog() {
    stallTimer?.cancel();
    stallTimer = Timer(stallAfter, () {
      if (completer.isCompleted) return;
      unawaited(task.cancel());
      completer.completeError(
        TimeoutException(
          'Conexão lenta: o envio parou. Verifique a rede e toque em «Tentar de novo».',
        ),
      );
    });
  }

  sub = task.snapshotEvents.listen(
    (snap) {
      final transferred = snap.bytesTransferred;
      if (transferred > lastTransferred) {
        lastTransferred = transferred;
        armStallWatchdog();
      }
      final total = snap.totalBytes;
      if (onProgress != null && total > 0) {
        onProgress((transferred / total).clamp(0.0, 1.0));
      }
      switch (snap.state) {
        case TaskState.success:
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete(snap);
        case TaskState.error:
          stallTimer?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              FirebaseException(
                plugin: 'firebase_storage',
                code: 'upload-error',
                message: 'Falha ao enviar ficheiro.',
              ),
            );
          }
        case TaskState.canceled:
          stallTimer?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Envio cancelado. Tente de novo.'),
            );
          }
        case TaskState.running:
        case TaskState.paused:
          break;
      }
    },
    onError: (Object e, StackTrace _) {
      stallTimer?.cancel();
      if (!completer.isCompleted) completer.completeError(e);
    },
  );

  armStallWatchdog();
  try {
    return await completer.future.timeout(
      maxDuration,
      onTimeout: () {
        unawaited(task.cancel());
        throw TimeoutException(
          'Tempo esgotado (${maxDuration.inMinutes} min). '
          'Use Wi‑Fi ou envie um ficheiro menor.',
        );
      },
    );
  } finally {
    await sub.cancel();
    stallTimer?.cancel();
  }
}

Future<String> storageDownloadUrlWithRetry(Reference ref) async {
  Object? last;
  for (var i = 0; i < 3; i++) {
    try {
      return await ref.getDownloadURL().timeout(const Duration(seconds: 60));
    } catch (e) {
      last = e;
      if (i < 2) {
        await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
    }
  }
  throw last ?? StateError('URL do ficheiro indisponível.');
}
