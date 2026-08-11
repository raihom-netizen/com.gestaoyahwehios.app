import 'package:flutter/material.dart';

import 'yahweh_month_calendar.dart';

/// Seletor de VÁRIOS dias — padrão Controle Total: um calendário mensal onde o
/// usuário TOCA os dias para marcar/desmarcar, com botão **Voltar** no topo,
/// contador "X dia(s) selecionado(s)" e **Cancelar / Confirmar** embaixo.
///
/// Retorna `List<DateTime>` (datas marcadas, só ano/mês/dia) ao Confirmar, ou
/// `null` ao Cancelar/Voltar. Reutiliza o [YahwehMonthCalendar] padrão do app.
class YahwehMultiDayPickerPage extends StatefulWidget {
  const YahwehMultiDayPickerPage({
    super.key,
    this.initialSelected = const [],
    this.accent = const Color(0xFF1D4ED8),
    this.title = 'Selecione a(s) data(s)',
  });

  final List<DateTime> initialSelected;
  final Color accent;
  final String title;

  @override
  State<YahwehMultiDayPickerPage> createState() =>
      _YahwehMultiDayPickerPageState();
}

class _YahwehMultiDayPickerPageState extends State<YahwehMultiDayPickerPage> {
  late DateTime _visibleMonth;
  final Map<String, DateTime> _selected = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    for (final d in widget.initialSelected) {
      final dd = DateTime(d.year, d.month, d.day);
      _selected[YahwehMonthCalendar.keyFor(dd)] = dd;
    }
  }

  void _toggle(DateTime day) {
    final dd = DateTime(day.year, day.month, day.day);
    final k = YahwehMonthCalendar.keyFor(dd);
    setState(() {
      if (_selected.containsKey(k)) {
        _selected.remove(k);
      } else {
        _selected[k] = dd;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dayColors = <String, Color>{
      for (final k in _selected.keys) k: widget.accent,
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
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => setState(_selected.clear),
            child: const Text('Limpar',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Column(
          children: [
            YahwehMonthCalendar(
              visibleMonth: _visibleMonth,
              selectedDay: DateTime(1900),
              dayColors: dayColors,
              onDayTap: _toggle,
              onDaySelectedTap: _toggle,
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
                  Icon(Icons.event_available_rounded,
                      color: widget.accent, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '${_selected.length} dia(s) selecionado(s)',
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
                  onPressed: () {
                    final list = _selected.values.toList()..sort();
                    Navigator.of(context).pop(list);
                  },
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
