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

/// Login expresso (mesmo padrÃ£o do app Controle Total):
///
///   1. Tenta `Google.signInSilently()` â€” usa a sessÃ£o jÃ¡ guardada do
///      Google Play Services / iCloud sem abrir UI.
///   2. Em iPhone/iPad, se silencioso falhar, tenta Â«Entrar com a AppleÂ»
///      (compatÃ­vel com a Diretriz 4.8 da App Store), salvo [skipApplePhase]
///      (ex.: Ãºltimo login guardado foi Google â€” vai direto ao passo 3).
///   3. Como Ãºltimo recurso abre o seletor Google nativo (com UI).
///
/// Em qualquer falha (rede / cancelamento / token vazio) retorna `null` â€”
/// o chamador decide se mostra mensagem ou cai para o fluxo manual.
///
/// NÃ£o depende de Firestore / Cloud Functions: a rota pÃ³s-login Ã© decidida
/// fora (por exemplo, `LoginPage._afterGoogleSignInSuccess`).
class ExpressLoginService {
  ExpressLoginService._();

  /// Resultado da tentativa de login expresso.
  ///
  /// [onBeforeNativeOAuthUi] Ã© chamado **antes** de abrir UI nativa (Apple ou seletor
  /// Google). Use para desligar spinners/overlays em Flutter â€” caso contrÃ¡rio a app
  /// pode ficar com barrier escuro por cima do picker do sistema.
  /// **NÃ£o** chamar no arranque da app â€” sÃ³ botÃµes Â«Login expressoÂ» / renovaÃ§Ã£o.
  /// Arranque: [PersistentAuthSessionService] + `firebaseDefaultAuth.currentUser`.
  static Future<ExpressLoginResult> tryExpressLogin({
    bool allowFallbackToGoogleUi = true,
    void Function()? onBeforeNativeOAuthUi,
    /// Quando `true`, nÃ£o volta a chamar `signInSilently` (jÃ¡ executado na 1.Âª fase
    /// sem overlay â€” evita spinner na faixa antes da UI nativa).
    bool skipSilentPhase = false,
    /// Quando `true`, nÃ£o abre Sign in with Apple no iOS entre o silencioso e o
    /// Google com UI (ex.: Ãºltimo login bem-sucedido foi Google â€” evita Face ID
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

  /// SÃ³ para o botÃ£o Â«Continuar com GoogleÂ» â€” **nÃ£o** chamar no arranque da app.
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

  /// Apenas Google silencioso â€” 1.Âª fase do login expresso sem overlay na UI Flutter.
  /// Interactivo / botÃ£o Google â€” nunca no cold start ([PersistentAuthSessionService]).
  static Future<UserCredential?> tryGoogleSilentOnly() async {
    if (kIsWeb) return null;
    if (firebaseDefaultAuth.currentUser != null) return null;
    return _signInWithGoogleSilently();
  }
}

enum ExpressLoginKind {
  /// JÃ¡ existia sessÃ£o Firebase ativa.
  alreadySignedIn,

  /// Login Google sem UI (sessÃ£o guardada).
  googleSilent,

  /// Login com Apple (iPhone/iPad).
  apple,

  /// Google nativo com UI (utilizador escolheu conta).
  googleInteractive,

  /// Utilizador cancelou em algum dos passos.
  cancelled,

  /// Plataforma nÃ£o suporta (ex.: web â€” usar [signInWithPopup]).
  unsupported,

  /// Erro tÃ©cnico (rede, token, configuraÃ§Ã£o).
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

