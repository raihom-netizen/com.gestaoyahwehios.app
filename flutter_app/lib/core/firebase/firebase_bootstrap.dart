import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/firebase_options.dart';

/// Inicialização única do núcleo Firebase (`[DEFAULT]` + options da plataforma).
///
/// O arranque completo (health Auth/Firestore/Storage) continua em
/// [FirebaseBootstrapService.initialize] no [main].
abstract final class FirebaseBootstrap {
  FirebaseBootstrap._();

  static Future<void>? _future;

  /// Garante `Firebase.initializeApp` — reexecuta se o app `[DEFAULT]` sumiu.
  static Future<void> ensureInitialized() {
    if (_hasDefaultApp()) {
      return Future.value();
    }
    final inFlight = _future;
    if (inFlight != null) return inFlight;
    final init = _initialize();
    _future = init;
    return init.catchError((Object e, StackTrace st) {
      if (!_hasDefaultApp()) {
        _future = null;
      }
      Error.throwWithStackTrace(e, st);
    });
  }

  /// Chamado por [FirebaseBootstrapService] ao reconectar/reiniciar o núcleo.
  /// Não cancela init em curso nem limpa estado se o app [DEFAULT] já existe.
  static void reset() {
    if (_hasDefaultApp()) return;
    _future = null;
  }

  static bool _hasDefaultApp() {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _initialize() async {
    if (_hasDefaultApp()) {
      if (kDebugMode) {
        debugPrint('FIREBASE INIT OK (já existia)');
        debugPrint('FIREBASE APPS=${Firebase.apps.length}');
      }
      return;
    }
    if (kDebugMode) debugPrint('FIREBASE INIT START');
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (kDebugMode) {
        debugPrint('FIREBASE INIT OK');
        debugPrint('FIREBASE APPS=${Firebase.apps.length}');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' && _hasDefaultApp()) {
        if (kDebugMode) {
          debugPrint('FIREBASE INIT OK (duplicate-app)');
          debugPrint('FIREBASE APPS=${Firebase.apps.length}');
        }
        return;
      }
      rethrow;
    }
  }
}
