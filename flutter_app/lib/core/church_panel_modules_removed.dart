import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Módulos removidos do painel — índices shell mantidos (não reindexar).
const bool kChurchAvisosModuleEnabled = true;
const bool kChurchEventosModuleEnabled = true;
const bool kChurchChatModuleEnabled = true;

/// Exceção genérica para publicação/navegação em módulo removido.
final class ChurchPanelModuleRemovedException implements Exception {
  const ChurchPanelModuleRemovedException(this.moduleLabel, [this.detail]);

  final String moduleLabel;
  final String? detail;

  @override
  String toString() =>
      detail ?? 'O módulo $moduleLabel foi removido desta versão.';
}

typedef ChurchAvisosModuleRemovedException = ChurchPanelModuleRemovedException;
typedef ChurchEventosModuleRemovedException = ChurchPanelModuleRemovedException;
typedef ChurchChatModuleRemovedException = ChurchPanelModuleRemovedException;

/// Placeholder único para índices shell sem módulo activo.
class ChurchPanelModuleRemovedPage extends StatelessWidget {
  const ChurchPanelModuleRemovedPage({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle =
        'Este módulo não está disponível nesta versão do painel.',
  });

  final String title;
  final IconData icon;
  final String subtitle;

  factory ChurchPanelModuleRemovedPage.avisos({Key? key}) =>
      ChurchPanelModuleRemovedPage(
        key: key,
        title: 'Módulo Avisos indisponível',
        icon: Icons.campaign_outlined,
      );

  factory ChurchPanelModuleRemovedPage.eventos({Key? key}) =>
      ChurchPanelModuleRemovedPage(
        key: key,
        title: 'Módulo Eventos indisponível',
        icon: Icons.celebration_outlined,
      );

  factory ChurchPanelModuleRemovedPage.chat({Key? key}) =>
      ChurchPanelModuleRemovedPage(
        key: key,
        title: 'Chat da Igreja indisponível',
        icon: Icons.forum_outlined,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compat — índice 7.
typedef ChurchAvisosModuleRemovedPage = ChurchPanelModuleRemovedPage;
