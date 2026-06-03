import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';

/// Escritas textuais **optimistas** — UI instantânea, sync silenciosa em background.
///
/// - **Online:** grava no Firestore (mobile com persistence → cache local imediato).
/// - **Offline:** fila Hive + espelho no cache Firestore (mobile); web grava directo quando online.
/// - Falhas de rede **não** bloqueiam a UI — [SyncEngine] reenvia ao voltar online.
abstract final class OptimisticFirestoreWrite {
  OptimisticFirestoreWrite._();

  static Future<void> set({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    bool merge = false,
    String? module,
    String? tenantId,
  }) =>
      TenantOfflineWrite.setDocument(
        ref: ref,
        data: data,
        merge: merge,
        module: module,
        tenantId: tenantId,
      );

  static Future<void> update({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    String? module,
    String? tenantId,
  }) =>
      TenantOfflineWrite.updateDocument(
        ref: ref,
        data: data,
        module: module,
        tenantId: tenantId,
      );

  static Future<void> delete({
    required DocumentReference<Map<String, dynamic>> ref,
    String? module,
    String? tenantId,
  }) =>
      TenantOfflineWrite.deleteDocument(
        ref: ref,
        module: module,
        tenantId: tenantId,
      );
}
