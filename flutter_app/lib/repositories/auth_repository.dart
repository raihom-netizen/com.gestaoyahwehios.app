import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/auth_service.dart';

/// Fachada de autenticação (Clean Architecture).
///
/// Telas e widgets devem preferir [AuthRepository] em vez de aceder
/// directamente a `FirebaseAuth.instance`.
abstract final class AuthRepository {
  AuthRepository._();

  static User? get currentUser => AuthService.currentUser;

  static bool get hasActiveSession => AuthService.hasActiveSession;

  static Future<void> configurePersistentSession() =>
      AuthService.configurePersistentSession();

  static String painelRouteIfSession({required String fallback}) =>
      AuthService.painelRouteIfSession(fallback: fallback);

  static Future<void> signOutForAccountSwitch() =>
      AuthService.signOutForAccountSwitch();

  static Future<void> clearLocalSessionCache({String? uid}) =>
      AuthService.clearLocalSessionCache(uid: uid);

  static Stream<User?> watchAuthState() =>
      firebaseDefaultAuth.authStateChanges();
}
