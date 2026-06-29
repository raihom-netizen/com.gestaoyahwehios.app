import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_foreground_notification_snackbar.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_yahweh_brand_logo.dart';

/// Cartão de notificação estilo banco (Controle Total) — sino, lista e push em primeiro plano.
class GestaoBankNotificationTile extends StatelessWidget {
  const GestaoBankNotificationTile({
    super.key,
    required this.title,
    this.body = '',
    this.module,
    this.dateLabel = '',
    this.isRead = false,
    this.isChatMention = false,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final String body;
  final String? module;
  final String dateLabel;
  final bool isRead;
  final bool isChatMention;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final moduleKey = module ?? 'generico';
    final accent = gyModuleAccentColor(moduleKey);
    final moduleLabel = isChatMention ? 'Menção no chat' : gyModuleLabel(moduleKey);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(
              color: isRead
                  ? const Color(0xFFE2E8F0)
                  : accent.withValues(alpha: 0.28),
            ),
            boxShadow: isRead
                ? null
                : [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    ...ThemeCleanPremium.softUiCardShadow,
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: compact ? 10 : 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BrandModuleBadge(accent: accent, moduleKey: moduleKey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        moduleLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.08,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  maxLines: compact ? 2 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: compact ? 13 : 14,
                                    height: 1.3,
                                    fontWeight:
                                        isRead ? FontWeight.w700 : FontWeight.w800,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    body,
                                    maxLines: compact ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (dateLabel.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    dateLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandModuleBadge extends StatelessWidget {
  const _BrandModuleBadge({
    required this.accent,
    required this.moduleKey,
  });

  final Color accent;
  final String moduleKey;

  IconData get _moduleIcon {
    switch (moduleKey) {
      case 'aviso':
        return Icons.campaign_rounded;
      case 'evento':
        return Icons.event_rounded;
      case 'escala':
        return Icons.calendar_month_rounded;
      case 'aniversario':
        return Icons.cake_rounded;
      case 'membro':
        return Icons.person_add_alt_1_rounded;
      case 'chat':
        return Icons.forum_rounded;
      case 'pastoral':
        return Icons.volunteer_activism_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    const side = 44.0;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: GestaoYahwehBrandLogo(height: 34, width: 34),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(_moduleIcon, size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
