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
  unawaited(CrashlyticsService.record(error, stack, reason: label));
}
