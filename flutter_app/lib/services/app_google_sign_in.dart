import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth 2.0 **Web client** do projeto Firebase (`google-services.json` →
/// `client_type` 3). Necessário no Android para o Google Play Services emitir
/// `idToken` compatível com [FirebaseAuth] e evitar `ApiException: 10`
/// (DEVELOPER_ERROR) em `sign_in_failed`.
///
/// Se ainda falhar após isso, registre o SHA-1 do keystore (debug/release) em
/// Firebase Console → Configurações do projeto → Seu app Android.
const String kFirebaseGoogleOAuthWebClientId =
    '157235497908-93osahk8novc7i2n6jq2fotimfmhefi3.apps.googleusercontent.com';

GoogleSignIn? _cached;

/// Instância única com [GoogleSignIn.serverClientId] em mobile (Firebase Auth + idToken).
GoogleSignIn appGoogleSignIn() {
  if (_cached != null) return _cached!;
  if (kIsWeb) {
    _cached = GoogleSignIn();
  } else {
    _cached = GoogleSignIn(
      scopes: const <String>['email', 'profile'],
      serverClientId: kFirebaseGoogleOAuthWebClientId,
      // Android: ajuda a obter código de auth/idToken estável para o Firebase.
      forceCodeForRefreshToken: true,
    );
  }
  return _cached!;
}

/// `sign_in_failed` com DEVELOPER_ERROR (10) — costuma ser SHA-1 ausente/errado no Firebase
/// ou keystore diferente; também variações da mensagem entre versões do Play Services.
bool isGoogleSignInAndroidConfigError(PlatformException e) {
  if (e.code != 'sign_in_failed') return false;
  final m = (e.message ?? '').toLowerCase();
  return m.contains(': 10') ||
      m.contains(' 10,') ||
      m.contains('code: 10') ||
      m.contains('developer_error') ||
      m.contains('12500');
}
