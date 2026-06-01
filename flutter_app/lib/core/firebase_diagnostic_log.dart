import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// Log da exceção **real** (nunca mensagem genérica mascarada).
void logFirebaseDiagnostic(
  Object error,
  StackTrace? stack, {
  String? context,
}) {
  final label = context ?? 'firebase';
  if (kDebugMode) {
    debugPrint('[$label] $error');
    if (stack != null) debugPrint(stack.toString());
  }
  if (CrashlyticsService.shouldReport(error)) {
    unawaited(CrashlyticsService.record(error, stack, reason: label));
  }
}

/// Fases de publicação avisos/eventos (upload → Firestore).
void logFirebasePublishPhase(
  String phase,
  String context, {
  Object? error,
  StackTrace? stack,
}) {
  if (kDebugMode) {
    debugPrint('[$phase] $context${error != null ? ' | $error' : ''}');
  }
  if (error != null && CrashlyticsService.shouldReport(error)) {
    unawaited(
      CrashlyticsService.record(error, stack, reason: '${phase}_$context'),
    );
  }
}
