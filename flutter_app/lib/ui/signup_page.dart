import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

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

  String _planId = planosOficiais.isNotEmpty ? planosOficiais.first.id : 'essencial';
  bool _loading = false;
  bool _obscure = true;
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;

  @override
  void initState() {
    super.initState();
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

  String? _req(String? v, String msg) => (v == null || v.trim().isEmpty) ? msg : null;

  Future<void> _cadastroRapidoGoogle() async {
    if (!kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastro rápido com Google disponível na versão web.')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      final user = cred.user;
      if (user == null || !mounted) return;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data();
      final igrejaId = (data?['igrejaId'] ?? data?['tenantId'] ?? '').toString().trim();

      if (mounted) {
        if (igrejaId.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conta já vinculada. Redirecionando ao painel.'), backgroundColor: Colors.green),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/painel', (_) => false);
        } else {
          Navigator.pushNamedAndRemoveUntil(context, '/signup/completar-dados', (_) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      final isDomain = msg.toString().toLowerCase().contains('domain') || msg.toString().toLowerCase().contains('authorized');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDomain
              ? 'Adicione este domínio em Firebase Console > Authentication > Authorized domains.'
              : 'Falha no login: $msg'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('createChurchAndGestorWithPlan');
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

      // ✅ Redirecionar automaticamente para o site da igreja recém-criada
      // (mantém o usuário na experiência da igreja e deixa o botão de login visível lá)
      final target = igrejaSlug.isNotEmpty ? '/igreja/$igrejaSlug' : '/igreja/login';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar conta - teste grátis 30 dias'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
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
                    'Antes de usar, crie sua conta de gestor. Você terá 30 dias completos para testar.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  if (kIsWeb)
                    FilledButton.icon(
                      onPressed: _loading ? null : _cadastroRapidoGoogle,
                      icon: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.g_mobiledata_rounded, size: 26),
                      label: const Text('Cadastro rápido com Google'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (kIsWeb) const SizedBox(height: 16),
                  if (kIsWeb)
                    const Center(
                      child: Text('Depois informe os dados da igreja e seus dados pessoais.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    ),
                  if (kIsWeb) const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text('Dados da igreja', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  const Text('Dados do gestor', style: TextStyle(fontWeight: FontWeight.w800)),
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
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
                  const Text('Plano para iniciar', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    value: planosOficiais.any((p) => p.id == _planId) ? _planId : (planosOficiais.isNotEmpty ? planosOficiais.first.id : null),
                    decoration: const InputDecoration(
                      labelText: 'Selecione o plano',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: planosOficiais.map((p) {
                      final monthly = _effectivePrices?[p.id]?.monthly ?? p.monthlyPrice;
                      final price = monthly != null
                          ? 'R\$ ${monthly.toStringAsFixed(2).replaceFirst('.', ',')}/mês'
                          : (p.note ?? 'Sob consulta');
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text('${p.name.replaceFirst('Plano ', '')} ($price)'),
                      );
                    }).toList(),
                    onChanged: _loading ? null : (v) => setState(() => _planId = v ?? (planosOficiais.isNotEmpty ? planosOficiais.first.id : 'essencial')),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(Icons.check_circle),
                      label: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Criar conta e iniciar teste'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.pushReplacementNamed(context, '/igreja/login'),
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
