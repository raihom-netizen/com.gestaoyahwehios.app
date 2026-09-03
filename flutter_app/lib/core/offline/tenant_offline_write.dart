import 'dart:async' show TimeoutException, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/offline/firestore_last_write_wins.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/offline_payload_codec.dart';
import 'package:gestao_yahweh/core/offline/offline_write_operations.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/sync_service.dart';
import 'package:gestao_yahweh/services/smart_trash_service.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Gravação tenant com fila Hive explícita quando `!isOnline` (Fase 2 — todos os módulos).
abstract final class TenantOfflineWrite {
  TenantOfflineWrite._();

  static bool get shouldQueueForHive =>
      !AppConnectivityService.instance.isOnline;

  /// Write-ahead Hive quando offline (mobile + web memória) — sync silenciosa ao voltar online.
  static bool _persistBeforeRemote(String module) => shouldQueueForHive;

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
      final effectiveMerge = FirestoreWriteGuard.effectiveSetMerge(
        merge: merge,
        data: data,
      );
      if (effectiveMerge) {
        await ref.set(data, SetOptions(merge: true));
      } else {
        await ref.set(data);
      }
    } catch (_) {}
  }

  /// Publicação (aviso/evento): a gravação **tem de ser confirmada**.
  ///
  /// O caminho normal é optimista — 2,2 s de espera e o resto em background,
  /// engolindo o erro. Isso é certo para texto de formulário, e errado para
  /// uma publicação: a UI dizia «Aviso publicado com sucesso» e o documento
  /// nunca chegava ao servidor (mídia no Storage, `avisos` vazia). Com
  /// [strict] a falha chega ao chamador, que já sabe distinguir «sem rede →
  /// fica em fila» de erro real.
  static const Duration kStrictWriteTimeout = Duration(seconds: 30);

  static Future<void> setDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    bool merge = false,
    String? module,
    String? tenantId,
    bool strict = false,
  }) async {
    final path = ref.path;
    final tid = tenantId?.trim().isNotEmpty == true
        ? tenantId!.trim()
        : OfflineModules.tenantIdFromPath(path);
    final stripped = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(data),
    );
    final effectiveMerge = FirestoreWriteGuard.effectiveSetMerge(
      merge: merge,
      data: stripped,
    );
    final payload = FirestoreLastWriteWins.stamp(
      ChurchTenantFields.stamp(
        tid,
        stripped,
      ),
      includeCreatedAt: !merge,
    );
    final mod = module ?? OfflineModules.tenant;

    // `strict` (publicação) nunca desvia para a fila sem tentar a rede: o
    // «offline» aqui é o palpite do `connectivity_plus`, que num 5G instável
    // dá `none` por momentos. Bastava esse palpite para o aviso ir só para a
    // fila Hive — que só é drenada na transição offline→online — enquanto a
    // mídia subia ao Storage e o mirror legado gravava no servidor pelo
    // caminho directo. Se a rede estiver mesmo em baixo, o erro sobe e quem
    // publica é que decide enfileirar (e diz isso ao utilizador).
    if (!strict && _persistBeforeRemote(mod)) {
      await _enqueue(
        module: mod,
        tenantId: tid,
        operation: OfflineWriteOperations.set,
        payload: {
          'path': path,
          'data': OfflinePayloadCodec.encodeMap(payload),
          'merge': effectiveMerge,
        },
      );
      await _mirrorToFirestoreCache(
        ref: ref,
        data: payload,
        merge: effectiveMerge,
      );
      SyncService.notifyUserActionSaved();
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
      if (strict) {
        await _setStrict(ref, payload, merge: effectiveMerge);
        return;
      }
      await _setWithLocalTimeout(
        ref,
        payload,
        merge: effectiveMerge,
        module: mod,
        tenantId: tid,
      );
    });
    SyncService.notifyUserActionSaved();
    unawaited(
      TenantAuditService.logCreate(
        tenantId: tid,
        module: mod,
        docPath: path,
        data: payload,
      ),
    );
  }

  /// Padrão CT: timeout curto → fila local do Firestore (UI não espera rede).
  static const Duration _kLocalWait = Duration(milliseconds: 2200);

  /// Se a tentativa em background também falhar, enfileira no Hive (mesma fila do modo
  /// offline) em vez de descartar o dado — sem isso, uma falha depois do timeout de
  /// [_kLocalWait] (rede instável, sessão web) era invisível: a UI já tinha dado como
  /// salvo e o documento nunca chegava ao Firestore (ex.: visitante "sumindo" após reload).
  static Future<void> _queueAfterBackgroundFailure({
    required String module,
    required String tenantId,
    required String path,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _enqueue(
        module: module,
        tenantId: tenantId,
        operation: operation,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Grava e **espera a confirmação do servidor** — erro sobe ao chamador.
  static Future<void> _setStrict(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    required bool merge,
  }) async {
    final write = merge
        ? ref.set(data, SetOptions(merge: true))
        : ref.set(data);
    await write.timeout(
      kStrictWriteTimeout,
      onTimeout: () => throw TimeoutException(
        'A gravação não foi confirmada pelo servidor. '
        'Verifique a rede e toque em «Tentar novamente».',
        kStrictWriteTimeout,
      ),
    );
  }

  static Future<void> _setWithLocalTimeout(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    required bool merge,
    required String module,
    required String tenantId,
  }) async {
    Future<void> write() async {
      if (merge) {
        await ref.set(data, SetOptions(merge: true));
      } else {
        await ref.set(data);
      }
    }

    Future<void> retryThenQueue() async {
      try {
        await write();
      } catch (_) {
        await _queueAfterBackgroundFailure(
          module: module,
          tenantId: tenantId,
          path: ref.path,
          operation: OfflineWriteOperations.set,
          payload: {
            'path': ref.path,
            'data': OfflinePayloadCodec.encodeMap(data),
            'merge': merge,
          },
        );
      }
    }

    try {
      await write().timeout(_kLocalWait);
    } on TimeoutException {
      unawaited(retryThenQueue());
    } catch (_) {
      unawaited(retryThenQueue());
    }
  }

  static Future<void> _updateWithLocalTimeout(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    required String module,
    required String tenantId,
  }) async {
    Future<void> retryThenQueue() async {
      try {
        await ref.update(data);
      } catch (_) {
        await _queueAfterBackgroundFailure(
          module: module,
          tenantId: tenantId,
          path: ref.path,
          operation: OfflineWriteOperations.update,
          payload: {
            'path': ref.path,
            'data': OfflinePayloadCodec.encodeMap(data),
          },
        );
      }
    }

    try {
      await ref.update(data).timeout(_kLocalWait);
    } on TimeoutException {
      unawaited(retryThenQueue());
    } catch (_) {
      unawaited(retryThenQueue());
    }
  }

  static Future<void> _deleteWithLocalTimeout(
    DocumentReference<Map<String, dynamic>> ref, {
    required String module,
    required String tenantId,
  }) async {
    Future<void> retryThenQueue() async {
      try {
        await ref.delete();
      } catch (_) {
        await _queueAfterBackgroundFailure(
          module: module,
          tenantId: tenantId,
          path: ref.path,
          operation: OfflineWriteOperations.delete,
          payload: {'path': ref.path},
        );
      }
    }

    try {
      await ref.delete().timeout(_kLocalWait);
    } on TimeoutException {
      unawaited(retryThenQueue());
    } catch (_) {
      unawaited(retryThenQueue());
    }
  }

  static Future<void> updateDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    String? module,
    String? tenantId,
  }) async {
    final path = ref.path;
    final tid = tenantId?.trim().isNotEmpty == true
        ? tenantId!.trim()
        : OfflineModules.tenantIdFromPath(path);
    final payload = FirestoreLastWriteWins.stamp(
      ChurchTenantFields.stamp(
        tid,
        FirestoreWriteGuard.stripHeavyFields(
          Map<String, dynamic>.from(data),
        ),
      ),
    );
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
      SyncService.notifyUserActionSaved();
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

    await runFirestorePublishWithRecovery<void>(
      () => _updateWithLocalTimeout(ref, payload, module: mod, tenantId: tid),
    );
    SyncService.notifyUserActionSaved();
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

    await runFirestorePublishWithRecovery<void>(
      () => _deleteWithLocalTimeout(ref, module: mod, tenantId: tid),
    );
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
        final batch = firebaseDefaultFirestore.batch();
        for (final w in writes) {
          final ref = firebaseDefaultFirestore.doc(w.path);
          final data = FirestoreWriteGuard.stripHeavyFields(w.data);
          final effectiveMerge = FirestoreWriteGuard.effectiveSetMerge(
            merge: w.merge,
            data: data,
          );
          if (effectiveMerge) {
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

    final batch = firebaseDefaultFirestore.batch();
    for (final w in writes) {
      final ref = firebaseDefaultFirestore.doc(w.path);
      final data = FirestoreWriteGuard.stripHeavyFields(w.data);
      final effectiveMerge = FirestoreWriteGuard.effectiveSetMerge(
        merge: w.merge,
        data: data,
      );
      if (effectiveMerge) {
        batch.set(ref, data, SetOptions(merge: true));
      } else {
        batch.set(ref, data);
      }
    }
    await runFirestorePublishWithRecovery<void>(() => batch.commit());
  }
}
