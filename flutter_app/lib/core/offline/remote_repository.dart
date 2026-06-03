import 'package:gestao_yahweh/core/offline/sync_task.dart';

/// Firestore / Storage — só após sucesso local.
typedef RemoteSyncHandler = Future<void> Function(SyncTask task);

/// Registo de operações remotas por módulo.
abstract class RemoteRepository {
  void registerHandler(String module, String operation, RemoteSyncHandler fn);

  Future<void> push(SyncTask task);
}
