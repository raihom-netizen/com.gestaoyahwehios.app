import 'package:flutter/material.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Filtro WISDOMAPP — financeiro vs compromissos gerais da igreja.
enum ChurchAgendaWisdomFilter {
  financeiros,
  particulares,
}

/// UI Agenda — paridade visual WISDOMAPP (sem sync Google/Apple).
abstract final class ChurchAgendaWisdomUi {
  ChurchAgendaWisdomUi._();

  static const Color navy = Color(0xFF0C3B8A);
  static const Color financeOrange = Color(0xFFEA580C);
  static const Color particularesTeal = Color(0xFF0D9488);
  static const Color actionBlue = Color(0xFF2563EB);

  static const List<String> dowLabels = [
    'DOM',
    'SEG',
    'TER',
    'QUA',
    'QUI',
    'SEX',
    'SAB',
  ];

  /// Legenda sob a grade (cores do calendário).
  static Widget calendarLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Células coloridas = compromissos · vermelho negrito = sábado, '
              'domingo e feriado · toque no dia para ver o resumo.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cabeçalho SEG–DOM (WISDOMAPP).
  static Widget dayOfWeekCell(int index, {required bool startingSunday}) {
    final i = index.clamp(0, 6);
    final label = dowLabels[i];
    final isSun = i == 0;
    final isSat = i == 6;
    final weekend = isSun || isSat;
    return Center(
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: weekend ? const Color(0xFFE53935) : const Color(0xFF475569),
        ),
      ),
    );
  }

  /// Card «Resumo feriados» + botão PDF laranja.
  static Widget holidaySummaryCard({
    required int year,
    required int month,
    required VoidCallback onExportPdf,
    bool exporting = false,
  }) {
    final m = month.clamp(1, 12);
    final holidays = HolidayHelper.nationalHolidaysInMonth(year, m);
    final monthTitle = _monthYearPt(year, m);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_note_rounded, color: navy, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo feriados',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      monthTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: navy,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Feriados nacionais do mês do calendário',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (holidays.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: holidays.map((h) {
                final dd = h.date.day.toString().padLeft(2, '0');
                final mm = h.date.month.toString().padLeft(2, '0');
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '$dd/$mm · ${h.name}',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: navy,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: exporting ? null : onExportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: financeOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(
                'Exportar PDF — $monthTitle',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Chips Financeiros / Particulares.
  static Widget filterToggleRow({
    required ChurchAgendaWisdomFilter selected,
    required ValueChanged<ChurchAgendaWisdomFilter> onChanged,
    bool showFinance = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showFinance)
              Expanded(
                child: _filterChip(
                  label: 'Financeiros',
                  icon: Icons.account_balance_wallet_rounded,
                  active: selected == ChurchAgendaWisdomFilter.financeiros,
                  activeColor: financeOrange,
                  onTap: () => onChanged(ChurchAgendaWisdomFilter.financeiros),
                ),
              ),
            if (showFinance) const SizedBox(width: 10),
            Expanded(
              child: _filterChip(
                label: 'Particulares',
                icon: Icons.event_available_rounded,
                active: selected == ChurchAgendaWisdomFilter.particulares,
                activeColor: particularesTeal,
                onTap: () => onChanged(ChurchAgendaWisdomFilter.particulares),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Filtra o resumo do dia e o resumo do mês (financeiro ou particular).',
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.grey.shade600,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  static Widget _filterChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? activeColor : Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: active ? 2 : 0,
      shadowColor: activeColor.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? activeColor : const Color(0xFFE2E8F0),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: active ? Colors.white : activeColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// «Resumo do dia» — WISDOMAPP.
  static Widget daySummaryShell({
    required DateTime day,
    required ChurchAgendaWisdomFilter filter,
    required int eventCount,
    required VoidCallback onAdd,
    required Widget child,
  }) {
    final raw = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(day);
    final label = raw.isEmpty ? raw : '${raw[0].toUpperCase()}${raw.substring(1)}';
    final emptyFinance = filter == ChurchAgendaWisdomFilter.financeiros &&
        eventCount == 0;
    final emptyParticular = filter == ChurchAgendaWisdomFilter.particulares &&
        eventCount == 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: const Border(
          top: BorderSide(color: particularesTeal, width: 3),
          left: BorderSide(color: Color(0xFFE2E8F0)),
          right: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.today_rounded, color: navy, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo do dia',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (emptyFinance)
            Text(
              'Nenhum lançamento financeiro pendente neste dia.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            )
          else if (emptyParticular)
            Text(
              'Nenhum compromisso neste dia.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (!emptyFinance && !emptyParticular) child,
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: actionBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                filter == ChurchAgendaWisdomFilter.financeiros
                    ? 'Adicionar lançamento'
                    : 'Adicionar compromisso',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo mensal — WISDOMAPP.
  /// [breakdown]: contagem por tipo (Cultos, Eventos, Reuniões…) em tiles coloridos, padrão Controle Total.
  static Widget monthSummaryCard({
    required String monthLabel,
    required ChurchAgendaWisdomFilter filter,
    required int total,
    VoidCallback? onTap,
    List<({String label, int count, Color color, IconData icon})> breakdown =
        const [],
  }) {
    final finance = filter == ChurchAgendaWisdomFilter.financeiros;
    final msg = total == 0
        ? (finance
            ? 'Nenhum compromisso financeiro pendente em $monthLabel.'
            : 'Nenhum compromisso particular em $monthLabel.')
        : (finance
            ? '$total lançamento${total == 1 ? '' : 's'} financeiro${total == 1 ? '' : 's'} em $monthLabel.'
            : '$total compromisso${total == 1 ? '' : 's'} em $monthLabel.');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    finance ? Icons.payments_rounded : Icons.event_note_rounded,
                    color: finance ? financeOrange : particularesTeal,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      msg,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade500, size: 24),
                ],
              ),
              if (breakdown.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in breakdown) _monthBreakdownTile(b),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _monthBreakdownTile(
    ({String label, int count, Color color, IconData icon}) b,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            b.color.withValues(alpha: 0.16),
            b.color.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(b.icon, size: 16, color: b.color),
          const SizedBox(width: 6),
          Text(
            '${b.count}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: b.color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            b.label,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  static String _monthYearPt(int year, int month) {
    final raw = DateFormat('MMMM yyyy', 'pt_BR')
        .format(DateTime(year, month.clamp(1, 12)));
    if (raw.isEmpty) return raw;
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }
}
