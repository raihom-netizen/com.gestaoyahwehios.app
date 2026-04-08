import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/auth_cpf_service.dart';
import 'package:gestao_yahweh/services/gestor_oauth_onboarding_service.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
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

  final _igrejaNome = TextEditingController();
  final _igrejaDoc = TextEditingController();
  final _nome = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();

  String _planId =
      planosOficiais.isNotEmpty ? planosOficiais.first.id : 'essencial';
  bool _loading = false;
  bool _obscure = true;
  bool _appleSignInAvailable = false;
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;

  FirebaseFunctions get _fnUsCentral1 =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

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
    PlanPriceService.getEffectivePrices().then((p) {
      if (mounted) setState(() => _effectivePrices = p);
    });
  }

  @override
  void dispose() {
    _igrejaNome.dispose();
    _igrejaDoc.dispose();
    _nome.dispose();
    _cpf.dispose();
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
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
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
      final fn = _fnUsCentral1.httpsCallable('createChurchAndGestorWithPlan');
      final res = await fn.call({
        'igrejaNome': _igrejaNome.text.trim(),
        'igrejaDoc': _igrejaDoc.text.trim(),
        'nome': _nome.text.trim(),
        'cpf': _cpf.text.trim(),
        'email': _email.text.trim(),
        'senha': _senha.text,
        'planId': _planId,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final igrejaSlug = (data['igrejaSlug'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            igrejaSlug.isNotEmpty
                ? 'Conta criada! Sua igreja: /igreja/$igrejaSlug — Teste grátis até: ${data['trialEndsAt'] ?? ''}'
                : 'Conta criada! Teste grátis até: ${data['trialEndsAt'] ?? ''}',
          ),
        ),
      );

      final target =
          igrejaSlug.isNotEmpty ? '/igreja/$igrejaSlug' : '/igreja/login';
      Navigator.pushNamedAndRemoveUntil(context, target, (_) => false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no cadastro: ${e.message ?? e.code}')),
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
          'Comece rápido com Google ou Apple (app) e depois complete os dados da igreja — ou use o formulário abaixo com e-mail e senha.',
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
              child: Text('ou cadastre com e-mail', style: TextStyle(fontSize: 13, color: Colors.black54)),
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
                    'Crie sua conta de gestor. Você terá 30 dias completos para testar.',
                    style: TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _socialHeader(),
                  const Text('Dados da igreja',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _igrejaNome,
                    decoration: const InputDecoration(
                      labelText: 'Nome da igreja',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _req(v, 'Informe o nome da igreja'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _igrejaDoc,
                    decoration: const InputDecoration(
                      labelText: 'CNPJ ou CPF (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Dados do gestor',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nome,
                    decoration: const InputDecoration(
                      labelText: 'Seu nome (gestor)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _req(v, 'Informe seu nome'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cpf,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'CPF (11 números)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _req(v, 'Informe seu CPF'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail (receberá o link de reset)',
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
                      if ((v ?? '').length < 6) return 'Senha mínima: 6 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text('Plano para iniciar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: planosOficiais.any((p) => p.id == _planId)
                        ? _planId
                        : (planosOficiais.isNotEmpty
                            ? planosOficiais.first.id
                            : null),
                    decoration: const InputDecoration(
                      labelText: 'Selecione o plano',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: planosOficiais.map((p) {
                      final monthly =
                          _effectivePrices?[p.id]?.monthly ?? p.monthlyPrice;
                      final price = monthly != null
                          ? 'R\$ ${monthly.toStringAsFixed(2).replaceFirst('.', ',')}/mês'
                          : (p.note ?? 'Sob consulta');
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(
                            '${p.name.replaceFirst('Plano ', '')} ($price)'),
                      );
                    }).toList(),
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _planId = v ??
                            (planosOficiais.isNotEmpty
                                ? planosOficiais.first.id
                                : 'essencial')),
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
                          : const Text('Criar conta e iniciar teste'),
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
