import 'package:firebase_core/firebase_core.dart';
import 'package:gestao_yahweh/firebase_options.dart';

/// Inicialização única do núcleo Firebase (`[DEFAULT]` + options da plataforma).
///
/// O arranque completo (health Auth/Firestore/Storage) continua em
/// [FirebaseBootstrapService.initialize] no [main].
abstract final class FirebaseBootstrap {
  FirebaseBootstrap._();

  static Future<void>? _future;

  /// Garante `Firebase.initializeApp` uma vez — idempotente em hot restart.
  static Future<void> ensureInitialized() {
    _future ??= _initialize();
    return _future!;
  }

  static Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }
}
