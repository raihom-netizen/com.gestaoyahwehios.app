import 'package:firebase_core/firebase_core.dart';
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
    _future = null;
    _future ??= _initialize();
    return _future!;
  }

  /// Chamado por [FirebaseBootstrapService] ao reconectar/reiniciar o núcleo.
  static void reset() {
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
    if (_hasDefaultApp()) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' && _hasDefaultApp()) return;
      rethrow;
    }
  }
}
