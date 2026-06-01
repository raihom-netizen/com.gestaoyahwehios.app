import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';

/// Erros esperados (sessão, stream duplicado, bootstrap recuperável) — não são crash de produção.
abstract final class CrashlyticsBenignErrors {
  CrashlyticsBenignErrors._();

  static bool isBenign(Object error) {
    if (error is FirebaseBootstrapException) {
      return _bootstrapBenign(error);
    }
    if (error is StateError) {
      return _stateBenign(error.message);
    }
    if (error is FirebaseException) {
      return _firebaseBenign(error);
    }
    return _stringBenign(error.toString());
  }

  static bool _bootstrapBenign(FirebaseBootstrapException e) {
    const benignCodes = {
      'auth_session_expired',
      'auth_no_user',
      'auth_anonymous',
      'not_initialized',
      'timeout',
    };
    if (benignCodes.contains(e.code)) return true;
    final cause = e.cause;
    if (cause is StateError && _stateBenign(cause.message)) return true;
    if (isFirebaseNoAppError(cause)) return true;
    return _stringBenign(cause.toString());
  }

  static bool _stateBenign(String message) {
    final m = message.toLowerCase();
    if (m.contains('sessão expirada')) return true;
    if (m.contains('stream has already been listened')) return true;
    if (m.contains('cannot add new events after calling close')) return true;
    if (m.contains('cannot add event after closing')) return true;
    return false;
  }

  static bool _firebaseBenign(FirebaseException e) {
    if (e.code == 'permission-denied' || e.code == 'unauthorized') {
      return true;
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      return true;
    }
    return isFirebaseNoAppError(e);
  }

  static bool _stringBenign(String raw) {
    final low = raw.toLowerCase();
    if (low.contains('sessão expirada')) return true;
    if (low.contains('stream has already been listened')) return true;
    if (low.contains('firebasebootstrapexception')) {
      if (low.contains('auth_session') ||
          low.contains('auth_no_user') ||
          low.contains('sessão')) {
        return true;
      }
    }
    return isFirebaseNoAppError(raw);
  }
}
