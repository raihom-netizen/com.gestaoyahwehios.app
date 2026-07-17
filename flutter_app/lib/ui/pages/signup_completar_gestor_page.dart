import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctions, FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_login_ui.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:google_fonts/google_fonts.dart';

/// Após login (Google/Apple/e-mail): 1) nome + CPF como futuro gestor; 2) dados mínimos da igreja.
/// O cadastro completo (endereço, logo, site público) fica no painel em **Cadastro da Igreja**.
class SignupCompletarGestorPage extends StatefulWidget {
  const SignupCompletarGestorPage({super.key});

  @override
  State<SignupCompletarGestorPage> createState() =>
      _SignupCompletarGestorPageState();
}

enum _OnboardingStep { perfil, igreja }

class _SignupCompletarGestorPageState extends State<SignupCompletarGestorPage> {
  final _formKey = GlobalKey<FormState>();
  final _igrejaNome = TextEditingController();
  final _igrejaDoc = TextEditingController();
  final _nome = TextEditingController();
  final _cpf = TextEditingController();

  bool _loading = false;
  String? _error;
  _OnboardingStep _step = _OnboardingStep.perfil;
  bool _resolvedStep = false;

  FirebaseFunctions get _fnUsCentral1 =>
      FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'us-central1',
      );

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _nome.text.trim().isEmpty) {
      _nome.text = user.displayName ?? '';
      _nome.selection = TextSelection.collapsed(offset: _nome.text.length);
    }
    _maybeSkipToIgrejaStep();
  }

  Future<void> _maybeSkipToIgrejaStep() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc =
          await firebaseDefaultFirestore.collection('users').doc(user.uid).get();
      final d = doc.data();
      if (d == null) {
        if (mounted) setState(() => _resolvedStep = true);
        return;
      }
      final prevIgreja = (d['igrejaId'] ?? d['tenantId'] ?? '').toString().trim();
      if (prevIgreja.isNotEmpty) {
        if (mounted) setState(() => _resolvedStep = true);
        return;
      }
      final nome = (d['nome'] ?? d['name'] ?? '').toString().trim();
      final cpf = _normalizeCpf((d['cpf'] ?? '').toString());
      if (nome.isNotEmpty && cpf.length == 11 && mounted) {
        setState(() {
          _nome.text = nome;
          _cpf.text = cpf;
          _step = _OnboardingStep.igreja;
          _resolvedStep = true;
        });
      } else if (mounted) {
        setState(() => _resolvedStep = true);
      }
    } catch (_) {
      if (mounted) setState(() => _resolvedStep = true);
    }
  }

  @override
  void dispose() {
    _igrejaNome.dispose();
    _igrejaDoc.dispose();
    _nome.dispose();
    _cpf.dispose();
    super.dispose();
  }

  String? _req(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  String _normalizeCpf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  String _callableErrorText(FirebaseFunctionsException e) {
    var msg = (e.message ?? e.code).trim();
    final low = msg.toLowerCase();
    if ((low == 'internal' || low == 'internal error') && e.details != null) {
      final d = e.details;
      if (d is String && d.trim().isNotEmpty) return d.trim();
      if (d is Map && d['message'] != null) {
        return d['message'].toString().trim();
      }
    }
    if (msg.isEmpty) return e.code;
    return msg;
  }

  Future<void> _submitPerfil() async {
    if (!_formKey.currentState!.validate()) return;
    final cpf = _normalizeCpf(_cpf.text);
    if (cpf.length != 11) {
      setState(() => _error = 'CPF deve ter 11 dígitos.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fn = _fnUsCentral1.httpsCallable('registerGestorProfile');
      await fn.call({
        'nome': _nome.text.trim(),
        'cpf': cpf,
      });

      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _OnboardingStep.igreja;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil salvo. Agora informe os dados da igreja.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final userMsg = _callableErrorText(e);
      setState(() {
        _loading = false;
        _error = userMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $userMsg')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    }
  }

  Future<void> _submitIgreja() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fn = _fnUsCentral1.httpsCallable('createChurchForOnboardingGestor');
      final res = await fn.call({
        'igrejaNome': _igrejaNome.text.trim(),
        'igrejaDoc': _igrejaDoc.text.trim().isEmpty ? null : _igrejaDoc.text.trim(),
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final igrejaSlug = (data['igrejaSlug'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Igreja criada! 30 dias de teste grátis${igrejaSlug.isNotEmpty ? '. Site: /igreja/$igrejaSlug' : ''}. Complete endereço e logo no painel.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final userMsg = _callableErrorText(e);
      setState(() {
        _loading = false;
        _error = userMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $userMsg')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideOrganizationSignup) {
      return const IosOrganizationSignupWebPage();
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Faça login primeiro (Google ou e-mail).'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(context, '/signup', (_) => false),
                child: const Text('Ir para cadastro'),
              ),
            ],
          ),
        ),
      );
    }

    final isPerfil = _step == _OnboardingStep.perfil;

    return ChurchWisdomLoginBackdrop(
      appBar: ChurchWisdomLoginAppBar(
        onBack: isPerfil
            ? () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/signup',
                    (_) => false,
                  );
                }
              }
            : () {
                if (_loading) return;
                setState(() {
                  _step = _OnboardingStep.perfil;
                  _error = null;
                });
              },
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => FirebaseAuth.instance.signOut().then((_) {
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/signup',
                        (_) => false,
                      );
                    }),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      child: SafeArea(
        child: !_resolvedStep
            ? const Center(child: CircularProgressIndicator())
            : ChurchWisdomAuthCenter(
                maxWidth: 460,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ChurchWisdomLoginFormCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ChurchWisdomCardBrandHeader(
                              title: isPerfil
                                  ? 'Seu perfil (gestor)'
                                  : 'Dados da igreja',
                              subtitle: isPerfil
                                  ? 'Nome e CPF — depois os dados da igreja.'
                                  : 'Só o essencial — o resto você completa no painel.',
                              logo:
                                  YahwehSaasVisualShell.brandEmblem(size: 64),
                            ),
                            Row(
                              children: [
                                SafeCircleAvatarImage(
                                  imageUrl: user.photoURL,
                                  radius: 20,
                                  fallbackIcon: Icons.person_rounded,
                                  backgroundColor: Colors.grey.shade200,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.displayName ??
                                            user.email ??
                                            'Sua conta',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        user.email ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (isPerfil) ...[
                              TextFormField(
                                controller: _nome,
                                decoration: authCompactFieldDecoration(
                                  labelText: 'Seu nome completo',
                                ),
                                validator: (v) => _req(v, 'Informe seu nome'),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _cpf,
                                keyboardType: TextInputType.number,
                                decoration: authCompactFieldDecoration(
                                  labelText: 'Seu CPF (11 dígitos)',
                                  hintText: 'Apenas números',
                                ),
                                validator: (v) {
                                  final msg = _req(v, 'Informe seu CPF');
                                  if (msg != null) return msg;
                                  if (_normalizeCpf(v ?? '').length != 11) {
                                    return 'CPF deve ter 11 dígitos';
                                  }
                                  return null;
                                },
                              ),
                            ] else ...[
                              TextFormField(
                                controller: _igrejaNome,
                                decoration: authCompactFieldDecoration(
                                  labelText: 'Nome da igreja',
                                  hintText: 'Ex.: Igreja Batista Central',
                                ),
                                validator: (v) =>
                                    _req(v, 'Informe o nome da igreja'),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _igrejaDoc,
                                decoration: authCompactFieldDecoration(
                                  labelText: 'CNPJ ou CPF da igreja (opcional)',
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: _loading
                                    ? null
                                    : (isPerfil
                                        ? _submitPerfil
                                        : _submitIgreja),
                                icon: _loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        isPerfil
                                            ? Icons.arrow_forward_rounded
                                            : Icons.check_circle_outline,
                                        size: 20,
                                      ),
                                label: Text(
                                  _loading
                                      ? 'Aguarde...'
                                      : (isPerfil
                                          ? 'Continuar'
                                          : 'Criar igreja e abrir painel'),
                                  style: const TextStyle(fontSize: 14),
                                ),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const ChurchWisdomLoginScriptureFooter(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
