import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/panel_section_prefs.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Atalhos rápidos no topo do painel — chips coloridos (padrão WISDOMAPP).
class PanelQuickShortcuts extends StatelessWidget {
  const PanelQuickShortcuts({
    super.key,
    required this.onOpenAniversariantesAno,
    required this.onOpenAgenda,
    required this.onOpenOrganograma,
    this.onOpenPainelCorpoAdmin,
  });

  final VoidCallback onOpenAniversariantesAno;
  final VoidCallback onOpenAgenda;
  final VoidCallback onOpenOrganograma;
  final VoidCallback? onOpenPainelCorpoAdmin;

  static const _items = <(IconData, String, List<Color>)>[
    (Icons.cake_rounded, 'Ano todo', [Color(0xFFF59E0B), Color(0xFFEA580C)]),
    (Icons.calendar_month_rounded, 'Agenda', [Color(0xFF0EA5E9), Color(0xFF2563EB)]),
    (Icons.account_tree_rounded, 'Organograma', [Color(0xFF7C3AED), Color(0xFF6366F1)]),
    (Icons.groups_rounded, 'Corpo admin.', [Color(0xFF10B981), Color(0xFF059669)]),
  ];

  @override
  Widget build(BuildContext context) {
    final actions = <VoidCallback>[
      onOpenAniversariantesAno,
      onOpenAgenda,
      onOpenOrganograma,
      if (onOpenPainelCorpoAdmin != null) onOpenPainelCorpoAdmin!,
    ];
    final count = onOpenPainelCorpoAdmin != null ? 4 : 3;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _GradientChip(
              icon: _items[i].$1,
              label: _items[i].$2,
              colors: _items[i].$3,
              onTap: actions[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _GradientChip extends StatelessWidget {
  const _GradientChip({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.32),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indica quando o cache do painel foi atualizado.
class PanelCacheUpdatedBadge extends StatelessWidget {
  const PanelCacheUpdatedBadge({super.key, this.updatedAt});

  final Timestamp? updatedAt;

  @override
  Widget build(BuildContext context) {
    if (updatedAt == null) return const SizedBox.shrink();
    final dt = updatedAt!.toDate();
    final diff = DateTime.now().difference(dt);
    String label;
    if (diff.inMinutes < 2) {
      label = 'Atualizado agora';
    } else if (diff.inMinutes < 60) {
      label = 'Atualizado há ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      label = 'Atualizado há ${diff.inHours} h';
    } else {
      label = 'Atualizado ${DateFormat('dd/MM HH:mm').format(dt)}';
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

/// Envolve uma secção do painel com expandir/recolher (cabeçalho WISDOMAPP).
class PanelCollapsibleSection extends StatefulWidget {
  const PanelCollapsibleSection({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.child,
    this.icon,
    this.accent,
    this.initiallyExpanded = true,
  });

  final String sectionKey;
  final String title;
  final Widget child;
  final IconData? icon;
  final Color? accent;
  final bool initiallyExpanded;

  @override
  State<PanelCollapsibleSection> createState() =>
      _PanelCollapsibleSectionState();
}

class _PanelCollapsibleSectionState extends State<PanelCollapsibleSection> {
  bool? _expanded;

  Color get _accent => widget.accent ?? ThemeCleanPremium.primary;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPref());
  }

  Future<void> _loadPref() async {
    final collapsed =
        await PanelSectionPrefs.isCollapsed(widget.sectionKey);
    if (!mounted) return;
    setState(() => _expanded = !collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded ?? widget.initiallyExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final next = !expanded;
              setState(() => _expanded = next);
              await PanelSectionPrefs.setCollapsed(
                widget.sectionKey,
                !next,
              );
            },
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color.lerp(Colors.white, _accent, 0.08)!,
                    Colors.white,
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg),
                border: Border.all(color: _accent.withValues(alpha: 0.12)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _accent,
                            Color.lerp(_accent, Colors.white, 0.3)!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF1E293B),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: _accent.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: widget.child,
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}
