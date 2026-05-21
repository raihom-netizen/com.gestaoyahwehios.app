import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';

import '../login_page.dart';

/// Rota de login (alias para LoginPage). [prefillEmail] via `/login?email=`.
class LoginPageNovo extends StatelessWidget {
  final String? prefillEmail;

  const LoginPageNovo({super.key, this.prefillEmail});

  @override
  Widget build(BuildContext context) {
    final iosReader = IosPaymentsGate.hideOrganizationSignup;
    return LoginPage(
      title: iosReader ? 'Entrar com conta existente' : 'Entrar',
      afterLoginRoute: '/painel',
      prefillEmail: prefillEmail,
      backRoute: iosReader ? '/igreja/login' : '/',
      showSmartLoginFlow: false,
    );
  }
}
