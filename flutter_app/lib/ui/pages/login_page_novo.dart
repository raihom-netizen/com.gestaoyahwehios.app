import 'package:flutter/material.dart';
import '../login_page.dart';

/// Rota de login (alias para LoginPage).
class LoginPageNovo extends StatelessWidget {
  const LoginPageNovo({super.key});
  @override
  Widget build(BuildContext context) {
    return const LoginPage(
      title: 'Entrar',
      afterLoginRoute: '/painel',
      showGoogleLogin: true,
    );
  }
}
