import 'package:flutter/material.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rodapé da Agenda: feriados nacionais do [year] em faixa horizontal rolável.
class HolidayFooter extends StatelessWidget {
  const HolidayFooter({super.key, required this.year});

  final int year;

  static const Color _navy = Color(0xFF0C3B8A);

  @override
  Widget build(BuildContext context) {
    final list = HolidayHelper.nationalHolidays(year);
    if (list.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Icon(Icons.event_available_rounded, size: 18, color: _navy),
                const SizedBox(width: 8),
                Text(
                  'Feriados nacionais $year',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => Center(
                child: Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: const Color(0xFFCBD5E1),
                ),
              ),
              itemBuilder: (context, index) {
                final h = list[index];
                final dd = h.date.day.toString().padLeft(2, '0');
                final mm = h.date.month.toString().padLeft(2, '0');
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 13, color: _navy.withValues(alpha: 0.9)),
                      const SizedBox(width: 6),
                      Text(
                        '$dd/$mm · ${h.name}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
