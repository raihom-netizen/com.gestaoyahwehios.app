import 'package:flutter/material.dart';
import 'package:gestao_yahweh/models/plan.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/onboarding_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:google_fonts/google_fonts.dart';

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
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      if (_nome.text.trim().isEmpty) throw Exception('Informe seu nome.');
      if (_cpf.text.trim().replaceAll(RegExp(r'[^0-9]'), '').length != 11) {
        throw Exception('CPF inválido (11 números).');
      }
      if (_email.text.trim().isEmpty) throw Exception('Informe seu e-mail.');
      if (_senha.text.length < 6) {
        throw Exception('Senha mínima: 6 caracteres.');
      }
      if (_igrejaNome.text.trim().isEmpty) {
        throw Exception('Informe o nome da igreja.');
      }

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
        const SnackBar(
          content: Text('Cadastro criado! Faça login com CPF e senha.'),
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/igreja/login',
        (r) => false,
      );
    } catch (e) {
      setState(
        () => _err = e.toString().replaceAll('Exception:', '').trim(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideOrganizationSignup) {
      return const IosOrganizationSignupWebPage();
    }

    final p = widget.selectedPlan;
    final price = _money(p.monthlyPrice);

    return ChurchWisdomLoginBackdrop(
      appBar: ChurchWisdomLoginAppBar(
        onBack: () => Navigator.of(context).pop(),
      ),
      child: SafeArea(
        child: ChurchWisdomAuthCenter(
          maxWidth: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YahwehSaasVisualShell.surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChurchWisdomCardBrandHeader(
                      title: 'Criar 1º gestor — teste grátis 30 dias',
                      subtitle:
                          'Plano ${p.name} • até ${p.maxMembers} membros • $price/mês',
                      logo: YahwehSaasVisualShell.brandEmblem(size: 64),
                    ),
                    if (_err != null) ...[
                      Text(
                        _err!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Seus dados',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nome,
                      textInputAction: TextInputAction.next,
                      decoration: authCompactFieldDecoration(
                        labelText: 'Seu nome',
                        prefixIcon: const Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _cpf,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.number,
                      decoration: authCompactFieldDecoration(
                        labelText: 'CPF (login)',
                        prefixIcon: const Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _email,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      decoration: authCompactFieldDecoration(
                        labelText: 'E-mail',
                        prefixIcon: const Icon(Icons.email_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _senha,
                      textInputAction: TextInputAction.next,
                      obscureText: true,
                      decoration: authCompactFieldDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Dados da igreja',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _igrejaNome,
                      textInputAction: TextInputAction.next,
                      decoration: authCompactFieldDecoration(
                        labelText: 'Nome da igreja',
                        prefixIcon: const Icon(Icons.church_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _igrejaDoc,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: authCompactFieldDecoration(
                        labelText: 'CNPJ/CPF da igreja (opcional)',
                        prefixIcon: const Icon(Icons.description_rounded),
                      ),
                    ),
                    const SizedBox(height: 18),
                    YahwehSaasVisualShell.primaryButton(
                      label: 'Criar e iniciar trial',
                      icon: Icons.rocket_launch_rounded,
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Depois é só entrar com CPF e senha.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    YahwehSaasVisualShell.securityFooter(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
