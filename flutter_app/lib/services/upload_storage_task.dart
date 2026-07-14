import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatFirebaseErrorForUser;
import 'package:gestao_yahweh/core/media_upload_limits.dart';

/// Mensagem amigável para SnackBar / «Tentar de novo» — mostra erro real.
String formatUploadErrorForUser(Object error) =>
    formatFirebaseErrorForUser(error);

/// Erros de rede/timeout — manter stub Firestore e reenviar depois.
bool isRetryableUploadError(Object error) {
  if (error is StateError) {
    final m = error.message.toLowerCase();
    if (m.contains('sem dados para enviar')) {
      return false;
    }
    if (m.contains('sessão expirada') ||
        m.contains('firebase não') ||
        m.contains('indispon')) {
      return true;
    }
  }
  final rawBootstrap = error.toString().toLowerCase();
  if (rawBootstrap.contains('no firebase app') ||
      rawBootstrap.contains('core/no-app') ||
      rawBootstrap.contains('não inicializou')) {
    return true;
  }
  if (error is TimeoutException) return true;
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unavailable':
      case 'network-request-failed':
      case 'retry-limit-exceeded':
      case 'deadline-exceeded':
      case 'cancelled':
        return true;
    }
  }
  final raw = error.toString().toLowerCase();
  return raw.contains('network') ||
      raw.contains('timeout') ||
      raw.contains('tempo esgotado') ||
      raw.contains('connection') ||
      raw.contains('offline') ||
      raw.contains('sem conexão');
}

Duration uploadMaxDurationForPayloadBytes(int bytes) {
  if (bytes <= kStorageUploadCompressedImageMaxBytes) {
    return Duration(seconds: kStorageUploadCompressedImageMaxSeconds);
  }
  if (bytes <= 3 * 1024 * 1024) {
    return Duration(seconds: kStorageUploadImageMaxSeconds);
  }
  final mb = bytes <= 0 ? 1 : (bytes / (1024 * 1024)).ceil();
  final minutes = (5 + mb * 2).clamp(5, 20);
  return Duration(minutes: minutes);
}

/// Aguarda [UploadTask] com progresso, timeout por tamanho e deteção de paragem (rede lenta).
Future<TaskSnapshot> awaitStorageUploadTask(
  UploadTask task, {
  required int payloadBytes,
  void Function(double progress)? onProgress,
  Duration stallAfter = const Duration(seconds: 120),
}) async {
  final maxDuration = uploadMaxDurationForPayloadBytes(payloadBytes);
  final effectiveStall = payloadBytes <= kStorageUploadCompressedImageMaxBytes
      ? Duration(seconds: kStorageUploadCompressedImageStallSeconds)
      : payloadBytes <= 3 * 1024 * 1024
          ? Duration(seconds: kStorageUploadImageStallSeconds)
          : stallAfter;
  final completer = Completer<TaskSnapshot>();
  StreamSubscription<TaskSnapshot>? sub;
  Timer? stallTimer;
  var lastTransferred = -1;

  void armStallWatchdog() {
    stallTimer?.cancel();
    stallTimer = Timer(effectiveStall, () {
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
        await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
      }
    }
  }
  throw last ?? StateError('URL do ficheiro indisponível.');
}
