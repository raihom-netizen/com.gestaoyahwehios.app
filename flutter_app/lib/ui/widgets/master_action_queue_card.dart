import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/master_dashboard_cache_service.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Fila de ações prioritárias no Command Center.
class MasterActionQueueCard extends StatelessWidget {
  const MasterActionQueueCard({
    super.key,
    required this.items,
    required this.onNavigateTo,
  });

  final List<MasterActionItem> items;
  final void Function(AdminMenuItem item) onNavigateTo;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return MasterPremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_rounded, color: ThemeCleanPremium.primary),
              const SizedBox(width: 8),
              const Text(
                'Fila de ações',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Prioridades do dia — toque para abrir o módulo.',
            style: TextStyle(
              fontSize: 12,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final menu = item.adminMenuItem;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: menu == null ? null : () => onNavigateTo(menu),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: ThemeCleanPremium.primary
                              .withValues(alpha: 0.12),
                          child: Text(
                            '${item.count}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: ThemeCleanPremium.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (item.subtitle.isNotEmpty)
                                Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Badge «Atualizado há X min» para o painel master.
class MasterCacheUpdatedBadge extends StatelessWidget {
  const MasterCacheUpdatedBadge({super.key, this.summary});

  final MasterDashboardSummary? summary;

  @override
  Widget build(BuildContext context) {
    final ts = summary?.cacheUpdatedAt;
    DateTime? dt;
    if (ts != null) {
      dt = ts.toDate();
    } else if ((summary?.cachedAtMs ?? 0) > 0) {
      dt = DateTime.fromMillisecondsSinceEpoch(summary!.cachedAtMs);
    }
    if (dt == null) return const SizedBox.shrink();

    final diff = DateTime.now().difference(dt);
    String label;
    if (diff.inMinutes < 2) {
      label = 'Dados atualizados agora';
    } else if (diff.inMinutes < 60) {
      label = 'Atualizado há ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      label = 'Atualizado há ${diff.inHours} h';
    } else {
      label =
          'Atualizado ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
