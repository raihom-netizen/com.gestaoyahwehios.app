import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/biometric_service.dart';

/// Bloqueio opcional após login: Face ID / digital. Não encerra a sessão Firebase ao falhar —
/// o utilizador pode confirmar a **senha da conta** (e-mail+senha) ou tentar biometria de novo.
/// Conta só Google/Apple: orienta Configurações → Trocar de conta (sem `signOut` automático aqui).
class BiometricLockPage extends StatefulWidget {
  final Widget child;
  const BiometricLockPage({super.key, required this.child});

  @override
  State<BiometricLockPage> createState() => _BiometricLockPageState();
}

class _BiometricLockPageState extends State<BiometricLockPage> {
  bool _unlocking = true;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _tryUnlock();
  }

  Future<void> _tryUnlock() async {
    setState(() => _unlocking = true);
    final ok = await BiometricService().authenticate();
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _unlocked = ok;
    });
  }

  bool _userHasPasswordProvider(User user) {
    for (final p in user.providerData) {
      if (p.providerId == EmailAuthProvider.PROVIDER_ID) return true;
    }
    return false;
  }

  Future<void> _unlockWithAccountPassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    if (!_userHasPasswordProvider(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta sessão entrou com Google ou Apple. Use «Tentar de novo» com biometria ou, '
            'em Configurações, toque em «Trocar de conta» para entrar com outro e-mail.',
          ),
        ),
      );
      return;
    }
    final email = (user.email ?? '').trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar o e-mail da conta.'),
        ),
      );
      return;
    }
    final pwdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar senha'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Digite a senha da conta $email para abrir o painel sem usar a biometria agora.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    final pwd = pwdCtrl.text.trim();
    pwdCtrl.dispose();
    if (ok != true || pwd.isEmpty || !mounted) return;

    setState(() => _unlocking = true);
    try {
      final cred = EmailAuthProvider.credential(email: email, password: pwd);
      await user.reauthenticateWithCredential(cred);
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _unlocked = true;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _unlocking = false);
      final code = e.code.toLowerCase();
      final msg = (code == 'wrong-password' || code == 'invalid-credential')
          ? 'Senha incorreta.'
          : 'Não foi possível confirmar: ${e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _unlocking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Desbloqueie com biometria',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _unlocking
                        ? 'Aguardando sua digital ou Face ID…'
                        : 'Não foi possível autenticar. Toque em «Tentar de novo», confirme a senha da conta ou use Configurações → Trocar de conta para sair.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _unlocking ? null : _tryUnlock,
                          child: const Text('Tentar de novo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _unlocking ? null : _unlockWithAccountPassword,
                          child: const Text('Usar senha'),
                        ),
                      ),
                    ],
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
