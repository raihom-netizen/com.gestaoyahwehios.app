import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/gestor_oauth_onboarding_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SignupPage extends StatefulWidget {
  /// Pré-preenche e-mail (ex.: deep link `/signup?email=`).
  final String? initialEmail;

  const SignupPage({super.key, this.initialEmail});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  bool _loading = false;

  /// Só o botão Google — evita bloquear o ecrã inteiro enquanto o seletor de contas abre.
  bool _googleBusy = false;
  bool _appleSignInAvailable = false;

  bool get _formLocked => _loading || _googleBusy;

  bool get _showAppleButton =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      _appleSignInAvailable;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      SignInWithApple.isAvailable().then((ok) {
        if (mounted) setState(() => _appleSignInAvailable = ok);
      });
    }
  }

  Future<void> _cadastroRapidoGoogle() async {
    if (_formLocked) return;
    setState(() => _googleBusy = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(
          firebaseWebGoogleAuthProvider(forceAccountPicker: true),
        );
      } else {
        await GestorOAuthOnboardingService.signInWithGoogleNative(
          forceAccountPicker: true,
        );
      }
      if (!mounted) return;
      await GestorOAuthOnboardingService.routeAfterOAuthSignIn(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final mapped = googleAuthErrorMessagePt(e);
      if (mapped == null) return;
      final low = mapped.toLowerCase();
      final isDomain = low.contains('domain') || low.contains('authorized');
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          isDomain
              ? 'Adicione este domínio em Firebase Console → Authentication → Authorized domains.'
              : mapped,
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (isGoogleSignInUserCancellation(e)) return;
      final isDevErr = isGoogleSignInAndroidConfigError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          isDevErr
              ? 'Login Google indisponível neste aparelho (SHA-1). '
                    'Verifique o keystore em Firebase Console → App Android ou use e-mail e senha.'
              : 'Falha no Google: ${e.code} ${e.message ?? ''}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(ThemeCleanPremium.feedbackSnackBar('Erro: $e'));
    } finally {
      if (mounted) {
        setState(() {
          _googleBusy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _cadastroRapidoApple() async {
    setState(() => _loading = true);
    try {
      final cred =
          await GestorOAuthOnboardingService.signInWithAppleIfAvailable();
      if (cred == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Entrar com Apple não está disponível neste aparelho.',
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      await GestorOAuthOnboardingService.routeAfterOAuthSignIn(context);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      if (e.code == AuthorizationErrorCode.canceled) return;
      final msg = e.code == AuthorizationErrorCode.unknown
          ? 'Não foi possível usar a Apple neste momento. Tente de novo ou use Google / e-mail e senha.'
          : 'Falha no login com Apple. Tente de novo ou use outro método.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro Apple: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _socialHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _formLocked ? null : _cadastroRapidoGoogle,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(color: const Color(0xFFDADCE0)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_googleBusy)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: ThemeCleanPremium.primary,
                          ),
                        )
                      else
                        const FaIcon(
                          FontAwesomeIcons.google,
                          size: 20,
                          color: Color(0xFF4285F4),
                        ),
                      const SizedBox(width: 10),
                      Text(
                        _googleBusy
                            ? 'Escolha a conta Google…'
                            : 'Continuar com Google',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: -0.2,
                          color: const Color(0xFF3C4043),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showAppleButton) ...[
          const SizedBox(height: 8),
          SignInWithAppleButton(
            onPressed: () {
              if (_formLocked) return;
              unawaited(_cadastroRapidoApple());
            },
            style: SignInWithAppleButtonStyle.black,
            height: 48,
            text: 'Continuar com Apple',
          ),
        ],
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'ou e-mail e senha',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideOrganizationSignup) {
      return const IosOrganizationSignupWebPage();
    }
    return Theme(
      data: ThemeCleanPremium.themeData,
      child: ChurchWisdomLoginBackdrop(
        appBar: ChurchWisdomLoginAppBar(
          onBack: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }
          },
        ),
        child: SafeArea(
          child: ChurchWisdomAuthCenter(
            maxWidth: 460,
            child: Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChurchWisdomLoginFormCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChurchWisdomCardBrandHeader(
                          title: 'Criar conta — teste grátis 30 dias',
                          subtitle:
                              'Entre com Google ou Apple — depois você completa os dados da igreja.',
                          logo: YahwehSaasVisualShell.brandEmblem(size: 72),
                        ),
                        _socialHeader(),
                      ],
                    ),
                  ),
                  const ChurchWisdomLoginScriptureFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
