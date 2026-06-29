import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Moldura premium do [TableCalendar] — padrão WISDOMAPP / Controle Total.
class ChurchAgendaCalendarPremiumShell extends StatelessWidget {
  const ChurchAgendaCalendarPremiumShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              ThemeCleanPremium.primary.withValues(alpha: 0.04),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: child,
        ),
      ),
    );
  }
}
