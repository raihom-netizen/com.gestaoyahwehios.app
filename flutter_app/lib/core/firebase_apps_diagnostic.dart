import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';

/// Diagnóstico `Firebase.apps` antes de upload/publicação (Chat vs Avisos/Eventos).
void logFirebaseAppsBeforeOperation(String operation, {String? module}) {
  final names = Firebase.apps.map((a) => a.name).toList();
  final label = module == null ? operation : '$module|$operation';
  if (kDebugMode) {
    debugPrint(
      '[FirebaseApps] $label platform=${UnifiedUploadService.platformLabel} '
      'apps=$names empty=${names.isEmpty}',
    );
  }
  if (names.isEmpty) {
    unawaited(
      CrashlyticsService.record(
        StateError('Firebase.apps vazio antes de $label'),
        StackTrace.current,
        reason: 'firebase_apps_empty',
      ),
    );
  }
}
