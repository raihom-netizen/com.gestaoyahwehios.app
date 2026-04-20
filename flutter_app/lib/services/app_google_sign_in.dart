import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, GoogleAuthProvider;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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

/// OAuth iOS (mesmo [CLIENT_ID] em `ios/Runner/GoogleService-Info.plist`).
const String kFirebaseIosGoogleClientId =
    '157235497908-m9fdpqeb6rj8gj6e1fsi9mfjpja2s5bg.apps.googleusercontent.com';

/// [FirebaseAuth] na web (`signInWithPopup` / `signInWithRedirect`): escopos e
/// `prompt=select_account` para evitar conta errada em cache do navegador.
GoogleAuthProvider firebaseWebGoogleAuthProvider() {
  final p = GoogleAuthProvider();
  p.addScope('email');
  p.addScope('profile');
  p.setCustomParameters(<String, String>{'prompt': 'select_account'});
  return p;
}

GoogleSignIn? _cached;

/// Instância única com [GoogleSignIn.serverClientId] em mobile (Firebase Auth + idToken).
GoogleSignIn appGoogleSignIn() {
  if (_cached != null) return _cached!;
  if (kIsWeb) {
    _cached = GoogleSignIn();
  } else {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    _cached = GoogleSignIn(
      scopes: const <String>['email', 'profile'],
      serverClientId: kFirebaseGoogleOAuthWebClientId,
      clientId: isIos ? kFirebaseIosGoogleClientId : null,
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

/// Utilizador fechou o seletor Google / tocou voltar — não mostrar erro.
bool isGoogleSignInUserCancellation(PlatformException e) {
  final c = e.code.toLowerCase();
  if (c == 'sign_in_canceled' || c == 'sign_in_cancelled') return true;
  final m = (e.message ?? '').toLowerCase();
  if (c == 'sign_in_failed' &&
      (m.contains('12501') ||
          m.contains('user_canceled') ||
          m.contains('cancelled'))) {
    return true;
  }
  if (m.contains('canceled') && m.contains('12501')) return true;
  return false;
}

/// Mensagens PT-BR para login Google (Firebase Auth Web/Android/iOS).
/// Devolve `null` quando não deve ser mostrada mensagem (cancelamento).
String? googleAuthErrorMessagePt(FirebaseAuthException e) {
  final code = e.code.toLowerCase();
  final raw = (e.message ?? '').toLowerCase();
  if (code.contains('popup-closed') ||
      code.contains('popup_closed_by_user') ||
      code == 'cancelled' ||
      code.contains('auth/cancelled') ||
      raw.contains('popup closed') ||
      raw.contains('popup_closed')) {
    return null;
  }
  if (code.contains('account-exists-with-different-credential')) {
    return 'Este e-mail já tem login com senha. Use e-mail e senha ou peça ao gestor para alinhar o acesso.';
  }
  if (code.contains('invalid-credential')) {
    return 'Não foi possível validar o login com Google. Tente de novo ou use e-mail e senha.';
  }
  if (code.contains('unauthorized-domain')) {
    return 'Este domínio não está autorizado para login Google. '
        'Em Firebase Console → Authentication → Settings, adicione o domínio em «Authorized domains».';
  }
  if (code.contains('operation-not-allowed')) {
    return 'Login com Google não está ativado no projeto. '
        'Ative o provedor Google em Firebase Console → Authentication → Sign-in method.';
  }
  if (code.contains('web-storage-unsupported') ||
      code.contains('storage-unsupported')) {
    return 'O navegador bloqueou armazenamento necessário para o login. '
        'Saia do modo anónimo ou permita cookies e armazenamento para este site.';
  }
  if (code.contains('network-request-failed') ||
      raw.contains('network')) {
    return 'Sem ligação estável. Verifique a internet e tente de novo.';
  }
  if (code.contains('too-many-requests')) {
    return 'Demasiadas tentativas. Aguarde alguns minutos ou use e-mail e senha.';
  }
  if (code.contains('user-disabled')) {
    return 'Esta conta foi desativada. Contacte o gestor ou o suporte.';
  }
  return e.message ?? e.code;
}
