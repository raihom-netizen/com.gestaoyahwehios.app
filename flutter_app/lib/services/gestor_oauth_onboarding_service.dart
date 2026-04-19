import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/gestor_membro_stub_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Login social no onboarding: painel se já tem igreja; senão `/signup/completar-dados` (perfil + igreja).
class GestorOAuthOnboardingService {
  GestorOAuthOnboardingService._();

  static Future<void> routeAfterOAuthSignIn(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta já vinculada. Redirecionando ao painel.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } else {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/signup/completar-dados',
        (_) => false,
      );
    }
  }

  static Future<UserCredential> signInWithGoogleNative() async {
    if (kIsWeb) {
      throw StateError('Use signInWithPopup na web.');
    }
    try {
      await appGoogleSignIn().signOut();
    } catch (_) {}
    final googleUser = await appGoogleSignIn().signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Login Google cancelado.',
      );
    }
    final ga = await googleUser.authentication;
    final idTok = ga.idToken;
    if (idTok == null || idTok.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message:
            'Google não retornou token de identificação. Tente de novo ou use outro método de login.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      accessToken: ga.accessToken,
      idToken: idTok,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
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

  /// SHA256 em hex minúsculo (exigência Apple + Firebase `nonce`).
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Só **iPhone/iPad** (não Android/macOS/web). Em outros ambientes retorna null.
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
        message: 'Apple não retornou token. Tente de novo.',
      );
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );
    return FirebaseAuth.instance.signInWithCredential(oauthCredential);
  }
}
