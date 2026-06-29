import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';

/// Barra superior fina em módulos full screen no shell (voltar ao Painel + título).
class ChurchEmbeddedModuleBar extends StatelessWidget {
  const ChurchEmbeddedModuleBar({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.onBack,
    this.actions = const [],
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback onBack;
  final List<Widget> actions;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Material(
      color: Colors.transparent,
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent,
              Color.lerp(accent, Colors.white, 0.22)!,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        foregroundDecoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0x66FFE082),
              width: 2,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, narrow ? 2 : 4, 4, narrow ? 4 : 6),
            child: Row(
              children: [
                YahwehSuperPremiumBackButton(
                  onPressed: onBack,
                  tooltip: 'Voltar ao Painel',
                  variant: YahwehSuperPremiumBackVariant.onDarkAppBar,
                ),
                Icon(icon, color: Colors.white, size: narrow ? 20 : 22),
                SizedBox(width: narrow ? 6 : 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: narrow ? 15 : 16.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
