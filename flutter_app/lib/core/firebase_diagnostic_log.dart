import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
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

/// Chat / Firestore — path exato quando `permission-denied` ou falha de leitura.
void logChatFirestoreAccess({
  required String path,
  required String churchId,
  Object? error,
  StackTrace? stack,
}) {
  String uid = '';
  try {
    uid = firebaseDefaultAuth.currentUser?.uid ?? '';
  } catch (_) {}
  if (kDebugMode) {
    debugPrint('CHAT PATH=$path');
    debugPrint('CHURCH=$churchId');
    debugPrint('UID=$uid');
    if (error != null) debugPrint('ERROR=$error');
    if (stack != null) debugPrint(stack.toString());
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
