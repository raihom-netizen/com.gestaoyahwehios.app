import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/firebase_remote_repository.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/offline/local_repository.dart';
import 'package:gestao_yahweh/core/offline/sync_repository.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/core/offline/sync_priority.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';

/// Fila local + retry + flush ao voltar online.
abstract final class SyncEngine {
  SyncEngine._();

  static final LocalRepository _local = HiveLocalStore.instance;
  static final FirebaseRemoteRepository _remote =
      FirebaseRemoteRepository.instance;
  static late final SyncRepository _syncRepo = SyncRepository(
    local: _local,
    remote: _remote,
  );

  static final Map<String, Future<void> Function()> _moduleFlushers = {};
  static bool _flushBusy = false;
  static const int _maxRetries = 8;

  static SyncRepository get repository => _syncRepo;

  static void registerModuleFlusher(String module, Future<void> Function() fn) {
    _moduleFlushers[module] = fn;
  }

  static Future<void> enqueue(SyncTask task) async {
    await _syncRepo.enqueueAndTrySync(task);
  }

  /// Processa fila Hive + flushers legados (chat, mural, storage…).
  static Future<void> flushAll({String? reason}) async {
    if (_flushBusy) return;
    if (!AppConnectivityService.instance.isOnline) {
      YahwehFlowLog.offline('SYNC');
      return;
    }
    _flushBusy = true;
    YahwehFlowLog.sync('SYNC', reason ?? 'flush');
    try {
      await ensureFirebaseCore(requireAuth: false);
      await _flushHiveQueue();
      final flushers = _moduleFlushers.entries.toList()
        ..sort(
          (a, b) => SyncPriority.flusherIndex(a.key)
              .compareTo(SyncPriority.flusherIndex(b.key)),
        );
      for (final entry in flushers) {
        try {
          YahwehFlowLog.start(entry.key);
          await entry.value();
          YahwehFlowLog.success(entry.key);
        } catch (e, st) {
          YahwehFlowLog.error(entry.key, e, st);
          if (kDebugMode) debugPrint('SyncEngine.${entry.key}: $e\n$st');
        }
      }
      YahwehFlowLog.success('SYNC');
    } catch (e, st) {
      YahwehFlowLog.error('SYNC', e, st);
      if (kDebugMode) debugPrint('SyncEngine.flushAll: $e\n$st');
    } finally {
      _flushBusy = false;
    }
  }

  static Future<void> _flushHiveQueue() async {
    final pending = await _local.listTasks();
    for (final task in pending) {
      if (task.retryCount >= _maxRetries) {
        YahwehFlowLog.error(
          task.module,
          StateError('max retries: ${task.lastError}'),
          StackTrace.current,
        );
        continue;
      }
      try {
        await _remote.push(task);
        await _local.removeTask(task.id);
        YahwehFlowLog.success(task.module);
      } catch (e, st) {
        YahwehFlowLog.retry(task.module, task.retryCount + 1);
        final next = task.copyWith(
          retryCount: task.retryCount + 1,
          lastError: e.toString(),
        );
        await _local.saveTask(next);
        YahwehFlowLog.error(task.module, e, st);
      }
    }
  }
}
