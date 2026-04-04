import 'package:flutter/material.dart';
import '../../../services/auth_cpf_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _cpf = TextEditingController();
  final _senha = TextEditingController();
  bool _loading = false;
  String? _err;

  @override
  void dispose() {
    _cpf.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _err = null; });
    try {
      await AuthCpfService().signInByCpf(cpf: _cpf.text, senha: _senha.text);
    } catch (e) {
      setState(() => _err = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final cpf = _cpf.text.trim();
    if (cpf.isEmpty) {
      setState(() => _err = 'Digite seu CPF ou e-mail para recuperar a senha.');
      return;
    }
    setState(() { _loading = true; _err = null; });
    try {
      await AuthCpfService().sendPasswordResetByCpf(cpf);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enviamos um link de recuperação para o e-mail cadastrado.')),
      );
    } catch (e) {
      setState(() => _err = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withOpacity(0.10),
                    const Color(0xFFF6F8FC),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: AppShell(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.lock_open, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('Acessar Gestão YAHWEH',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 18),

                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_err!, style: const TextStyle(color: Colors.red)),
                    ),

                  SectionCard(
                    child: Column(
                      children: [
                        TextField(
                          controller: _cpf,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'CPF ou e-mail',
                            hintText: '11 dígitos ou seu@email.com',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _senha,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        const SizedBox(height: 14),
                        PrimaryButton(
                          text: 'Entrar',
                          icon: Icons.login,
                          loading: _loading,
                          onPressed: _login,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading ? null : _forgot,
                          child: const Text('Esqueci minha senha'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
