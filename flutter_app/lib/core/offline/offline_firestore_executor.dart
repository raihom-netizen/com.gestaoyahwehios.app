import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/smart_trash_service.dart';
import 'package:gestao_yahweh/core/offline/firebase_remote_repository.dart';
import 'package:gestao_yahweh/core/offline/offline_firestore_path.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/offline_payload_codec.dart';
import 'package:gestao_yahweh/core/offline/offline_write_operations.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Handlers remotos genéricos por módulo (membros, eventos, avisos, …).
abstract final class OfflineFirestoreExecutor {
  OfflineFirestoreExecutor._();

  static void registerAll(FirebaseRemoteRepository remote) {
    for (final module in _allModules) {
      remote.registerHandler(
        module,
        OfflineWriteOperations.set,
        _handleSet,
      );
      remote.registerHandler(
        module,
        OfflineWriteOperations.update,
        _handleUpdate,
      );
      remote.registerHandler(
        module,
        OfflineWriteOperations.delete,
        _handleDelete,
      );
      remote.registerHandler(
        module,
        OfflineWriteOperations.batchWrite,
        _handleBatchWrite,
      );
      remote.registerHandler(
        module,
        OfflineWriteOperations.trash,
        _handleTrash,
      );
    }
  }

  static const _allModules = [
    OfflineModules.membros,
    OfflineModules.eventos,
    OfflineModules.avisos,
    OfflineModules.patrimonio,
    OfflineModules.financeiro,
    OfflineModules.escalas,
    OfflineModules.visitantes,
    OfflineModules.pedidosOracao,
    OfflineModules.departamentos,
    OfflineModules.chat,
    OfflineModules.mural,
    OfflineModules.tenant,
  ];

  static Future<void> _handleSet(SyncTask task) async {
    final path = (task.payload['path'] ?? '').toString();
    final merge = task.payload['merge'] == true;
    final data = OfflinePayloadCodec.decodeMap(
      Map<String, dynamic>.from(
        task.payload['data'] is Map
            ? task.payload['data'] as Map
            : const <String, dynamic>{},
      ),
    );
    final ref = OfflineFirestorePath.document(path);
    await runFirestorePublishWithRecovery<void>(() async {
      if (merge) {
        await ref.set(data, SetOptions(merge: true));
      } else {
        await ref.set(data);
      }
    });
  }

  static Future<void> _handleUpdate(SyncTask task) async {
    final path = (task.payload['path'] ?? '').toString();
    final data = OfflinePayloadCodec.decodeMap(
      Map<String, dynamic>.from(
        task.payload['data'] is Map
            ? task.payload['data'] as Map
            : const <String, dynamic>{},
      ),
    );
    final ref = OfflineFirestorePath.document(path);
    await runFirestorePublishWithRecovery<void>(() => ref.update(data));
  }

  static Future<void> _handleDelete(SyncTask task) async {
    final path = (task.payload['path'] ?? '').toString();
    final ref = OfflineFirestorePath.document(path);
    await runFirestorePublishWithRecovery<void>(() => ref.delete());
  }

  static Future<void> _handleBatchWrite(SyncTask task) async {
    final raw = task.payload['writes'];
    if (raw is! List || raw.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final item in raw) {
      if (item is! Map) continue;
      final path = (item['path'] ?? '').toString();
      if (path.isEmpty) continue;
      final ref = OfflineFirestorePath.document(path);
      final data = OfflinePayloadCodec.decodeMap(
        Map<String, dynamic>.from(
          item['data'] is Map ? item['data'] as Map : const <String, dynamic>{},
        ),
      );
      final merge = item['merge'] == true;
      if (merge) {
        batch.set(ref, data, SetOptions(merge: true));
      } else {
        batch.set(ref, data);
      }
    }
    await runFirestorePublishWithRecovery<void>(() => batch.commit());
  }

  static Future<void> _handleTrash(SyncTask task) async {
    final path = (task.payload['path'] ?? '').toString();
    final tenantId = (task.payload['tenantId'] ?? task.tenantId).toString();
    final module = (task.payload['module'] ?? task.module).toString();
    if (path.isEmpty || tenantId.isEmpty) return;
    final ref = OfflineFirestorePath.document(path);
    await SmartTrashService.moveQueuedTrashOnline(
      ref: ref,
      tenantId: tenantId,
      module: module,
    );
  }
}
