import 'package:flutter/material.dart';

import 'yahweh_month_calendar.dart';

/// Seletor de UM dia — mesmo visual do [YahwehMultiDayPickerPage] (padrão
/// Controle Total): calendário mensal onde o usuário TOCA o dia, com **Voltar**
/// no topo e **Cancelar / Confirmar** embaixo. Substitui o `showDatePicker`
/// (diálogo Material) padronizando a seleção de datas nos módulos.
///
/// Retorna o [DateTime] escolhido (só ano/mês/dia) ao Confirmar, ou `null` ao
/// Cancelar/Voltar.
class YahwehSingleDayPickerPage extends StatefulWidget {
  const YahwehSingleDayPickerPage({
    super.key,
    this.initial,
    this.firstDate,
    this.lastDate,
    this.accent = const Color(0xFF1D4ED8),
    this.title = 'Selecione a data',
  });

  final DateTime? initial;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final Color accent;
  final String title;

  /// Atalho estilo `showDatePicker`: abre a página e devolve a data (ou null).
  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initial,
    DateTime? firstDate,
    DateTime? lastDate,
    Color accent = const Color(0xFF1D4ED8),
    String title = 'Selecione a data',
  }) {
    return Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => YahwehSingleDayPickerPage(
          initial: initial,
          firstDate: firstDate,
          lastDate: lastDate,
          accent: accent,
          title: title,
        ),
      ),
    );
  }

  @override
  State<YahwehSingleDayPickerPage> createState() =>
      _YahwehSingleDayPickerPageState();
}

class _YahwehSingleDayPickerPageState extends State<YahwehSingleDayPickerPage> {
  late DateTime _visibleMonth;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? DateTime.now();
    _selected = widget.initial == null
        ? null
        : DateTime(base.year, base.month, base.day);
    _visibleMonth = DateTime(base.year, base.month);
  }

  bool _inRange(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (widget.firstDate != null) {
      final f = widget.firstDate!;
      if (day.isBefore(DateTime(f.year, f.month, f.day))) return false;
    }
    if (widget.lastDate != null) {
      final l = widget.lastDate!;
      if (day.isAfter(DateTime(l.year, l.month, l.day))) return false;
    }
    return true;
  }

  void _pick(DateTime day) {
    if (!_inRange(day)) return;
    setState(() => _selected = DateTime(day.year, day.month, day.day));
  }

  @override
  Widget build(BuildContext context) {
    final dayColors = <String, Color>{
      if (_selected != null)
        YahwehMonthCalendar.keyFor(_selected!): widget.accent,
    };
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: widget.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          children: [
            YahwehMonthCalendar(
              visibleMonth: _visibleMonth,
              selectedDay: _selected ?? DateTime(1900),
              dayColors: dayColors,
              onDayTap: _pick,
              onDaySelectedTap: _pick,
              onMonthDelta: (delta) => setState(() {
                _visibleMonth =
                    DateTime(_visibleMonth.year, _visibleMonth.month + delta);
              }),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: widget.accent.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, color: widget.accent, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    _selected == null
                        ? 'Toque um dia no calendário'
                        : '${_selected!.day.toString().padLeft(2, '0')}/${_selected!.month.toString().padLeft(2, '0')}/${_selected!.year}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: widget.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
