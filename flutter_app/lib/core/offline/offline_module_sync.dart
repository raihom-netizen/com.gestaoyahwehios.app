import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';

/// Fachadas por módulo — fila Hive quando offline (Fase 2).
abstract final class MembrosOfflineSync {
  MembrosOfflineSync._();

  static Future<void> set({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
    bool merge = false,
  }) =>
      TenantOfflineWrite.setDocument(
        ref: ref,
        data: data,
        merge: merge,
        module: OfflineModules.membros,
        tenantId: tenantId,
      );

  static Future<void> update({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
  }) =>
      TenantOfflineWrite.updateDocument(
        ref: ref,
        data: data,
        module: OfflineModules.membros,
        tenantId: tenantId,
      );
}

abstract final class EventosOfflineSync {
  EventosOfflineSync._();

  static Future<void> set({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
    bool merge = false,
  }) =>
      TenantOfflineWrite.setDocument(
        ref: ref,
        data: data,
        merge: merge,
        module: OfflineModules.eventos,
        tenantId: tenantId,
      );
}

abstract final class AvisosOfflineSync {
  AvisosOfflineSync._();

  static Future<void> set({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
    bool merge = false,
  }) =>
      TenantOfflineWrite.setDocument(
        ref: ref,
        data: data,
        merge: merge,
        module: OfflineModules.avisos,
        tenantId: tenantId,
      );
}

abstract final class PatrimonioOfflineSync {
  PatrimonioOfflineSync._();

  static Future<void> set({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
    bool merge = false,
  }) =>
      TenantOfflineWrite.setDocument(
        ref: ref,
        data: data,
        merge: merge,
        module: OfflineModules.patrimonio,
        tenantId: tenantId,
      );

  static Future<void> update({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
  }) =>
      TenantOfflineWrite.updateDocument(
        ref: ref,
        data: data,
        module: OfflineModules.patrimonio,
        tenantId: tenantId,
      );
}

abstract final class FinanceiroOfflineSync {
  FinanceiroOfflineSync._();

  static Future<void> batchSet({
    required String tenantId,
    required List<({
      String path,
      Map<String, dynamic> data,
      bool merge,
    })> writes,
  }) =>
      TenantOfflineWrite.batchSet(
        tenantId: tenantId,
        module: OfflineModules.financeiro,
        writes: writes,
      );
}

abstract final class EscalasOfflineSync {
  EscalasOfflineSync._();

  static Future<void> update({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String tenantId,
  }) =>
      TenantOfflineWrite.updateDocument(
        ref: ref,
        data: data,
        module: OfflineModules.escalas,
        tenantId: tenantId,
      );
}

/// Contagem de tarefas pendentes na fila (diagnóstico / futura UI).
abstract final class OfflineQueueStats {
  OfflineQueueStats._();

  static Future<int> pendingTotal() async {
    return (await HiveLocalStore.instance.listTasks()).length;
  }

  static Future<int> pendingForModule(String module) async {
    return (await HiveLocalStore.instance.listTasks(module: module)).length;
  }

  static Future<void> flushModule(String module) async {
    await SyncEngine.repository.flushModule(module);
  }
}
