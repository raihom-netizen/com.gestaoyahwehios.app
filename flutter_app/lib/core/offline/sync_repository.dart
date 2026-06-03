import 'package:gestao_yahweh/core/offline/local_repository.dart';
import 'package:gestao_yahweh/core/offline/remote_repository.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';

/// Orquestra gravação local → UI → rede (padrão Controle Total).
class SyncRepository {
  SyncRepository({
    required LocalRepository local,
    required RemoteRepository remote,
  })  : _local = local,
        _remote = remote;

  final LocalRepository _local;
  final RemoteRepository _remote;

  /// Grava na fila local e tenta enviar se online (falha mantém tarefa — Nunca Perder Dados).
  Future<void> enqueueAndTrySync(SyncTask task) async {
    YahwehFlowLog.start(task.module);
    await _local.saveTask(task);
    if (!AppConnectivityService.instance.isOnline) {
      YahwehFlowLog.offline(task.module);
      return;
    }
    try {
      await _remote.push(task);
      await _local.removeTask(task.id);
      YahwehFlowLog.success(task.module);
    } catch (e, st) {
      YahwehFlowLog.error(task.module, e, st);
    }
  }

  Future<void> flushModule(String module) async {
    final pending = await _local.listTasks(module: module);
    for (final task in pending) {
      try {
        await _remote.push(task);
        await _local.removeTask(task.id);
        YahwehFlowLog.success(module);
      } catch (e, st) {
        YahwehFlowLog.error(module, e, st);
      }
    }
  }
}
