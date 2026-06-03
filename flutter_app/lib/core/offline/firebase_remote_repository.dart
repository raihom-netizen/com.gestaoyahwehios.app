import 'package:gestao_yahweh/core/offline/remote_repository.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';

/// Implementação remota — handlers registados por módulo.
class FirebaseRemoteRepository implements RemoteRepository {
  FirebaseRemoteRepository._();
  static final FirebaseRemoteRepository instance =
      FirebaseRemoteRepository._();

  final Map<String, Map<String, RemoteSyncHandler>> _handlers = {};

  @override
  void registerHandler(String module, String operation, RemoteSyncHandler fn) {
    _handlers.putIfAbsent(module, () => {})[operation] = fn;
  }

  @override
  Future<void> push(SyncTask task) async {
    final mod = _handlers[task.module];
    if (mod == null) {
      throw StateError('RemoteRepository: módulo ${task.module} sem handler');
    }
    final fn = mod[task.operation];
    if (fn == null) {
      throw StateError(
        'RemoteRepository: ${task.module}/${task.operation} sem handler',
      );
    }
    await fn(task);
  }
}
