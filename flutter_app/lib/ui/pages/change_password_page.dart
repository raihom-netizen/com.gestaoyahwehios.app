import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePasswordPage extends StatefulWidget {
  final String tenantId; // igrejaId (mantido para compatibilidade)
  final String cpf;
  final bool force; // true = obrigatório antes de entrar no sistema

  const ChangePasswordPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.force,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _change() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();

    if (user == null || email == null || email.isEmpty) {
      _snack('Sessão inválida. Faça login novamente.');
      return;
    }

    final current = _currentCtrl.text;
    final newPass = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (newPass.length < 6) {
      _snack('Nova senha deve ter pelo menos 6 caracteres.');
      return;
    }
    if (newPass != confirm) {
      _snack('Confirmação não confere.');
      return;
    }

    setState(() => _loading = true);
    try {
      // Reautentica (necessário para updatePassword)
      final cred = EmailAuthProvider.credential(email: email, password: current);
      await user.reauthenticateWithCredential(cred);

      await user.updatePassword(newPass);

      // Marca MUST_CHANGE_PASS = false
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'mustChangePass': false,
      });

      if (!mounted) return;

      _snack('Senha atualizada com sucesso.');
      if (widget.force) {
        Navigator.pushReplacementNamed(context, '/app');
      } else {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _snack('Erro (Auth): ${e.code}');
    } on FirebaseException catch (e) {
      _snack('Erro (Firestore): ${e.code}');
    } catch (e) {
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trocar senha'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CPF: ${widget.cpf}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text(
                  'Por segurança, defina uma nova senha para continuar.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _currentCtrl,
                  obscureText: _obscure1,
                  decoration: InputDecoration(
                    labelText: 'Senha atual',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newCtrl,
                  obscureText: _obscure2,
                  decoration: InputDecoration(
                    labelText: 'Nova senha',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscure3,
                  decoration: InputDecoration(
                    labelText: 'Confirmar nova senha',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure3 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure3 = !_obscure3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _change,
                    child: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Salvar nova senha'),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
