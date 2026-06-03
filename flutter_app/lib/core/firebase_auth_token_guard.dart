import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Evita esgotar a quota do Identity Toolkit (getIdToken / getIdTokenResult).
///
/// Sintoma em produção: `auth/quota-exceeded`, painel lento, chat skeleton,
/// eventos não gravam, `bootstrap_failed` em cascata por retries.
abstract final class FirebaseAuthTokenGuard {
  FirebaseAuthTokenGuard._();

  static const _minRefreshGap = Duration(minutes: 10);
  static const _quotaBackoff = Duration(minutes: 35);
  static const _resumeMinGap = Duration(seconds: 90);

  static DateTime? _lastRefreshOkAt;
  static DateTime? _quotaBackoffUntil;
  static DateTime? _lastResumeHandledAt;

  static bool isQuotaExceeded(Object e) {
    if (e is FirebaseAuthException) {
      final c = e.code.toLowerCase();
      return c == 'quota-exceeded' ||
          c == 'too-many-requests' ||
          c == 'resource-exhausted';
    }
    final low = e.toString().toLowerCase();
    return low.contains('quota') &&
        (low.contains('exceed') || low.contains('exceeded'));
  }

  static bool get isInQuotaBackoff {
    final until = _quotaBackoffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static void recordQuotaExceeded([Object? cause]) {
    _quotaBackoffUntil = DateTime.now().add(_quotaBackoff);
    if (kDebugMode) {
      debugPrint(
        'FirebaseAuthTokenGuard: quota backoff até $_quotaBackoffUntil'
        '${cause != null ? ' ($cause)' : ''}',
      );
    }
  }

  static String get quotaUserMessage =>
      'Limite temporário da autenticação Firebase (quota excedida). '
      'Feche outras abas do painel, aguarde cerca de 30 minutos e recarregue (Ctrl+F5). '
      'Se voltar sempre, confira o plano Blaze e quotas no Console Firebase.';

  /// Retoma global — no máximo um refresh completo a cada [_resumeMinGap].
  static bool shouldHandleAppResume() {
    final now = DateTime.now();
    final last = _lastResumeHandledAt;
    if (last != null && now.difference(last) < _resumeMinGap) {
      return false;
    }
    _lastResumeHandledAt = now;
    return true;
  }

  /// Renova JWT só se necessário; em backoff de quota não chama a API.
  static Future<void> refreshIfStale({
    bool force = false,
    Duration minGap = _minRefreshGap,
  }) async {
    if (isInQuotaBackoff) {
      if (force) {
        throw FirebaseAuthException(
          code: 'quota-exceeded',
          message: quotaUserMessage,
        );
      }
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    if (!force) {
      final last = _lastRefreshOkAt;
      if (last != null && DateTime.now().difference(last) < minGap) {
        return;
      }
    }

    try {
      await user.getIdToken(force).timeout(const Duration(seconds: 15));
      _lastRefreshOkAt = DateTime.now();
    } catch (e) {
      if (isQuotaExceeded(e)) {
        recordQuotaExceeded(e);
      }
      if (force) rethrow;
    }
  }
}
