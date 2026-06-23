import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart'
    show
        appGoogleSignOutForAccountPicker,
        appGoogleSignInInteractive,
        firebaseCredentialFromGoogleAccount,
        isGoogleSignInUserCancellationException;
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/gestor_membro_stub_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Login social no onboarding: painel se jÃ¡ tem igreja; senÃ£o `/signup/completar-dados` (perfil + igreja).
class GestorOAuthOnboardingService {
  GestorOAuthOnboardingService._();

  static Future<void> routeAfterOAuthSignIn(BuildContext context) async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) return;

    final doc =
        await firebaseDefaultFirestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    final igrejaId =
        (data?['igrejaId'] ?? data?['tenantId'] ?? '').toString().trim();

    if (!context.mounted) return;
    if (igrejaId.isNotEmpty) {
      final role = (data?['role'] ?? 'gestor').toString();
      await GestorMembroStubService.ensurePreCadastroGestor(
        tenantId: igrejaId,
        role: role,
      );
      if (!context.mounted) return;
      await ChurchAutoSessionService.persistAfterSuccessfulPainelLogin();
      unawaited(
        ChurchAutoSessionService.preheatPanelCachesCoordinated(
          tenantIdHint: igrejaId,
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta jÃ¡ vinculada. Redirecionando ao painel.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } else {
      if (IosPaymentsGate.hideOrganizationSignup) {
        await firebaseDefaultAuth.signOut();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esta conta ainda nÃ£o estÃ¡ vinculada a uma igreja. '
              'No app iOS sÃ³ Ã© possÃ­vel entrar com conta existente. '
              'Cadastro de nova igreja: gestaoyahweh.com.br (navegador). '
              'Se jÃ¡ Ã© gestor, use o e-mail da igreja cadastrada.',
            ),
            duration: Duration(seconds: 7),
          ),
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/igreja/login',
          (_) => false,
        );
        return;
      }
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/signup/completar-dados',
        (_) => false,
      );
    }
  }

  /// [forceAccountPicker] â€” cadastro / troca de conta; senÃ£o tenta silencioso primeiro.
  static Future<UserCredential> signInWithGoogleNative({
    bool forceAccountPicker = false,
  }) async {
    if (kIsWeb) {
      throw StateError('Use signInWithPopup na web.');
    }
    final forcePicker = forceAccountPicker ||
        await LoginPreferences.shouldForceGoogleAccountPicker();

    // Silencioso sÃ³ no botÃ£o manual e sem sessÃ£o Firebase (nunca no arranque).
    if (!forcePicker && firebaseDefaultAuth.currentUser == null) {
      final silent = await ExpressLoginService.tryGoogleSilentOnly();
      if (silent != null) return silent;
    } else if (forcePicker) {
      // SÃ³ apÃ³s Â«Trocar contaÂ»: limpa sessÃ£o local para o Play Services abrir o seletor.
      await appGoogleSignOutForAccountPicker();
    }

    GoogleSignInAccount? googleUser;
    try {
      googleUser = await appGoogleSignInInteractive();
    } on GoogleSignInException catch (e) {
      if (isGoogleSignInUserCancellationException(e)) {
        throw FirebaseAuthException(
          code: 'cancelled',
          message: 'Login Google cancelado.',
        );
      }
      rethrow;
    }
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Login Google cancelado.',
      );
    }
    return firebaseCredentialFromGoogleAccount(googleUser);
  }

  static String _randomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// SHA256 em hex minÃºsculo (exigÃªncia Apple + Firebase `nonce`).
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// SÃ³ **iPhone/iPad** (nÃ£o Android/macOS/web). Em outros ambientes retorna null.
  static Future<UserCredential?> signInWithAppleIfAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    if (!await SignInWithApple.isAvailable()) {
      return null;
    }
    final rawNonce = _randomNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Apple nÃ£o retornou token. Tente de novo.',
      );
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    return firebaseDefaultAuth.signInWithCredential(oauthCredential);
  }
}

