import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctions, FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
/// Página para completar cadastro do gestor após login com Google ou Apple.
/// Dados da igreja + dados pessoais → trial 30 dias, acesso total.
class SignupCompletarGestorPage extends StatefulWidget {
  const SignupCompletarGestorPage({super.key});

  @override
  State<SignupCompletarGestorPage> createState() => _SignupCompletarGestorPageState();
}

class _SignupCompletarGestorPageState extends State<SignupCompletarGestorPage> {
  final _formKey = GlobalKey<FormState>();
  final _igrejaNome = TextEditingController();
  final _igrejaDoc = TextEditingController();
  final _nome = TextEditingController();
  final _cpf = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && (_nome.text.trim().isEmpty)) {
      _nome.text = user.displayName ?? '';
      _nome.selection = TextSelection.collapsed(offset: _nome.text.length);
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

  String? _req(String? v, String msg) => (v == null || v.trim().isEmpty) ? msg : null;

  String _normalizeCpf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _submit() async {
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
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createChurchAndGestorWithGoogle');
      final res = await fn.call({
        'igrejaNome': _igrejaNome.text.trim(),
        'igrejaDoc': _igrejaDoc.text.trim().isEmpty ? null : _igrejaDoc.text.trim(),
        'nome': _nome.text.trim(),
        'cpf': cpf,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      final igrejaSlug = (data['igrejaSlug'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conta ativada! 30 dias de teste grátis. Acesso total ao sistema${igrejaSlug.isNotEmpty ? '. Sua igreja: /igreja/$igrejaSlug' : ''}.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? e.code;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: ${e.message ?? e.code}')),
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
              const Text('Faça login com Google primeiro.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/signup', (_) => false),
                child: const Text('Ir para cadastro'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar cadastro'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut().then((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/signup', (_) => false);
            }),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName ?? user.email ?? 'Conta Google',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                    Text(
                                      user.email ?? '',
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Agora informe os dados da sua igreja e seus dados pessoais para começar a testar o sistema por 30 dias com acesso total.',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Dados da igreja', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                  const SizedBox(height: 22),
                  const Text('Seus dados (gestor)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                      if (_normalizeCpf(v ?? '').length != 11) return 'CPF deve ter 11 dígitos';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_loading ? 'Criando conta...' : 'Criar igreja e começar teste grátis (30 dias)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
