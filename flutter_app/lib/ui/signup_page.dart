import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:gestao_yahweh/services/auth_cpf_service.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/gestor_oauth_onboarding_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SignupPage extends StatefulWidget {
  /// Pré-preenche e-mail (ex.: deep link `/signup?email=`).
  final String? initialEmail;

  const SignupPage({super.key, this.initialEmail});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _senha = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _appleSignInAvailable = false;

  bool get _showAppleButton => !kIsWeb && _appleSignInAvailable;

  @override
  void initState() {
    super.initState();
    final init = widget.initialEmail?.trim();
    if (init != null && init.isNotEmpty) {
      _email.text = init;
    }
    if (!kIsWeb) {
      SignInWithApple.isAvailable().then((ok) {
        if (mounted) setState(() => _appleSignInAvailable = ok);
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  String? _req(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  Future<void> _cadastroRapidoGoogle() async {
    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance
            .signInWithPopup(firebaseWebGoogleAuthProvider());
      } else {
        await GestorOAuthOnboardingService.signInWithGoogleNative();
      }
      if (!mounted) return;
      await GestorOAuthOnboardingService.routeAfterOAuthSignIn(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      final low = msg.toString().toLowerCase();
      final isDomain =
          low.contains('domain') || low.contains('authorized');
      final isCancel = e.code == 'cancelled' ||
          low.contains('cancel') ||
          low.contains('popup-closed');
      if (isCancel) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDomain
              ? 'Adicione este domínio em Firebase Console > Authentication > Authorized domains.'
              : 'Falha no login Google: $msg'),
          duration: const Duration(seconds: 5),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final isDevErr = isGoogleSignInAndroidConfigError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDevErr
                ? 'Login Google indisponível neste aparelho (assinatura/SHA-1). '
                    'Adicione o SHA-1 do keystore em Firebase Console → Configurações do projeto → App Android, '
                    'ou use e-mail e senha. Depois de alterar o SHA-1, aguarde alguns minutos e tente de novo.'
                : 'Falha no Google: ${e.code} ${e.message ?? ''}',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
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
              content: Text('Entrar com Apple não está disponível neste aparelho.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      await GestorOAuthOnboardingService.routeAfterOAuthSignIn(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro Apple: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _senha.text,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/signup/completar-dados',
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      String msg = e.message ?? e.code;
      if (code == 'email-already-in-use') {
        msg =
            'Este e-mail já está em uso. Use Entrar ou outro endereço.';
      } else if (code == 'weak-password') {
        msg = 'Senha fraca. Use pelo menos 6 caracteres.';
      } else if (code == 'invalid-email') {
        msg = 'E-mail inválido.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no cadastro: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _socialHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Entre com Google ou Apple (app). Depois você informa nome, CPF e os dados da igreja em duas etapas rápidas — ou crie só e-mail e senha abaixo.',
          style: TextStyle(color: Colors.black54, height: 1.35),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _cadastroRapidoGoogle,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.g_mobiledata_rounded, size: 26),
          label: const Text('Continuar com Google'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4285F4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (_showAppleButton) ...[
          const SizedBox(height: 10),
          SignInWithAppleButton(
            onPressed: () {
              if (_loading) return;
              unawaited(_cadastroRapidoApple());
            },
            style: SignInWithAppleButtonStyle.black,
            height: 48,
            text: 'Continuar com Apple',
          ),
        ],
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('ou e-mail e senha',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar conta - teste grátis 30 dias'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
            child: const Text('Home'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const Text(
                    'Abra sua conta em poucos passos. O teste completo (30 dias) começa quando você criar a igreja no sistema.',
                    style: TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _socialHeader(),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _req(v, 'Informe seu e-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _senha,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Senha (mínimo 6)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      final msg = _req(v, 'Informe a senha');
                      if (msg != null) return msg;
                      if ((v ?? '').length < 6) {
                        return 'Senha mínima: 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(Icons.check_circle),
                      label: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Criar conta e continuar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            final e = _email.text.trim();
                            if (AuthCpfService.looksLikeEmail(e)) {
                              Navigator.pushReplacementNamed(
                                context,
                                '/igreja/login?email=${Uri.encodeComponent(e)}',
                              );
                            } else {
                              Navigator.pushReplacementNamed(
                                context,
                                '/igreja/login',
                              );
                            }
                          },
                    child: const Text('Já tenho conta → Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
