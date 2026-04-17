import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/ui/widgets/version_footer.dart';

class CadastroUsuarioPage extends StatefulWidget {
  const CadastroUsuarioPage({super.key});

  @override
  State<CadastroUsuarioPage> createState() => _CadastroUsuarioPageState();
}

class _CadastroUsuarioPageState extends State<CadastroUsuarioPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    if (!kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login com Google disponível na versão web.')),
        );
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance
          .signInWithPopup(firebaseWebGoogleAuthProvider());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Acesso rápido ativado. O gestor da igreja pode solicitar mais dados (CPF/CNPJ) depois.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushReplacementNamed('/painel');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      final isDomainError = msg.toString().toLowerCase().contains('domain') && msg.toString().toLowerCase().contains('authorized');
      setState(() {
        _loading = false;
        _error = isDomainError
            ? 'Domínio não autorizado no Firebase. Adicione este domínio em Firebase Console > Authentication > Authorized domains (ex.: gestaoyahweh.com.br).'
            : msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDomainError ? 'Login Google: adicione este domínio em Firebase Console > Authentication > Authorized domains.' : 'Falha no login: $msg'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final isDomainError = s.toLowerCase().contains('domain') && s.toLowerCase().contains('authorized');
      setState(() {
        _loading = false;
        _error = isDomainError
            ? 'Domínio não autorizado. Firebase Console > Authentication > Authorized domains (ex.: gestaoyahweh.com.br).'
            : s;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDomainError ? 'Adicione este domínio em Firebase Console > Authentication > Authorized domains.' : 'Erro: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cadastro de usuário',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Acesso rápido com Google ou preencha os dados abaixo. O gestor da igreja pode solicitar CPF/CNPJ depois.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                if (kIsWeb)
                  FilledButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: Text(_loading ? 'Entrando...' : 'Entrar com Google'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (kIsWeb) const SizedBox(height: 16),
                if (kIsWeb && (_error != null && _error!.isNotEmpty)) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade800,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Ou preencha o formulário de cadastro (em breve mais opções).',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Voltar ao início'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 32),
                const VersionFooter(showVersion: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
