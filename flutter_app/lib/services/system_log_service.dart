import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Logs centralizados multi-tenant (`system_logs`) — Regra 9.
abstract final class SystemLogService {
  SystemLogService._();

  static const String _collection = 'system_logs';

  static Future<void> record({
    required String module,
    required String message,
    String? tenantId,
    String? canonicalId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? extra,
    String severity = 'error',
  }) async {
    final user = firebaseDefaultAuth.currentUser;
    final uid = user?.uid ?? '';
    final payload = <String, dynamic>{
      'module': module.trim(),
      'message': message.trim(),
      'severity': severity,
      'uid': uid,
      if (tenantId != null && tenantId.trim().isNotEmpty)
        'tenantId': tenantId.trim(),
      if (canonicalId != null && canonicalId.trim().isNotEmpty)
        'canonicalId': canonicalId.trim(),
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
      if (extra != null && extra.isNotEmpty) 'extra': extra,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'flutter',
    };

    if (kDebugMode) {
      debugPrint('SystemLog[$severity] $module: $message');
    }

    if (uid.isEmpty) return;

    try {
      await firebaseDefaultFirestore.collection(_collection).add(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SystemLogService.write failed: $e');
      }
    }
  }

  static Future<void> recordTenantAccessDenied({
    required String module,
    required String tenantId,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      record(
        module: module,
        message: 'permission-denied ou tenant incorreto',
        tenantId: tenantId,
        error: error,
        stackTrace: stackTrace,
        severity: 'warn',
        extra: const {'kind': 'tenant_access_denied'},
      );
}

