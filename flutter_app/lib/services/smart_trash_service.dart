import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_write_operations.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';

/// Lixeira inteligente — 30 dias antes de exclusão definitiva.
abstract final class SmartTrashService {
  SmartTrashService._();

  static const retentionDays = 30;

  static const trashModules = TenantAuditService.auditedModules;

  static bool supportsModule(String module) => trashModules.contains(module);

  static Future<void> softDelete({
    required DocumentReference<Map<String, dynamic>> ref,
    required String tenantId,
    required String module,
  }) async {
    if (!supportsModule(module)) {
      await TenantOfflineWrite.deleteDocument(
        ref: ref,
        module: module,
        tenantId: tenantId,
      );
      return;
    }

    if (TenantOfflineWrite.shouldQueueForHive) {
      await _enqueueTrash(ref: ref, tenantId: tenantId, module: module);
      try {
        await ref.delete();
      } catch (_) {}
      return;
    }

    await _moveToTrashOnline(ref: ref, tenantId: tenantId, module: module);
  }

  /// Chamado pelo executor remoto quando a fila Hive processa `trash`.
  static Future<void> moveQueuedTrashOnline({
    required DocumentReference<Map<String, dynamic>> ref,
    required String tenantId,
    required String module,
  }) =>
      _moveToTrashOnline(ref: ref, tenantId: tenantId, module: module);

  static Future<void> _moveToTrashOnline({
    required DocumentReference<Map<String, dynamic>> ref,
    required String tenantId,
    required String module,
  }) async {
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.data() ?? {});
    final expires = DateTime.now().add(const Duration(days: retentionDays));
    final u = firebaseDefaultAuth.currentUser;

    await firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId)
        .collection('lixeira')
        .doc(snap.id)
        .set({
      'originalPath': ref.path,
      'modulo': module,
      'data': data,
      'deletedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'deletedByUid': u?.uid,
      'deletedByEmail': u?.email,
      'dispositivo': TenantAuditService.deviceLabel(),
    });

    await ref.delete();

    await TenantAuditService.logDelete(
      tenantId: tenantId,
      module: module,
      docPath: ref.path,
      before: data,
    );
  }

  static Future<void> _enqueueTrash({
    required DocumentReference<Map<String, dynamic>> ref,
    required String tenantId,
    required String module,
  }) async {
    await SyncEngine.enqueue(
      SyncTask(
        id: 'trash_${ref.path.hashCode}_${DateTime.now().microsecondsSinceEpoch}',
        module: module,
        tenantId: tenantId,
        operation: OfflineWriteOperations.trash,
        payload: {
          'path': ref.path,
          'module': module,
          'tenantId': tenantId,
        },
      ),
    );
  }

  /// Restaura documento da lixeira para o path original.
  static Future<void> restore({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> trashRef,
  }) async {
    final snap = await trashRef.get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    final originalPath = (data['originalPath'] ?? '').toString();
    final docData = data['data'];
    if (originalPath.isEmpty || docData is! Map) return;

    final original = firebaseDefaultFirestore.doc(originalPath);
    await original.set(Map<String, dynamic>.from(docData));
    await trashRef.delete();
  }

  /// Purga entradas expiradas (cliente admin; CF pode fazer em batch).
  static Future<int> purgeExpired(String tenantId) async {
    final now = Timestamp.now();
    final q = await firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId)
        .collection('lixeira')
        .where('expiresAt', isLessThan: now)
        .limit(40)
        .get();
    var n = 0;
    for (final d in q.docs) {
      await d.reference.delete();
      n++;
    }
    return n;
  }
}
