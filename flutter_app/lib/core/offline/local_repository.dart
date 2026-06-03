import 'package:gestao_yahweh/core/offline/sync_task.dart';

/// Fonte local principal (Hive) — leitura/escrita imediata sem rede.
abstract class LocalRepository {
  Future<void> init();

  Future<void> saveTask(SyncTask task);

  Future<void> removeTask(String id);

  Future<List<SyncTask>> listTasks({String? module});

  Future<void> clearModule(String module);
}
