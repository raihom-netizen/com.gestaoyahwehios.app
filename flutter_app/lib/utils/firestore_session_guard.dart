import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Evita `permission-denied` quando o Auth ainda restaura o token (cold start Web).
///
/// Padrão Controle Total — Web = Android = iOS: esperar sessão, refresh token,
/// retry em permission-denied / unavailable antes de declarar «sem dados».
class FirestoreSessionGuard {
  FirestoreSessionGuard._();

  static DateTime? _lastStabilizeAt;
  static Future<void>? _stabilizeInFlight;

  static bool isPermissionLikeError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied' ||
          code == 'unauthenticated' ||
          code == 'unavailable' ||
          code == 'deadline-exceeded') {
        return true;
      }
      final msg = '${error.message ?? ''} ${error.toString()}'.toLowerCase();
      if (msg.contains('permission-denied') ||
          msg.contains('permission_denied') ||
          msg.contains('insufficient permissions') ||
          msg.contains('unauthenticated') ||
          msg.contains('unavailable') ||
          msg.contains('network')) {
        return true;
      }
    }
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('unauthenticated') ||
        text.contains('unavailable') ||
        text.contains('failed to get document because the client is offline');
  }

  static Future<void> refreshAuthSession({bool forceToken = true}) async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) return;
    try {
      await user.getIdToken(forceToken);
    } catch (_) {}
    try {
      await user.reload();
    } catch (_) {}
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
  }

  /// Aguarda o Firebase Auth restaurar a sessão (até [timeout]).
  static Future<User?> waitForCurrentUser({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    var user = firebaseDefaultAuth.currentUser;
    if (user != null) return user;
    try {
      user = await firebaseDefaultAuth
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(timeout);
    } catch (_) {}
    return user ?? firebaseDefaultAuth.currentUser;
  }

  /// Antes de leituras/gravações — token alinhado às regras do Firestore.
  static Future<void> ensureWriteSession() async {
    var user = firebaseDefaultAuth.currentUser;
    if (user == null) {
      user = await waitForCurrentUser(timeout: const Duration(seconds: 3));
    }
    if (user == null) return;
    try {
      await user.getIdToken(false);
    } catch (_) {
      try {
        await user.getIdToken(true);
      } catch (_) {}
    }
  }

  /// Resume / cold start Web — força token novo antes dos módulos lerem.
  static Future<void> stabilizeAfterAppResume() async {
    final inflight = _stabilizeInFlight;
    if (inflight != null) return inflight;

    final last = _lastStabilizeAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return;
    }

    final fut = () async {
      try {
        await waitForCurrentUser(timeout: const Duration(seconds: 5));
        await refreshAuthSession(forceToken: true);
        if (kIsWeb) {
          await FirestoreWebGuard.stabilizeAfterWebSignIn();
        }
        _lastStabilizeAt = DateTime.now();
      } finally {
        _stabilizeInFlight = null;
      }
    }();
    _stabilizeInFlight = fut;
    return fut;
  }

  /// Stream com auto-recuperação: permission-denied → estabiliza e reabre.
  static Stream<T> authAwareSnapshots<T>(
    Stream<T> Function() open, {
    int maxAutoRetries = 3,
  }) {
    return Stream<T>.multi((controller) {
      StreamSubscription<T>? sub;
      var attempts = 0;
      var cancelled = false;

      Future<void> attach() async {
        if (cancelled) return;
        await sub?.cancel();
        sub = null;
        try {
          if (attempts > 0) {
            await stabilizeAfterAppResume();
            await Future<void>.delayed(Duration(milliseconds: 220 * attempts));
          }
          if (cancelled) return;
          sub = open().listen(
            controller.add,
            onError: (Object e, StackTrace st) async {
              if (cancelled) return;
              if (kIsWeb &&
                  (FirestoreWebGuard.isInternalAssertionError(e) ||
                      FirestoreWebGuard.isClientTerminated(e))) {
                FirestoreWebGuard.handleFatalWebErrorIfNeeded(e);
                if (!controller.isClosed) controller.addError(e, st);
                return;
              }
              if (isPermissionLikeError(e) && attempts < maxAutoRetries) {
                attempts++;
                await attach();
                return;
              }
              if (!controller.isClosed) controller.addError(e, st);
            },
            onDone: () {
              if (!controller.isClosed) controller.close();
            },
            cancelOnError: false,
          );
        } catch (e, st) {
          if (cancelled) return;
          if (isPermissionLikeError(e) && attempts < maxAutoRetries) {
            attempts++;
            await attach();
            return;
          }
          if (!controller.isClosed) controller.addError(e, st);
        }
      }

      unawaited(attach());
      controller.onCancel = () async {
        cancelled = true;
        await sub?.cancel();
      };
    });
  }

  static Future<T> runWithAuthRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await stabilizeAfterAppResume();
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
        } else {
          await ensureWriteSession();
        }
        return await action();
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (kIsWeb && FirestoreWebGuard.isClientTerminated(e)) {
          FirestoreWebGuard.handleFatalWebErrorIfNeeded(e);
          Error.throwWithStackTrace(e, st);
        }
        final retry = isPermissionLikeError(e) ||
            (kIsWeb && FirestoreWebGuard.isInternalAssertionError(e));
        if (!retry || attempt >= maxAttempts - 1) {
          Error.throwWithStackTrace(e, st);
        }
        // Soft only — nunca terminate() no hot path.
        if (kIsWeb && FirestoreWebGuard.isInternalAssertionError(e)) {
          await FirestoreWebGuard.softRecoverWebSession();
        } else {
          await refreshAuthSession(forceToken: true);
        }
      }
    }
    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
    throw lastError ?? StateError('firestore_session_guard: exhausted');
  }
}
