import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Estados da fila de upload — visíveis para UI/diagnóstico.
enum UploadQueueState {
  queued,
  uploading,
  processing,
  completed,
  failed,
}

/// Item rastreado na fila unificada (Storage → URL; Firestore no caller strict).
class UploadQueueJob {
  UploadQueueJob({
    required this.id,
    required this.storagePath,
    required this.module,
    this.tenantId,
    this.state = UploadQueueState.queued,
    this.progress = 0,
    this.error,
    this.downloadUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String storagePath;
  final YahwehUploadModule module;
  final String? tenantId;
  UploadQueueState state;
  double progress;
  String? error;
  String? downloadUrl;
  final DateTime createdAt;

  bool get isTerminal =>
      state == UploadQueueState.completed || state == UploadQueueState.failed;
}

/// Fachada obrigatória: selecionar mídia → fila → upload em background → URL.
///
/// O Firestore strict (storagePath) continua no caller após [enqueueBytes] completar.
class UploadQueueService {
  UploadQueueService._();
  static final UploadQueueService instance = UploadQueueService._();

  final _jobs = <String, UploadQueueJob>{};
  final _controller = StreamController<List<UploadQueueJob>>.broadcast();
  var _seq = 0;

  Stream<List<UploadQueueJob>> get jobsStream => _controller.stream;

  int get pendingCount =>
      _jobs.values.where((j) => !j.isTerminal).length +
      StorageUploadQueueService.instance.pendingCount;

  List<UploadQueueJob> get activeJobs => _jobs.values
      .where((j) => !j.isTerminal)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void _emit() {
    if (_controller.isClosed) return;
    final list = _jobs.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _controller.add(List<UploadQueueJob>.unmodifiable(list));
  }

  void _setState(UploadQueueJob job, UploadQueueState state, {String? error}) {
    job.state = state;
    if (error != null) job.error = error;
    _emit();
  }

  void start() {
    StorageUploadQueueService.instance.start();
  }

  Future<void> dispose() async {
    await _controller.close();
    await StorageUploadQueueService.instance.dispose();
  }

  void clearFailed() {
    _jobs.removeWhere((_, j) => j.state == UploadQueueState.failed);
    _emit();
  }

  void clearPending() {
    _jobs.removeWhere((_, j) => !j.isTerminal);
    StorageUploadQueueService.instance.clearPending();
    _emit();
  }

  Future<String> enqueueBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    YahwehUploadModule? module,
    String? tenantId,
    String? localFilePathForRetry,
    bool useOfflineQueue = true,
    void Function(double progress)? onProgress,
  }) async {
    final id = 'uq_${++_seq}_${DateTime.now().millisecondsSinceEpoch}';
    final mod =
        module ?? YahwehMediaUploadPipeline.moduleFromStoragePath(storagePath);
    final job = UploadQueueJob(
      id: id,
      storagePath: storagePath,
      module: mod,
      tenantId: tenantId,
    );
    _jobs[id] = job;
    _emit();

    try {
      _setState(job, UploadQueueState.processing);
      _setState(job, UploadQueueState.uploading);
      final url = await YahwehMediaUploadPipeline.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        module: mod,
        tenantId: tenantId,
        localFilePathForRetry: localFilePathForRetry,
        useOfflineQueue: useOfflineQueue,
        onProgress: (p) {
          job.progress = p;
          _emit();
          onProgress?.call(p);
        },
      );
      job.downloadUrl = url;
      job.progress = 1;
      _setState(job, UploadQueueState.completed);
      debugPrint('UploadQueueService: concluído $storagePath');
      return url;
    } catch (e, st) {
      _setState(job, UploadQueueState.failed, error: e.toString());
      debugPrint('UploadQueueService: falhou $storagePath — $e\n$st');
      rethrow;
    }
  }
}
