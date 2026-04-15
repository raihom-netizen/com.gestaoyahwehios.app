import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:gestao_yahweh/core/global_upload_progress.dart';

import 'app_connectivity_service.dart';
import 'upload_bytes_core.dart';

/// Erros de rede / indisponibilidade — candidatos a fila offline e retry.
bool isLikelyNetworkUploadError(Object error) {
  final msg = error.toString().toLowerCase();
  if (error is FirebaseException) {
    switch (error.code) {
      case 'network-request-failed':
      case 'unavailable':
      case 'deadline-exceeded':
        return true;
      default:
        break;
    }
  }
  if (msg.contains('network') ||
      msg.contains('connection') ||
      msg.contains('socket') ||
      msg.contains('failed host lookup') ||
      msg.contains('errno = 7') ||
      msg.contains('timed out') ||
      msg.contains('temporar')) {
    return true;
  }
  return false;
}

/// Fila em memória de uploads ao Storage quando a rede falha após as tentativas imediatas.
/// Reprocessa ao voltar online ([AppConnectivityService]) com backoff.
class StorageUploadQueueService {
  StorageUploadQueueService._();
  static final StorageUploadQueueService instance = StorageUploadQueueService._();

  final List<_QueuedPutData> _queue = [];
  StreamSubscription<bool>? _onlineSub;
  bool _draining = false;
  int _networkFailStreak = 0;

  /// Itens à espera (útil para testes / futura UI).
  int get pendingCount => _queue.length;

  void start() {
    _onlineSub?.cancel();
    _onlineSub = AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) {
        unawaited(_drain());
      }
    });
  }

  Future<void> dispose() async {
    await _onlineSub?.cancel();
    _onlineSub = null;
  }

  /// Enfileira bytes já preparados (ex. após compressão). Completa com a URL de download.
  Future<String> enqueuePutData({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    void Function(double progress)? onProgress,
  }) async {
    final c = Completer<String>();
    _queue.add(
      _QueuedPutData(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        cacheControl: cacheControl,
        onProgress: onProgress,
        completer: c,
      ),
    );
    debugPrint(
        'StorageUploadQueueService: enfileirado ${_storagePathShort(storagePath)} (fila: ${_queue.length})');
    if (AppConnectivityService.instance.isOnline) {
      unawaited(_drain());
    }
    return c.future;
  }

  String _storagePathShort(String p) =>
      p.length > 48 ? '${p.substring(0, 45)}...' : p;

  Future<void> _drain() async {
    if (_draining) return;
    if (_queue.isEmpty) return;
    if (!AppConnectivityService.instance.isOnline) return;
    _draining = true;
    var showedProgress = false;
    try {
      while (_queue.isNotEmpty) {
        if (!AppConnectivityService.instance.isOnline) break;
        final item = _queue.first;
        if (!showedProgress) {
          showedProgress = true;
          GlobalUploadProgress.instance
              .start('A enviar ficheiros em fila (${_queue.length})…');
          GlobalUploadProgress.instance.update(0);
        }
        try {
          final url = await uploadStoragePutDataWithRetry(
            storagePath: item.storagePath,
            bytes: item.bytes,
            contentType: item.contentType,
            cacheControl: item.cacheControl,
            maxAttempts: 3,
            onProgress: item.onProgress,
          );
          if (!item.completer.isCompleted) {
            item.completer.complete(url);
          }
          _queue.removeAt(0);
          _networkFailStreak = 0;
        } catch (e) {
          if (isLikelyNetworkUploadError(e)) {
            _networkFailStreak++;
            final delayMs = (2000 * (1 << _networkFailStreak.clamp(0, 4)))
                .clamp(2000, 60000);
            debugPrint(
                'StorageUploadQueueService: rede falhou, nova tentativa em ${delayMs}ms ($e)');
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            continue;
          }
          if (!item.completer.isCompleted) {
            item.completer.completeError(e);
          }
          _queue.removeAt(0);
          _networkFailStreak = 0;
        }
        debugPrint(
            'StorageUploadQueueService: restam ${_queue.length} upload(s)');
      }
    } finally {
      if (showedProgress) {
        GlobalUploadProgress.instance.end();
      }
      _draining = false;
    }
  }
}

class _QueuedPutData {
  _QueuedPutData({
    required this.storagePath,
    required this.bytes,
    required this.contentType,
    required this.cacheControl,
    this.onProgress,
    required this.completer,
  });

  final String storagePath;
  final Uint8List bytes;
  final String contentType;
  final String cacheControl;
  final void Function(double progress)? onProgress;
  final Completer<String> completer;
}
