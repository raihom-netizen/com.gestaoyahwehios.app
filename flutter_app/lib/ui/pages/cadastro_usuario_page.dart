import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
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
      final msg = googleAuthErrorMessagePt(e);
      if (msg == null) {
        setState(() => _loading = false);
        return;
      }
      final isDomainError =
          msg.toLowerCase().contains('domínio') &&
              msg.toLowerCase().contains('autorizado');
      setState(() {
        _loading = false;
        _error = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          isDomainError
              ? 'Adicione este domínio em Firebase Console → Authentication → Authorized domains.'
              : msg,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is PlatformException && isGoogleSignInUserCancellation(e)) {
        setState(() => _loading = false);
        return;
      }
      final s = e.toString();
      final lower = s.toLowerCase();
      final isDomainError =
          lower.contains('domain') && lower.contains('authorized');
      final msg = isDomainError
          ? 'Este domínio não está autorizado para login Google. '
              'Em Firebase Console → Authentication → Settings, adicione em «Authorized domains».'
          : s;
      setState(() {
        _loading = false;
        _error = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          isDomainError
              ? 'Adicione este domínio em Firebase Console → Authentication → Authorized domains.'
              : msg,
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
                  Material(
                    color: Colors.white,
                    elevation: 2,
                    shadowColor: Colors.black.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _loading ? null : _signInWithGoogle,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          border: Border.all(color: const Color(0xFFDADCE0)),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: ThemeCleanPremium.minTouchTarget,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_loading)
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: ThemeCleanPremium.primary,
                                    ),
                                  )
                                else
                                  const FaIcon(
                                    FontAwesomeIcons.google,
                                    size: 22,
                                    color: Color(0xFF4285F4),
                                  ),
                                const SizedBox(width: 12),
                                Text(
                                  _loading
                                      ? 'A ligar ao Google…'
                                      : 'Entrar com Google',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5,
                                    color: const Color(0xFF3C4043),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
