import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

import 'pwa_install_bridge_stub.dart'
    if (dart.library.html) 'pwa_install_bridge_web.dart';

/// Botão para instalar PWA (web). Em outras plataformas não exibe nada.
class InstallPwaButton extends StatelessWidget {
  final bool expanded;
  const InstallPwaButton({super.key}) : expanded = false;
  const InstallPwaButton.expanded({super.key}) : expanded = true;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final btn = OutlinedButton.icon(
      onPressed: () async {
        final accepted = await promptInstallPwa();
        if (accepted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Instalação iniciada. Confirme no navegador.'),
              ),
            );
          }
          return;
        }
        if (!context.mounted) return;
        final canPrompt = await canInstallPwa();
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Instalar site da igreja'),
            content: Text(
              canPrompt
                  ? 'Toque novamente em "Instalar site da igreja" para abrir o prompt do navegador.'
                  : 'No navegador, abra o menu e escolha "Instalar app" ou "Adicionar à tela inicial".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.install_mobile_rounded, size: 20),
      label: const Text('Instalar site da igreja'),
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeCleanPremium.primary,
        side: BorderSide(color: ThemeCleanPremium.primary, width: 1.6),
        minimumSize: const Size(
            ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
      ),
    );
    if (expanded) return SizedBox(width: double.infinity, child: btn);
    return btn;
  }
}
