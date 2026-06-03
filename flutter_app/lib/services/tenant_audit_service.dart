import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';

/// Auditoria tenant — quem criou/editou/excluiu, quando, dispositivo.
abstract final class TenantAuditService {
  TenantAuditService._();

  static const auditedModules = <String>{
    OfflineModules.financeiro,
    OfflineModules.patrimonio,
    OfflineModules.membros,
    OfflineModules.escalas,
  };

  static String deviceLabel() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem}_${Platform.operatingSystemVersion}';
    } catch (_) {
      return defaultTargetPlatform.name;
    }
  }

  static Future<void> log({
    required String tenantId,
    required String module,
    required String action,
    required String docPath,
    String? docId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    if (!auditedModules.contains(module)) return;

    try {
      final u = firebaseDefaultAuth.currentUser;
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tid)
          .collection('auditoria_tenant')
          .add({
        'acao': action,
        'modulo': module,
        'docPath': docPath,
        if (docId != null) 'docId': docId,
        'uid': u?.uid,
        'email': u?.email,
        'dispositivo': deviceLabel(),
        'plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'criadoEm': FieldValue.serverTimestamp(),
        if (before != null) 'antes': before,
        if (after != null) 'depois': after,
      });
    } catch (_) {}
  }

  static Future<void> logCreate({
    required String tenantId,
    required String module,
    required String docPath,
    Map<String, dynamic>? data,
  }) =>
      log(
        tenantId: tenantId,
        module: module,
        action: 'criar',
        docPath: docPath,
        after: data,
      );

  static Future<void> logUpdate({
    required String tenantId,
    required String module,
    required String docPath,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) =>
      log(
        tenantId: tenantId,
        module: module,
        action: 'editar',
        docPath: docPath,
        before: before,
        after: after,
      );

  static Future<void> logDelete({
    required String tenantId,
    required String module,
    required String docPath,
    Map<String, dynamic>? before,
  }) =>
      log(
        tenantId: tenantId,
        module: module,
        action: 'excluir',
        docPath: docPath,
        before: before,
      );
}
