/// Operações remotas registadas em [FirebaseRemoteRepository].
abstract final class OfflineWriteOperations {
  OfflineWriteOperations._();

  static const set = 'set';
  static const update = 'update';
  static const delete = 'delete';
  static const batchWrite = 'batch_write';
  static const trash = 'trash';
}
