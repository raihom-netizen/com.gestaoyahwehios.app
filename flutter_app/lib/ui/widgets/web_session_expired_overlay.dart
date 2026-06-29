import 'package:flutter/material.dart';

/// Legado — overlay «Sessão expirada» removido (sessão persistente até «Trocar de conta»).
class WebSessionExpiredOverlay extends StatelessWidget {
  const WebSessionExpiredOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
