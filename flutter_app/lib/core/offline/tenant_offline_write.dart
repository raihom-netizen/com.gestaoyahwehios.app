import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/offline/never_lose_data_policy.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/offline_payload_codec.dart';
import 'package:gestao_yahweh/core/offline/offline_write_operations.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/smart_trash_service.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Gravação tenant com fila Hive explícita quando `!isOnline` (Fase 2 — todos os módulos).
abstract final class TenantOfflineWrite {
  TenantOfflineWrite._();

  static bool get shouldQueueForHive =>
      !AppConnectivityService.instance.isOnline;

  /// Write-ahead local (Nunca Perder Dados) — sempre fila Hive antes do Firebase.
  static bool _persistBeforeRemote(String module) =>
      NeverLoseDataPolicy.appliesTo(module) || shouldQueueForHive;

  static String _taskId(String module, String path, String op) =>
      '${module}_${op}_${path.hashCode}_${DateTime.now().microsecondsSinceEpoch}';

  static Future<void> _enqueue({
    required String module,
    required String tenantId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    await SyncEngine.enqueue(
      SyncTask(
        id: _taskId(module, (payload['path'] ?? tenantId).toString(), operation),
        module: module,
        tenantId: tenantId,
        operation: operation,
        payload: payload,
      ),
    );
  }

  /// Escrita local imediata no Firestore (mobile persistence) — UI atualiza offline.
  static Future<void> _mirrorToFirestoreCache({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    bool merge = false,
    bool isUpdate = false,
    bool isDelete = false,
  }) async {
    if (kIsWeb) return;
    try {
      if (isDelete) {
        await ref.delete();
        return;
      }
      if (isUpdate) {
        await ref.update(data);
        return;
      }
      if (merge) {
        await ref.set(data, SetOptions(merge: true));
      } else {
        await ref.set(data);
      }
    } catch (_) {}
  }

  static Future<void> setDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    bool merge = false,
    String? module,
    String? tenantId,
  }) async {
    final payload = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(data),
    );
    final path = ref.path;
    final tid = tenantId?.trim().isNotEmpty == true
        ? tenantId!.trim()
        : OfflineModules.tenantIdFromPath(path);
    final mod = module ?? OfflineModules.tenant;

    if (_persistBeforeRemote(mod)) {
      await _enqueue(
        module: mod,
        tenantId: tid,
        operation: OfflineWriteOperations.set,
        payload: {
          'path': path,
          'data': OfflinePayloadCodec.encodeMap(payload),
          'merge': merge,
        },
      );
      await _mirrorToFirestoreCache(ref: ref, data: payload, merge: merge);
      unawaited(
        TenantAuditService.logCreate(
          tenantId: tid,
          module: mod,
          docPath: path,
          data: payload,
        ),
      );
      return;
    }

    await runFirestorePublishWithRecovery<void>(() async {
      if (merge) {
        await ref.set(payload, SetOptions(merge: true));
      } else {
        await ref.set(payload);
      }
    });
    unawaited(
      TenantAuditService.logCreate(
        tenantId: tid,
        module: mod,
        docPath: path,
        data: payload,
      ),
    );
  }

  static Future<void> updateDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    String? module,
    String? tenantId,
  }) async {
    final payload = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(data),
    );
    final path = ref.path;
    final tid = tenantId?.trim().isNotEmpty == true
        ? tenantId!.trim()
        : OfflineModules.tenantIdFromPath(path);
    final mod = module ?? OfflineModules.tenant;

    if (_persistBeforeRemote(mod)) {
      await _enqueue(
        module: mod,
        tenantId: tid,
        operation: OfflineWriteOperations.update,
        payload: {
          'path': path,
          'data': OfflinePayloadCodec.encodeMap(payload),
        },
      );
      await _mirrorToFirestoreCache(
        ref: ref,
        data: payload,
        isUpdate: true,
      );
      unawaited(
        TenantAuditService.logUpdate(
          tenantId: tid,
          module: mod,
          docPath: path,
          after: payload,
        ),
      );
      return;
    }

    await runFirestorePublishWithRecovery<void>(() => ref.update(payload));
    unawaited(
      TenantAuditService.logUpdate(
        tenantId: tid,
        module: mod,
        docPath: path,
        after: payload,
      ),
    );
  }

  static Future<void> deleteDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    String? module,
    String? tenantId,
  }) async {
    final path = ref.path;
    final tid = tenantId?.trim().isNotEmpty == true
        ? tenantId!.trim()
        : OfflineModules.tenantIdFromPath(path);
    final mod = module ?? OfflineModules.tenant;

    if (SmartTrashService.supportsModule(mod)) {
      await SmartTrashService.softDelete(
        ref: ref,
        tenantId: tid,
        module: mod,
      );
      return;
    }

    if (_persistBeforeRemote(mod)) {
      await _enqueue(
        module: mod,
        tenantId: tid,
        operation: OfflineWriteOperations.delete,
        payload: {'path': path},
      );
      await _mirrorToFirestoreCache(ref: ref, data: {}, isDelete: true);
      unawaited(
        TenantAuditService.logDelete(
          tenantId: tid,
          module: mod,
          docPath: path,
        ),
      );
      return;
    }

    await runFirestorePublishWithRecovery<void>(() => ref.delete());
    unawaited(
      TenantAuditService.logDelete(
        tenantId: tid,
        module: mod,
        docPath: path,
      ),
    );
  }

  /// Vários `set` num único commit (ex.: financeiro em lote).
  static Future<void> batchSet({
    required String tenantId,
    required String module,
    required List<({
      String path,
      Map<String, dynamic> data,
      bool merge,
    })> writes,
  }) async {
    if (writes.isEmpty) return;
    final encoded = writes
        .map(
          (w) => <String, dynamic>{
            'path': w.path,
            'data': OfflinePayloadCodec.encodeMap(
              FirestoreWriteGuard.stripHeavyFields(w.data),
            ),
            'merge': w.merge,
          },
        )
        .toList();

    if (_persistBeforeRemote(module)) {
      await _enqueue(
        module: module,
        tenantId: tenantId,
        operation: OfflineWriteOperations.batchWrite,
        payload: {'writes': encoded},
      );
      if (!kIsWeb) {
        final batch = FirebaseFirestore.instance.batch();
        for (final w in writes) {
          final ref = FirebaseFirestore.instance.doc(w.path);
          final data = FirestoreWriteGuard.stripHeavyFields(w.data);
          if (w.merge) {
            batch.set(ref, data, SetOptions(merge: true));
          } else {
            batch.set(ref, data);
          }
        }
        try {
          await batch.commit();
        } catch (_) {}
      }
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final w in writes) {
      final ref = FirebaseFirestore.instance.doc(w.path);
      final data = FirestoreWriteGuard.stripHeavyFields(w.data);
      if (w.merge) {
        batch.set(ref, data, SetOptions(merge: true));
      } else {
        batch.set(ref, data);
      }
    }
    await runFirestorePublishWithRecovery<void>(() => batch.commit());
  }
}
