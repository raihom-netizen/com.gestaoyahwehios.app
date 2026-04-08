import 'package:flutter/material.dart';
import '../login_page.dart';

/// Rota de login (alias para LoginPage). [prefillEmail] via `/login?email=`.
class LoginPageNovo extends StatelessWidget {
  final String? prefillEmail;

  const LoginPageNovo({super.key, this.prefillEmail});

  @override
  Widget build(BuildContext context) {
    return LoginPage(
      title: 'Entrar',
      afterLoginRoute: '/painel',
      prefillEmail: prefillEmail,
      backRoute: '/',
    );
  }
}
