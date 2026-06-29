import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'app_google_sign_in.dart'
    show
        appGoogleSignInInteractive,
        appGoogleSignInSilently,
        firebaseCredentialFromGoogleAccount,
        isGoogleSignInUserCancellationException;
import 'gestor_oauth_onboarding_service.dart';
import 'login_preferences.dart';

/// Login expresso (mesmo padrão do app Controle Total):
///
///   1. Tenta `Google.signInSilently()` — usa a sessão já guardada do
///      Google Play Services / iCloud sem abrir UI.
///   2. Em iPhone/iPad, se silencioso falhar, tenta «Entrar com a Apple»
///      (compatível com a Diretriz 4.8 da App Store), salvo [skipApplePhase]
///      (ex.: último login guardado foi Google — vai direto ao passo 3).
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
  ///
  /// [onBeforeNativeOAuthUi] é chamado **antes** de abrir UI nativa (Apple ou seletor
  /// Google). Use para desligar spinners/overlays em Flutter — caso contrário a app
  /// pode ficar com barrier escuro por cima do picker do sistema.
  /// **Não** chamar no arranque da app — só botões «Login expresso» / renovação.
  /// Arranque: [PersistentAuthSessionService] + `firebaseDefaultAuth.currentUser`.
  static Future<ExpressLoginResult> tryExpressLogin({
    bool allowFallbackToGoogleUi = true,
    void Function()? onBeforeNativeOAuthUi,
    /// Quando `true`, não volta a chamar `signInSilently` (já executado na 1.ª fase
    /// sem overlay — evita spinner na faixa antes da UI nativa).
    bool skipSilentPhase = false,
    /// Quando `true`, não abre Sign in with Apple no iOS entre o silencioso e o
    /// Google com UI (ex.: último login bem-sucedido foi Google — evita Face ID
    /// + sheet Apple antes do seletor Google).
    bool skipApplePhase = false,
  }) async {
    if (kIsWeb) {
      return const ExpressLoginResult._(
        kind: ExpressLoginKind.unsupported,
      );
    }

    final user = firebaseDefaultAuth.currentUser;
    if (user != null) {
      return ExpressLoginResult._(
        kind: ExpressLoginKind.alreadySignedIn,
        userCredential: null,
      );
    }

    if (!skipSilentPhase && firebaseDefaultAuth.currentUser == null) {
      final silent = await _signInWithGoogleSilently();
      if (silent != null) {
        return ExpressLoginResult._(
          kind: ExpressLoginKind.googleSilent,
          userCredential: silent,
        );
      }
    }

    if (!skipApplePhase && defaultTargetPlatform == TargetPlatform.iOS) {
      onBeforeNativeOAuthUi?.call();
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

    onBeforeNativeOAuthUi?.call();
    try {
      final forcePicker = await LoginPreferences.shouldForceGoogleAccountPicker();
      final google = await GestorOAuthOnboardingService.signInWithGoogleNative(
        forceAccountPicker: forcePicker,
      );
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

  /// Só para o botão «Continuar com Google» — **não** chamar no arranque da app.
  static Future<UserCredential?> _signInWithGoogleSilently() async {
    if (firebaseDefaultAuth.currentUser != null) return null;
    try {
      final GoogleSignInAccount? account = await appGoogleSignInSilently();
      if (account == null) return null;
      return firebaseCredentialFromGoogleAccount(account);
    } on GoogleSignInException catch (e) {
      if (isGoogleSignInUserCancellationException(e)) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Apenas Google silencioso — 1.ª fase do login expresso sem overlay na UI Flutter.
  /// Interactivo / botão Google — nunca no cold start ([PersistentAuthSessionService]).
  static Future<UserCredential?> tryGoogleSilentOnly() async {
    if (kIsWeb) return null;
    if (firebaseDefaultAuth.currentUser != null) return null;
    return _signInWithGoogleSilently();
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

