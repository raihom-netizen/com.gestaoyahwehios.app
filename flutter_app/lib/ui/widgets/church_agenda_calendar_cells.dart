import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_visual_palette.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:intl/intl.dart';

/// Células do calendário — padrão WISDOMAPP (compromissos / cultos / agenda igreja).
abstract final class ChurchAgendaCalendarCells {
  ChurchAgendaCalendarCells._();

  static const Color kNationalHolidayDot = Color(0xFFE11D48);

  static const List<Color> compromissoPalette = [
    AgendaVisualPalette.culto,
    AgendaVisualPalette.curso,
    AgendaVisualPalette.evento,
    AgendaVisualPalette.escala,
    AgendaVisualPalette.pendencia,
    AgendaVisualPalette.eventoSocial,
    AgendaVisualPalette.lideranca,
    AgendaVisualPalette.agendaInterna,
    AgendaVisualPalette.feedEvento,
    AgendaVisualPalette.feriado,
  ];

  static Color corFromCompromisso(
    Map<String, dynamic> data, {
    Color fallback = AgendaVisualPalette.culto,
  }) {
    final raw = data['cor'];
    if (raw is int) return Color(raw);
    if (raw is num) return Color(raw.toInt());
    return fallback;
  }

  static List<Color> coresDoDia(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) {
    if (items.isEmpty) return const [];
    return items
        .take(3)
        .map((d) => corFromCompromisso(
              d.data(),
              fallback: compromissoPalette[
                  d.hashCode.abs() % compromissoPalette.length],
            ))
        .toList();
  }

  static String dayKey(DateTime d) =>
      DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));

  static Widget buildPlainDay(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final cellFs = isMobile ? 17.0 : 15.5;
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final isHoliday = HolidayHelper.holidayNameOn(day) != null;
    const outerPad = EdgeInsets.all(1.85);
    final radius = ControleTotalCalendarTheme.cellRadius;
    final primary = ThemeCleanPremium.primary;

    BoxDecoration deco;
    TextStyle textStyle;
    if (isSelected) {
      deco = BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      );
    } else if (isToday) {
      deco = BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: primary, width: 2.2),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      );
    } else if (isOutside) {
      deco = BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade400,
      );
    } else if (isHoliday) {
      deco = BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFFECDD3), width: 1.15),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF9F1239),
      );
    } else if (isWeekend) {
      deco = BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.05),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFBE123C),
      );
    } else {
      deco = BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.1),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: ThemeCleanPremium.onSurface,
      );
    }

    final showHolidayDot = isHoliday && (isSelected || isToday || isOutside);

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: deco,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Center(child: Text(day.day.toString(), style: textStyle)),
              if (showHolidayDot)
                Positioned(
                  bottom: 5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: kNationalHolidayDot,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget buildDayWithSegmentColors(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required List<Color> segmentColors,
    required int eventCount,
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    if (eventCount <= 0 || segmentColors.isEmpty) {
      return buildPlainDay(
        context,
        day,
        focusedDay,
        isToday: isToday,
        isSelected: isSelected,
        isOutside: isOutside,
      );
    }

    final isMobile = ThemeCleanPremium.isMobile(context);
    final cellFs = isMobile ? 17.0 : 15.5;
    final n = eventCount;
    final dim = isOutside ? 0.45 : 1.0;
    const outerPad = EdgeInsets.all(1.85);
    final radius = ControleTotalCalendarTheme.cellRadius;
    final primary = ThemeCleanPremium.primary;
    final isNationalHoliday = HolidayHelper.holidayNameOn(day) != null;

    final fill1 = segmentColors[0];
    final fill2 = segmentColors.length > 1
        ? segmentColors[1]
        : const Color(0xFF2563EB);
    final fill3 = segmentColors.length > 2
        ? segmentColors[2]
        : const Color(0xFF9333EA);

    Border border;
    List<BoxShadow>? cellShadow;
    if (isSelected) {
      border = Border.all(color: primary, width: 3.2);
      cellShadow = [
        BoxShadow(
          color: primary.withValues(alpha: 0.38),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (n >= 2 && !isOutside) {
      border = Border.all(
        color: isToday ? primary : const Color(0xFF0F172A),
        width: isToday ? 3.0 : 2.65,
      );
      cellShadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (isToday) {
      border = Border.all(color: primary, width: 2.4);
    } else {
      border = Border.all(
        color: isOutside ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
        width: n == 1 && !isOutside ? 1.35 : 1,
      );
    }

    final dayNum = day.day.toString();
    final multiDay = n >= 2;
    final isWeekendCell =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final numStyle = TextStyle(
      fontSize: cellFs,
      fontWeight:
          isSelected || isToday || multiDay ? FontWeight.w800 : FontWeight.w700,
      color: isWeekendCell ? const Color(0xFFFFE4E8) : Colors.white,
      shadows: [
        Shadow(
          color: isWeekendCell
              ? const Color(0xFF7F1D1D).withValues(alpha: 0.85)
              : const Color(0xA0000000),
          blurRadius: isWeekendCell ? 6 : 5,
          offset: const Offset(0, 1.5),
        ),
      ],
    );

    final extra = n > 3 ? n - 3 : 0;

    final Widget stripes;
    if (n == 1) {
      stripes = ColoredBox(color: fill1.withValues(alpha: 0.93 * dim));
    } else if (n == 2) {
      stripes = Row(
        children: [
          Expanded(
            child: ColoredBox(color: fill1.withValues(alpha: 0.88 * dim)),
          ),
          Expanded(
            child: ColoredBox(color: fill2.withValues(alpha: 0.88 * dim)),
          ),
        ],
      );
    } else {
      final count = n > 3 ? 3 : n;
      final children = <Widget>[];
      final cols = [fill1, fill2, fill3];
      for (var i = 0; i < count; i++) {
        if (i > 0) {
          children.add(
            Container(
              width: 1.6,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          );
        }
        children.add(
          Expanded(
            child: ColoredBox(
              color: cols[i].withValues(
                alpha: (0.84 + (isSelected ? 0.06 : 0)) * dim,
              ),
            ),
          ),
        );
      }
      stripes = Row(children: children);
    }

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: cellShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: stripes),
              Center(child: Text(dayNum, style: numStyle)),
              if (extra > 0)
                Positioned(
                  right: 3,
                  top: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '+$extra',
                      style: TextStyle(
                        fontSize: isMobile ? 9.5 : 8.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              if (isNationalHoliday)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: kNationalHolidayDot,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget buildDayWithCompromissos(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        byDay,
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final items = byDay[dayKey(day)] ?? [];
    if (items.isEmpty) {
      return buildPlainDay(
        context,
        day,
        focusedDay,
        isToday: isToday,
        isSelected: isSelected,
        isOutside: isOutside,
      );
    }
    return buildDayWithSegmentColors(
      context,
      day,
      focusedDay,
      segmentColors: coresDoDia(items),
      eventCount: items.length,
      isToday: isToday,
      isSelected: isSelected,
      isOutside: isOutside,
    );
  }
}

typedef FornecedorAgendaCalendarCells = ChurchAgendaCalendarCells;
