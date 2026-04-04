import 'package:flutter/material.dart';
import '../../../models/plan.dart';
import '../../../services/onboarding_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';

class SignupGestorPage extends StatefulWidget {
  final Plan selectedPlan;
  const SignupGestorPage({super.key, required this.selectedPlan});

  @override
  State<SignupGestorPage> createState() => _SignupGestorPageState();
}

class _SignupGestorPageState extends State<SignupGestorPage> {
  final _nome = TextEditingController();
  final _cpf = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _igrejaNome = TextEditingController();
  final _igrejaDoc = TextEditingController();

  bool _loading = false;
  String? _err;

  @override
  void dispose() {
    _nome.dispose();
    _cpf.dispose();
    _email.dispose();
    _senha.dispose();
    _igrejaNome.dispose();
    _igrejaDoc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _err = null; });
    try {
      if (_nome.text.trim().isEmpty) throw Exception('Informe seu nome.');
      if (_cpf.text.trim().replaceAll(RegExp(r'[^0-9]'), '').length != 11) {
        throw Exception('CPF inválido (11 números).');
      }
      if (_email.text.trim().isEmpty) throw Exception('Informe seu e-mail.');
      if (_senha.text.length < 6) throw Exception('Senha mínima: 6 caracteres.');
      if (_igrejaNome.text.trim().isEmpty) throw Exception('Informe o nome da igreja.');

      await OnboardingService().createGestorWithTrial(
        nome: _nome.text.trim(),
        cpf: _cpf.text.trim(),
        email: _email.text.trim(),
        senha: _senha.text,
        igrejaNome: _igrejaNome.text.trim(),
        igrejaDoc: _igrejaDoc.text.trim(),
        planId: widget.selectedPlan.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro criado! Faça login com CPF e senha.')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _err = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.selectedPlan;
    final price = p.monthlyPrice.toStringAsFixed(2).replaceAll('.', ',');

    return Scaffold(
      appBar: AppBar(title: const Text('Criar 1º Gestor')),
      body: AppShell(
        child: ListView(
          children: [
            const SizedBox(height: 8),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Você está a 1 passo de começar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Plano selecionado: ${p.name} • até ${p.maxMembers} membros • R\$ $price/mês',
                      style: const TextStyle(color: Color(0xFF5E6B85))),
                  const SizedBox(height: 10),
                  const Text('Ao concluir, o sistema cria sua igreja, o usuário gestor e uma assinatura TRIAL de 30 dias.',
                      style: TextStyle(height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_err!, style: const TextStyle(color: Colors.red)),
              ),

            SectionCard(
              child: Column(
                children: [
                  TextField(
                    controller: _nome,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Seu nome', prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cpf,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CPF (login)', prefixIcon: Icon(Icons.badge)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _email,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _senha,
                    textInputAction: TextInputAction.next,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SectionCard(
              child: Column(
                children: [
                  TextField(
                    controller: _igrejaNome,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nome da igreja', prefixIcon: Icon(Icons.church)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _igrejaDoc,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'CNPJ/CPF da igreja (opcional)',
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            PrimaryButton(
              text: 'Criar e iniciar trial',
              icon: Icons.rocket_launch,
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            const Text(
              'Após criar, faça login usando CPF e senha. Se esquecer a senha, você recupera informando o CPF.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5E6B85), height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
