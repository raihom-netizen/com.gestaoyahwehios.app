import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();

  bool _loading = false;
  String? _msg;
  bool _ok = false;

  String? get _mode => Uri.base.queryParameters['mode'];
  String? get _oobCode => Uri.base.queryParameters['oobCode'];

  Future<void> _salvar() async {
    setState(() {
      _msg = null;
      _ok = false;
    });

    final mode = _mode;
    final code = _oobCode;

    if (mode != 'resetPassword' || code == null || code.isEmpty) {
      setState(() => _msg = 'Link inválido ou expirado. Gere um novo reset.');
      return;
    }

    final p1 = _p1.text.trim();
    final p2 = _p2.text.trim();

    if (p1.length < 6) {
      setState(() => _msg = 'A senha deve ter no mínimo 6 caracteres.');
      return;
    }
    if (p1 != p2) {
      setState(() => _msg = 'As senhas não conferem.');
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: code,
        newPassword: p1,
      );
      setState(() {
        _ok = true;
        _msg = 'Senha alterada com sucesso! Você já pode entrar.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _msg = e.message ?? 'Erro ao redefinir senha.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestão YAHWEH',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Redefinir senha',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 18),

                    TextField(
                      controller: _p1,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nova senha',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _p2,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar nova senha',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_msg != null)
                      Text(
                        _msg!,
                        style: TextStyle(
                          color: _ok ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _salvar,
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Salvar'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false),
                          child: const Text('Login'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
