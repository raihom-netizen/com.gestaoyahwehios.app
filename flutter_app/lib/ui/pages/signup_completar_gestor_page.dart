import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctions, FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

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
      FirebaseFunctions.instanceFor(region: 'us-central1');

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
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

    return Scaffold(
      appBar: AppBar(
        leading: isPerfil
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _step = _OnboardingStep.perfil;
                          _error = null;
                        }),
              ),
        title: Text(isPerfil ? 'Seu perfil (gestor)' : 'Dados da igreja'),
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => FirebaseAuth.instance.signOut().then((_) {
                      if (!context.mounted) return;
                      Navigator.pushNamedAndRemoveUntil(context, '/signup', (_) => false);
                    }),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: !_resolvedStep
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SafeCircleAvatarImage(
                                      imageUrl: user.photoURL,
                                      radius: 24,
                                      fallbackIcon: Icons.person_rounded,
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.displayName ??
                                                user.email ??
                                                'Sua conta',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16),
                                          ),
                                          Text(
                                            user.email ?? '',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  isPerfil
                                      ? 'Primeiro cadastre-se como gestor (nome e CPF). Depois você informa só os dados da igreja — endereço, logo e link do site público você completa no painel.'
                                      : 'Informe o nome da igreja e, se quiser, o CNPJ ou CPF da instituição. Se for MEI com seu CPF, pode ser o mesmo do seu cadastro pessoal.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (isPerfil) ...[
                          const Text('Seus dados',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _nome,
                            decoration: const InputDecoration(
                              labelText: 'Seu nome completo',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => _req(v, 'Informe seu nome'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cpf,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seu CPF (11 dígitos)',
                              border: OutlineInputBorder(),
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
                          const Text('Igreja',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _igrejaNome,
                            decoration: const InputDecoration(
                              labelText: 'Nome da igreja',
                              border: OutlineInputBorder(),
                              hintText: 'Ex.: Igreja Batista Central',
                            ),
                            validator: (v) => _req(v, 'Informe o nome da igreja'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _igrejaDoc,
                            decoration: const InputDecoration(
                              labelText: 'CNPJ ou CPF da igreja (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: _loading
                                ? null
                                : (isPerfil ? _submitPerfil : _submitIgreja),
                            icon: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isPerfil
                                        ? Icons.arrow_forward_rounded
                                        : Icons.check_circle_outline),
                            label: Text(
                              _loading
                                  ? 'Aguarde...'
                                  : (isPerfil
                                      ? 'Continuar para dados da igreja'
                                      : 'Criar igreja e abrir painel (30 dias grátis)'),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              textStyle: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
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
