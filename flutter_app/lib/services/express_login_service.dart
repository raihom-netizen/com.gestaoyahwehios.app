import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'app_google_sign_in.dart' show appGoogleSignIn;
import 'gestor_oauth_onboarding_service.dart';

/// Login expresso (mesmo padrão do app Controle Total):
///
///   1. Tenta `Google.signInSilently()` — usa a sessão já guardada do
///      Google Play Services / iCloud sem abrir UI.
///   2. Em iPhone/iPad, se silencioso falhar, tenta «Entrar com a Apple»
///      (compatível com a Diretriz 4.8 da App Store).
///   3. Como último recurso abre o seletor Google nativo (com UI).
///
/// Em qualquer falha (rede / cancelamento / token vazio) retorna `null` —
/// o chamador decide se mostra mensagem ou cai para o fluxo manual.
///
/// Não depende de Firestore / Cloud Functions: a rota pós-login é decidida
/// fora (por exemplo, `LoginPage._afterGoogleSignInSuccess`).
class ExpressLoginService {
  ExpressLoginService._();

  /// Resultado da tentativa de login expresso.
  static Future<ExpressLoginResult> tryExpressLogin({
    bool allowFallbackToGoogleUi = true,
  }) async {
    if (kIsWeb) {
      return const ExpressLoginResult._(
        kind: ExpressLoginKind.unsupported,
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return ExpressLoginResult._(
        kind: ExpressLoginKind.alreadySignedIn,
        userCredential: null,
      );
    }

    final silent = await _signInWithGoogleSilently();
    if (silent != null) {
      return ExpressLoginResult._(
        kind: ExpressLoginKind.googleSilent,
        userCredential: silent,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final apple =
            await GestorOAuthOnboardingService.signInWithAppleIfAvailable();
        if (apple != null) {
          return ExpressLoginResult._(
            kind: ExpressLoginKind.apple,
            userCredential: apple,
          );
        }
      } catch (_) {
        // segue para Google com UI
      }
    }

    if (!allowFallbackToGoogleUi) {
      return const ExpressLoginResult._(kind: ExpressLoginKind.cancelled);
    }

    try {
      final google = await GestorOAuthOnboardingService.signInWithGoogleNative();
      return ExpressLoginResult._(
        kind: ExpressLoginKind.googleInteractive,
        userCredential: google,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'cancelled') {
        return const ExpressLoginResult._(kind: ExpressLoginKind.cancelled);
      }
      return ExpressLoginResult._(
        kind: ExpressLoginKind.error,
        errorMessage: e.message ?? e.code,
      );
    } catch (e) {
      return ExpressLoginResult._(
        kind: ExpressLoginKind.error,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<UserCredential?> _signInWithGoogleSilently() async {
    try {
      final GoogleSignInAccount? account =
          await appGoogleSignIn().signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      final idTok = auth.idToken;
      if (idTok == null || idTok.isEmpty) return null;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: idTok,
      );
      return FirebaseAuth.instance.signInWithCredential(credential);
    } catch (_) {
      return null;
    }
  }
}

enum ExpressLoginKind {
  /// Já existia sessão Firebase ativa.
  alreadySignedIn,

  /// Login Google sem UI (sessão guardada).
  googleSilent,

  /// Login com Apple (iPhone/iPad).
  apple,

  /// Google nativo com UI (utilizador escolheu conta).
  googleInteractive,

  /// Utilizador cancelou em algum dos passos.
  cancelled,

  /// Plataforma não suporta (ex.: web — usar [signInWithPopup]).
  unsupported,

  /// Erro técnico (rede, token, configuração).
  error,
}

class ExpressLoginResult {
  final ExpressLoginKind kind;
  final UserCredential? userCredential;
  final String? errorMessage;

  const ExpressLoginResult._({
    required this.kind,
    this.userCredential,
    this.errorMessage,
  });

  bool get success =>
      kind == ExpressLoginKind.googleSilent ||
      kind == ExpressLoginKind.apple ||
      kind == ExpressLoginKind.googleInteractive ||
      kind == ExpressLoginKind.alreadySignedIn;

  bool get isCancellation => kind == ExpressLoginKind.cancelled;
  bool get isUnsupported => kind == ExpressLoginKind.unsupported;
  bool get isError => kind == ExpressLoginKind.error;
}
