import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gestao_yahweh/core/offline/local_repository.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/core/offline/sync_priority.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';

/// Hive como store da fila offline (mobile/desktop; web usa memória + Firestore cache).
class HiveLocalStore implements LocalRepository {
  HiveLocalStore._();
  static final HiveLocalStore instance = HiveLocalStore._();

  static const String _boxName = 'yahweh_sync_queue_v1';
  Box<String>? _box;
  final List<SyncTask> _webMemory = [];

  bool get isReady => _box != null || kIsWeb;

  @override
  Future<void> init() async {
    if (kIsWeb) {
      YahwehFlowLog.sync('OFFLINE', 'hive_skipped_web');
      return;
    }
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.initFlutter();
      _box = await Hive.openBox<String>(_boxName);
    }
    YahwehFlowLog.success('OFFLINE');
  }

  @override
  Future<void> saveTask(SyncTask task) async {
    if (kIsWeb) {
      _webMemory.removeWhere((t) => t.id == task.id);
      _webMemory.add(task);
      return;
    }
    final box = _box;
    if (box == null) return;
    await box.put(task.id, jsonEncode(task.toJson()));
  }

  @override
  Future<void> removeTask(String id) async {
    if (kIsWeb) {
      _webMemory.removeWhere((t) => t.id == id);
      return;
    }
    await _box?.delete(id);
  }

  @override
  Future<List<SyncTask>> listTasks({String? module}) async {
    if (kIsWeb) {
      final m = module?.trim();
      if (m == null || m.isEmpty) return List<SyncTask>.from(_webMemory);
      return _webMemory.where((t) => t.module == m).toList();
    }
    final box = _box;
    if (box == null) return const [];
    final out = <SyncTask>[];
    for (final raw in box.values) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final task = SyncTask.fromJson(map);
        if (module == null ||
            module.isEmpty ||
            task.module == module) {
          out.add(task);
        }
      } catch (_) {}
    }
    out.sort(SyncPriority.compareTasks);
    return out;
  }

  @override
  Future<void> clearModule(String module) async {
    final tasks = await listTasks(module: module);
    for (final t in tasks) {
      await removeTask(t.id);
    }
  }
}
