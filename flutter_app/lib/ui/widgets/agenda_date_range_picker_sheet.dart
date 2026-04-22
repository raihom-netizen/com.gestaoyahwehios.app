import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:gestao_yahweh/ui/widgets/holiday_footer.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

/// Exibe o calendário (estilo Controle Total) para escolher **início e fim** do evento
/// na agenda: mês com swipe, sáb/dom e feriados nacionais em **vermelho negrito**,
/// rodapé com lista de feriados do mês visível.
class AgendaDateRangePickerSheet extends StatefulWidget {
  const AgendaDateRangePickerSheet({
    super.key,
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  static const Color _redEmphasis = Color(0xFFC1121F);

  @override
  State<AgendaDateRangePickerSheet> createState() =>
      _AgendaDateRangePickerSheetState();
}

class _AgendaDateRangePickerSheetState extends State<AgendaDateRangePickerSheet> {
  late DateTime _focused;
  late DateTime? _rangeStart;
  late DateTime? _rangeEnd;
  late int _footerYear;
  late int _footerMonth;

  bool _isWeekend(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  @override
  void initState() {
    super.initState();
    final a = _dateOnly(
      widget.initialStart.isBefore(widget.initialEnd)
          ? widget.initialStart
          : widget.initialEnd,
    );
    final b = _dateOnly(
      widget.initialStart.isBefore(widget.initialEnd)
          ? widget.initialEnd
          : widget.initialStart,
    );
    _rangeStart = a;
    _rangeEnd = b;
    _focused = a;
    _footerYear = _focused.year;
    _footerMonth = _focused.month;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final cellFs = isMobile ? 16.0 : 15.0;
    final rowH = isMobile ? 50.0 : 46.0;
    final dowH = isMobile ? 32.0 : 30.0;
    final primary = ThemeCleanPremium.primary;
    final onSurface = ThemeCleanPremium.onSurface;

    final cal = ControleTotalCalendarTheme.agendaDateRangePickerBase(
      cellFs: cellFs,
      primary: primary,
      onSurface: onSurface,
    );

    final redBold = GoogleFonts.poppins(
      fontSize: cellFs,
      fontWeight: FontWeight.w800,
      color: AgendaDateRangePickerSheet._redEmphasis,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          'Data inicial e data final',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Navegue pelas setas. Toque no primeiro e no último dia do evento. '
          'Se for só um dia, toque duas vezes nele. Sábado, domingo e feriado '
          'nacional: número em vermelho; no rodapé, lista dos feriados do mês visível.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: ThemeCleanPremium.onSurfaceVariant,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        if (_rangeStart != null && _rangeEnd != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _fmtShort(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
          )
        else if (_rangeStart != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '1.º dia: ${_fmtLong(_rangeStart!)}. Toque no último.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF64748B), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: TableCalendar<void>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2036, 12, 31),
              focusedDay: _focused,
              locale: 'pt_BR',
              availableGestures: AvailableGestures.horizontalSwipe,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              rangeSelectionMode: RangeSelectionMode.enforced,
              rangeStartDay: _rangeStart,
              rangeEndDay: _rangeEnd,
              holidayPredicate: (_) => false,
              onRangeSelected: (start, end, focusedDay) {
                setState(() {
                  if (start != null) {
                    _rangeStart = _dateOnly(start);
                  } else {
                    _rangeStart = null;
                  }
                  if (end != null) {
                    _rangeEnd = _dateOnly(end);
                    if (_rangeStart != null && _rangeEnd!.isBefore(_rangeStart!)) {
                      final t = _rangeStart;
                      _rangeStart = _rangeEnd;
                      _rangeEnd = t;
                    }
                  } else {
                    _rangeEnd = null;
                  }
                  _focused = focusedDay;
                });
              },
              onPageChanged: (d) {
                setState(() {
                  _footerYear = d.year;
                  _footerMonth = d.month;
                });
              },
              calendarFormat: CalendarFormat.month,
              rowHeight: rowH,
              daysOfWeekHeight: dowH,
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 12.5 : 12,
                  fontWeight: FontWeight.w700,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
                weekendStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 12.5 : 12,
                  fontWeight: FontWeight.w800,
                  color: AgendaDateRangePickerSheet._redEmphasis,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                leftChevronIcon: const Icon(
                  Icons.chevron_left_rounded,
                  size: 28,
                  color: Color(0xFF0F172A),
                ),
                rightChevronIcon: const Icon(
                  Icons.chevron_right_rounded,
                  size: 28,
                  color: Color(0xFF0F172A),
                ),
                leftChevronPadding: EdgeInsets.zero,
                rightChevronPadding: EdgeInsets.zero,
                titleTextStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 17 : 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              calendarStyle: cal,
              calendarBuilders: CalendarBuilders(
                withinRangeBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  final hol = HolidayHelper.holidayNameOn(day) != null;
                  if (!wk && !hol) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: cal.withinRangeDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
                defaultBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  final hol = HolidayHelper.holidayNameOn(day) != null;
                  if (!wk && !hol) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: wk ? cal.weekendDecoration : cal.defaultDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
                outsideBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  if (!wk) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: cal.outsideDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
                todayBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  final hol = HolidayHelper.holidayNameOn(day) != null;
                  if (!wk && !hol) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: cal.todayDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
                rangeStartBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  final hol = HolidayHelper.holidayNameOn(day) != null;
                  if (!wk && !hol) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: cal.rangeStartDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
                rangeEndBuilder: (context, day, focused) {
                  final wk = _isWeekend(day);
                  final hol = HolidayHelper.holidayNameOn(day) != null;
                  if (!wk && !hol) return null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: cal.cellMargin,
                    padding: cal.cellPadding,
                    alignment: cal.cellAlignment,
                    decoration: cal.rangeEndDecoration,
                    child: Text('${day.day}', style: redBold),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.95)),
          child: HolidayFooter(year: _footerYear, month: _footerMonth),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  foregroundColor: primary,
                  side: BorderSide(color: primary.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  ),
                ),
                child: Text('Cancelar', style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                )),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _rangeStart == null
                    ? null
                    : () {
                        final a = _rangeStart!;
                        final b = _rangeEnd ?? a;
                        final s = a.isBefore(b) ? a : b;
                        final e = a.isBefore(b) ? b : a;
                        Navigator.of(context)
                            .pop((start: s, end: e));
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  ),
                ),
                child: Text('Confirmar', style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                )),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtShort() {
    if (_rangeStart == null || _rangeEnd == null) {
      return '';
    }
    if (isSameDay(_rangeStart!, _rangeEnd!)) {
      return _fmtLong(_rangeStart!);
    }
    return '${_fmtLong(_rangeStart!)} a ${_fmtLong(_rangeEnd!)}';
  }

  String _fmtLong(DateTime ref) {
    return DateFormat("EEE d MMM y", 'pt_BR').format(ref);
  }
}

/// Abre o seletor de **intervalo** e devolve o par de datas (ordem: início, fim).
Future<({DateTime start, DateTime end})?>
    showAgendaDateRangePicker(
  BuildContext context, {
  required DateTime initialStart,
  required DateTime initialEnd,
}) {
  return showModalBottomSheet<({DateTime start, DateTime end})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ThemeCleanPremium.radiusXl),
      ),
    ),
    builder: (context) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            MediaQuery.viewPaddingOf(context).bottom + 18,
          ),
          child: SingleChildScrollView(
            child: AgendaDateRangePickerSheet(
              initialStart: initialStart,
              initialEnd: initialEnd,
            ),
          ),
        ),
      );
    },
  );
}
