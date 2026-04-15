import 'package:flutter/material.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rodapé da Agenda: feriados **nacionais** do mês visível — lista dia + nome.
class HolidayFooter extends StatelessWidget {
  const HolidayFooter({
    super.key,
    required this.year,
    required this.month,
  });

  final int year;
  final int month;

  static const Color _navy = Color(0xFF0C3B8A);
  static const Color _holidayDot = Color(0xFFE11D48);

  @override
  Widget build(BuildContext context) {
    final y = year;
    final m = month.clamp(1, 12);
    final list = HolidayHelper.nationalHolidaysInMonth(y, m);
    if (list.isEmpty) return const SizedBox.shrink();

    final monthTitle = _monthYearPt(y, m);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 18, color: _navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Feriados nacionais — $monthTitle',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...list.map((h) {
              final dia = h.date.day.toString().padLeft(2, '0');
              final mes = h.date.month.toString().padLeft(2, '0');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _holidayDot,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.grey.shade800,
                          ),
                          children: [
                            TextSpan(
                              text: 'Dia $dia/$mes',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: ' — ${h.name}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  static String _monthYearPt(int year, int month) {
    const names = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    final i = month - 1;
    if (i < 0 || i >= 12) return year.toString();
    return '${names[i]} $year';
  }
}
