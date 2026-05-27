import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/panel_section_prefs.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Atalhos rápidos no topo do painel.
class PanelQuickShortcuts extends StatelessWidget {
  const PanelQuickShortcuts({
    super.key,
    required this.onOpenAniversariantesAno,
    required this.onOpenGaleriaEventos,
    required this.onOpenOrganograma,
    this.onOpenPainelCorpoAdmin,
  });

  final VoidCallback onOpenAniversariantesAno;
  final VoidCallback onOpenGaleriaEventos;
  final VoidCallback onOpenOrganograma;
  final VoidCallback? onOpenPainelCorpoAdmin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            icon: Icons.cake_rounded,
            label: 'Ano todo',
            onTap: onOpenAniversariantesAno,
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: Icons.photo_library_rounded,
            label: 'Galeria',
            onTap: onOpenGaleriaEventos,
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: Icons.account_tree_rounded,
            label: 'Organograma',
            onTap: onOpenOrganograma,
          ),
          if (onOpenPainelCorpoAdmin != null) ...[
            const SizedBox(width: 8),
            _Chip(
              icon: Icons.groups_rounded,
              label: 'Corpo admin.',
              onTap: onOpenPainelCorpoAdmin!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: ThemeCleanPremium.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
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

/// Envolve uma secção do painel com expandir/recolher.
class PanelCollapsibleSection extends StatefulWidget {
  const PanelCollapsibleSection({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.child,
    this.icon,
    this.initiallyExpanded = true,
  });

  final String sectionKey;
  final String title;
  final Widget child;
  final IconData? icon;
  final bool initiallyExpanded;

  @override
  State<PanelCollapsibleSection> createState() =>
      _PanelCollapsibleSectionState();
}

class _PanelCollapsibleSectionState extends State<PanelCollapsibleSection> {
  bool? _expanded;

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
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon,
                        size: 20, color: ThemeCleanPremium.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) widget.child,
      ],
    );
  }
}
