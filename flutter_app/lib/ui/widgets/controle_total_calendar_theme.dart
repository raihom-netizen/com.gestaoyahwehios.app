import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

/// Visual tipo “Controle Total”: dias em quadrados com borda, marcadores em quadrados na base.
class ControleTotalCalendarTheme {
  ControleTotalCalendarTheme._();

  static const double cellRadius = 8;

  /// Estilo base para [TableCalendar] — células retangulares (não círculos).
  static CalendarStyle calendarStyle({
    required double cellFs,
    required Color primary,
    required Color onSurface,
    /// Margem entre células — evita que marcadores “vazem” para o dia ao lado.
    EdgeInsets cellMargin = const EdgeInsets.all(1.85),
  }) {
    final borderDefault = const Color(0xFFCBD5E1);
    final borderSoft = const Color(0xFFE2E8F0);

    return CalendarStyle(
      outsideDaysVisible: true,
      canMarkersOverflow: true,
      cellMargin: cellMargin,
      cellPadding: EdgeInsets.zero,
      cellAlignment: Alignment.topCenter,
      defaultDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.1),
      ),
      weekendDecoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: borderDefault, width: 1.05),
      ),
      outsideDecoration: BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: borderSoft, width: 1),
      ),
      todayDecoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: primary, width: 2.2),
      ),
      selectedDecoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(cellRadius),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      defaultTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      weekendTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
      outsideTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade400,
      ),
      todayTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      selectedTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
      markersMaxCount: 0,
      markerSize: 0,
      markersAlignment: Alignment.bottomCenter,
      markersAnchor: 0.88,
    );
  }

  /// [TableCalendar] em modo intervalo: mesmas células do Controle Total + realce de período;
  /// fim de semana e feriados nacionais em **vermelho negrito** (usar com `holidayPredicate` falso
  /// e [HolidayHelper] nos [CalendarBuilders] para feriados no meio do intervalo).
  static CalendarStyle agendaDateRangePickerBase({
    required double cellFs,
    required Color primary,
    required Color onSurface,
  }) {
    const redEmphasis = Color(0xFFC1121F);
    final redBold = GoogleFonts.poppins(
      fontSize: cellFs,
      fontWeight: FontWeight.w800,
      color: redEmphasis,
    );
    final borderDefault = const Color(0xFFCBD5E1);
    final borderSoft = const Color(0xFFE2E8F0);

    return CalendarStyle(
      rangeHighlightColor: primary.withValues(alpha: 0.2),
      outsideDaysVisible: true,
      canMarkersOverflow: true,
      cellMargin: const EdgeInsets.all(1.85),
      cellPadding: EdgeInsets.zero,
      cellAlignment: Alignment.topCenter,
      defaultDecoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.1),
      ),
      weekendDecoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: borderDefault, width: 1.05),
      ),
      outsideDecoration: BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: borderSoft, width: 1),
      ),
      todayDecoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: primary, width: 2.2),
      ),
      rangeStartDecoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(cellRadius),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      rangeEndDecoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(cellRadius),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      withinRangeDecoration: BoxDecoration(
        color: primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(cellRadius),
        border: Border.all(color: primary.withValues(alpha: 0.35), width: 0.9),
      ),
      defaultTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      weekendTextStyle: redBold,
      outsideTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade400,
      ),
      todayTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      rangeStartTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
      rangeEndTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
      withinRangeTextStyle: GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      /// Evita o ramo "feriado" quebrar o contínuo do intervalo; feriado é estilizado nos builders.
      holidayDecoration: const BoxDecoration(shape: BoxShape.circle),
      holidayTextStyle: const TextStyle(fontSize: 0, height: 0),
      markersMaxCount: 0,
      markerSize: 0,
      markersAlignment: Alignment.bottomCenter,
      markersAnchor: 0.88,
    );
  }

  /// Quadrados de cor no rodapé da célula (eventos / escalas).
  static Widget markerRow({
    required List<Color> colors,
    required int moreCount,
    required bool isMobile,
  }) {
    final sz = isMobile ? 11.5 : 10.5;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: sz,
            height: sz,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.white,
                width: 1.25,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        if (moreCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '+$moreCount',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 9.5 : 8.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF475569),
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}
