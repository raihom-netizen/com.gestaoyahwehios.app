import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Calendário mensal PADRÃO do Gestão YAHWEH (visual do módulo Agenda).
///
/// Componente único reutilizado por Agenda, Escalas e Fornecedores para
/// padronizar o visual: cabeçalho ‹ MÊS ANO ›, cabeçalho de dias da semana
/// (DOM…SAB), células coloridas por dia (cor dominante + contador quando há
/// mais de um item) e destaque "HOJE". Semana começa no domingo.
///
/// É **stateless/controlado**: o pai fornece [visibleMonth], [selectedDay] e os
/// mapas de cor/contagem por dia (chave = `yyyy-MM-dd`), e recebe os callbacks.
class YahwehMonthCalendar extends StatelessWidget {
  const YahwehMonthCalendar({
    super.key,
    required this.visibleMonth,
    required this.selectedDay,
    required this.dayColors,
    this.dayCounts = const {},
    this.dayColorBands = const {},
    required this.onDayTap,
    this.onDaySelectedTap,
    required this.onMonthDelta,
    this.mixedColor = const Color(0xFF0EA5A4),
  });

  /// Primeiro dia do mês visível.
  final DateTime visibleMonth;

  /// Dia atualmente selecionado.
  final DateTime selectedDay;

  /// Cor de fundo por dia (chave `yyyy-MM-dd`). Ausente = dia sem itens.
  final Map<String, Color> dayColors;

  /// Contagem de itens por dia (chave `yyyy-MM-dd`) — mostra o badge de número.
  final Map<String, int> dayCounts;

  /// Cores dos compromissos do dia, usadas como faixas quando há vários itens.
  final Map<String, List<Color>> dayColorBands;

  /// Cor usada quando um dia tem itens de tipos diferentes (misto).
  final Color mixedColor;

  /// Toque simples num dia diferente do selecionado (seleciona).
  final void Function(DateTime day) onDayTap;

  /// Toque num dia JÁ selecionado (abrir/incluir) — opcional.
  final void Function(DateTime day)? onDaySelectedTap;

  /// Navegação de mês (-1 anterior, +1 próximo).
  final void Function(int delta) onMonthDelta;

  static const List<String> _weekdays = [
    'DOM',
    'SEG',
    'TER',
    'QUA',
    'QUI',
    'SEX',
    'SAB',
  ];

  static String keyFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Arrastar para a ESQUERDA = próximo mês; para a DIREITA = mês anterior.
      // Além das setas ‹ › no cabeçalho. Só troca com gesto horizontal claro
      // (não interfere no toque no dia nem no scroll vertical da página).
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -120) {
          onMonthDelta(1); // arrastou p/ esquerda → avança
        } else if (v > 120) {
          onMonthDelta(-1); // arrastou p/ direita → volta
        }
      },
      child: Center(
        child: ConstrainedBox(
          // Web: limita a largura para o calendário não esticar/inchar no
          // desktop (células menores). Mobile: usa toda a largura (maior).
          constraints: BoxConstraints(maxWidth: kIsWeb ? 640 : double.infinity),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                _monthHeader(),
                const SizedBox(height: 10),
                _weekdayRow(),
                const SizedBox(height: 6),
                _grid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthHeader() {
    final title = DateFormat(
      "MMMM 'de' yyyy",
      'pt_BR',
    ).format(visibleMonth).toUpperCase();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _circleNav(Icons.chevron_left_rounded, () => onMonthDelta(-1)),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E3A8A),
            letterSpacing: 0.3,
          ),
        ),
        _circleNav(Icons.chevron_right_rounded, () => onMonthDelta(1)),
      ],
    );
  }

  Widget _circleNav(IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xFFEFF6FF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(0xFF2563EB), size: 24),
        ),
      ),
    );
  }

  Widget _weekdayRow() {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                _weekdays[i],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: (i == 0 || i == 6)
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid() {
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leading = first.weekday % 7; // domingo = 0
    final today = _dateOnly(DateTime.now());
    final sel = _dateOnly(selectedDay);

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(visibleMonth.year, visibleMonth.month, d);
      cells.add(_dayCell(day, isToday: day == today, isSelected: day == sel));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    // Web (tela larga): célula ACHATADA (mais larga que alta) para o calendário
    // não ficar gigante; mobile: célula levemente mais ALTA (maior alvo de toque).
    final cellAspect = kIsWeb ? 1.22 : 0.78;

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 7; j++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: AspectRatio(
                    aspectRatio: cellAspect,
                    child: cells[i + j],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _dayCell(
    DateTime day, {
    required bool isToday,
    required bool isSelected,
  }) {
    final key = keyFor(day);
    final bg = dayColors[key];
    final count = dayCounts[key] ?? 0;
    final bands = dayColorBands[key] ?? const <Color>[];
    final hasItems = bg != null || bands.isNotEmpty;
    final fg = hasItems ? Colors.white : const Color(0xFF334155);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (isSelected && onDaySelectedTap != null) {
          onDaySelectedTap!(day);
        } else {
          onDayTap(day);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: bands.length > 1 ? null : (bg ?? Colors.white),
          gradient: bands.length > 1
              ? LinearGradient(
                  colors: bands,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1D4ED8)
                : (hasItems ? Colors.transparent : const Color(0xFFE2E8F0)),
            width: isSelected ? 2.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (isToday)
              Positioned(
                bottom: 3,
                left: 3,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: hasItems ? Colors.white : const Color(0xFF1D4ED8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      'HOJE',
                      style: TextStyle(
                        fontSize: 8.0,
                        fontWeight: FontWeight.w900,
                        color: hasItems
                            ? const Color(0xFF1D4ED8)
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            if (count > 1)
              Positioned(
                top: 3,
                right: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: bg ?? mixedColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
