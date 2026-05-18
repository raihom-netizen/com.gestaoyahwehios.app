import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rótulo legível para chave de função/cargo (pastor, secretario, …).
String churchRoleDisplayLabel(String raw) {
  final v = raw.trim().toLowerCase();
  const labels = {
    'pastor': 'Pastor',
    'pastora': 'Pastora',
    'presbitero': 'Presbítero',
    'diacono': 'Diácono',
    'secretario': 'Secretário',
    'secretaria': 'Secretária',
    'tesoureiro': 'Tesoureiro',
    'tesoureira': 'Tesoureira',
    'evangelista': 'Evangelista',
    'musico': 'Músico',
    'auxiliar': 'Auxiliar',
    'midia': 'Mídia',
    'divulgacao': 'Divulgação',
    'membro': 'Membro',
    'adm': 'Administrador',
    'gestor': 'Gestor',
  };
  return labels[v] ?? raw.trim();
}

/// Badge de cargo/função — texto sempre legível (Super Premium).
class ChurchRoleBadge extends StatelessWidget {
  final String label;

  const ChurchRoleBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = label.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.14),
            const Color(0xFF6366F1).withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.95),
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
