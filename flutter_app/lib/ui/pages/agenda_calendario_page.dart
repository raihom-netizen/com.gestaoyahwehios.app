import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_month_calendar.dart';

/// Módulo Agenda — reescrito do zero no padrão Controle Total (Agenda/Escala):
/// calendário mensal colorido, "Funções Calendário", Hoje/Sincronizar Google,
/// Resumo do dia e contadores (Todos / Reuniões / Eventos / Cultos), adaptado
/// para **cultos, eventos e reuniões**.
///
/// Lê/grava em `igrejas/{churchId}/agenda` via [ChurchAgendaLoadService]
/// (preserva cache/offline/recovery já existentes). Mesma assinatura do antigo
/// `CalendarPage` para troca direta no shell.
class AgendaCalendarioPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final List<String>? permissions;
  final bool embeddedInShell;

  const AgendaCalendarioPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
  });

  @override
  State<AgendaCalendarioPage> createState() => _AgendaCalendarioPageState();
}

/// Tipo canónico da agenda YAHWEH.
enum AgKind { culto, evento, reuniao }

extension _AgKindX on AgKind {
  String get id => switch (this) {
        AgKind.culto => 'culto',
        AgKind.evento => 'evento',
        AgKind.reuniao => 'reuniao',
      };

  String get label => switch (this) {
        AgKind.culto => 'Culto',
        AgKind.evento => 'Evento',
        AgKind.reuniao => 'Reunião',
      };

  String get labelPlural => switch (this) {
        AgKind.culto => 'Cultos',
        AgKind.evento => 'Eventos',
        AgKind.reuniao => 'Reuniões',
      };

  Color get color => switch (this) {
        AgKind.culto => const Color(0xFF2563EB), // azul
        AgKind.evento => const Color(0xFFF97316), // laranja
        AgKind.reuniao => const Color(0xFF7C3AED), // roxo
      };

  IconData get icon => switch (this) {
        AgKind.culto => Icons.church_rounded,
        AgKind.evento => Icons.celebration_rounded,
        AgKind.reuniao => Icons.groups_rounded,
      };
}

class _AgendaItem {
  _AgendaItem({
    required this.id,
    required this.title,
    required this.when,
    required this.kind,
    required this.allDay,
    required this.ref,
  });

  final String id;
  final String title;
  final DateTime when;
  final AgKind kind;
  final bool allDay;
  final DocumentReference<Map<String, dynamic>> ref;
}

class _AgendaCalendarioPageState extends State<AgendaCalendarioPage> {
  late DateTime _visibleMonth;
  DateTime _selectedDay = _dateOnly(DateTime.now());
  final Map<String, List<_AgendaItem>> _byDay = {};
  bool _loading = true;
  String? _softError;
  bool _funcoesOpen = false;

  bool get _canEdit {
    final r = widget.role.toLowerCase();
    if (r == 'membro' || r == 'visitante') {
      final perms = widget.permissions ?? const [];
      return perms.contains('agenda_edicao');
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _load();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _keyFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  AgKind _kindFrom(Map<String, dynamic> data, String title) {
    final raw = [
      data['tipo'],
      data['type'],
      data['categoria'],
      data['category'],
      data['kind'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    final hay = '$raw ${title.toLowerCase()}';
    if (hay.contains('culto')) return AgKind.culto;
    if (hay.contains('reuni')) return AgKind.reuniao;
    return AgKind.evento;
  }

  String _titleFrom(Map<String, dynamic> data) {
    for (final k in AgendaFirestoreFields.titleKeys) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return 'Compromisso';
  }

  Future<void> _load({bool forceServer = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await ChurchAgendaLoadService.loadAll(
        seedTenantId: widget.tenantId,
        forceServer: forceServer,
      );
      final map = <String, List<_AgendaItem>>{};
      for (final doc in res.docs) {
        final data = doc.data();
        final when = AgendaFirestoreFields.parseDate(data);
        if (when == null) continue;
        final title = _titleFrom(data);
        final item = _AgendaItem(
          id: doc.id,
          title: title,
          when: when,
          kind: _kindFrom(data, title),
          allDay: data['allDay'] == true,
          ref: doc.reference,
        );
        map.putIfAbsent(_keyFor(when), () => []).add(item);
      }
      for (final list in map.values) {
        list.sort((a, b) => a.when.compareTo(b.when));
      }
      if (!mounted) return;
      setState(() {
        _byDay
          ..clear()
          ..addAll(map);
        _softError = res.softError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _softError = 'Não foi possível carregar a agenda.';
        _loading = false;
      });
    }
  }

  List<_AgendaItem> _itemsOf(DateTime day) => _byDay[_keyFor(day)] ?? const [];

  List<_AgendaItem> _monthItems() {
    final out = <_AgendaItem>[];
    _byDay.forEach((_, list) {
      for (final it in list) {
        if (it.when.year == _visibleMonth.year &&
            it.when.month == _visibleMonth.month) {
          out.add(it);
        }
      }
    });
    return out;
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDay = _dateOnly(now);
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _load(forceServer: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          _funcoesCalendario(),
          const SizedBox(height: 12),
          _actionRow(),
          const SizedBox(height: 12),
          _hintCard(),
          const SizedBox(height: 14),
          _calendarCard(),
          const SizedBox(height: 14),
          _resumoDoDia(),
          const SizedBox(height: 14),
          _counters(),
          if (_softError != null) ...[
            const SizedBox(height: 12),
            Text(
              _softError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _funcoesCalendario() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _funcoesOpen = !_funcoesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'FUNÇÕES CALENDÁRIO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _funcoesOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          if (_funcoesOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  _funcTile(
                    Icons.add_circle_rounded,
                    'Novo culto / evento / reunião',
                    () => _openAddEditForm(day: _selectedDay),
                  ),
                  _funcTile(
                    Icons.today_rounded,
                    'Ir para hoje',
                    _goToday,
                  ),
                  _funcTile(
                    Icons.refresh_rounded,
                    'Recarregar do servidor',
                    () => _load(forceServer: true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _funcTile(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    ).paddedBottom();
  }

  Widget _actionRow() {
    // Sincronização com Google/Apple Agenda DESABILITADA por enquanto (futuro).
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            icon: Icons.calendar_today_rounded,
            label: 'Hoje',
            gradient: const [Color(0xFF0F172A), Color(0xFF1E293B)],
            onTap: _goToday,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            icon: Icons.add_rounded,
            label: 'Novo',
            gradient: const [Color(0xFFEC4899), Color(0xFFF97316)],
            onTap: () => _openAddEditForm(day: _selectedDay),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String? label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 14 : 12,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              if (label != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded, color: Color(0xFF059669), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Toque no dia para ver. Toque de novo no mesmo dia para incluir ou editar culto/evento/reunião.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF065F46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarCard() {
    // Calendário PADRÃO do sistema (mesmo widget de Escalas/Fornecedores).
    final dayColors = <String, Color>{};
    final dayCounts = <String, int>{};
    _byDay.forEach((key, items) {
      if (items.isEmpty) return;
      final kinds = items.map((e) => e.kind).toSet();
      dayColors[key] =
          kinds.length == 1 ? items.first.kind.color : const Color(0xFF0EA5A4);
      dayCounts[key] = items.length;
    });
    return YahwehMonthCalendar(
      visibleMonth: _visibleMonth,
      selectedDay: _selectedDay,
      dayColors: dayColors,
      dayCounts: dayCounts,
      onMonthDelta: _changeMonth,
      onDayTap: (day) => setState(() => _selectedDay = day),
      onDaySelectedTap: (day) => _openDayEditor(day),
    );
  }

  Widget _resumoDoDia() {
    final items = _itemsOf(_selectedDay);
    final dateLabel =
        DateFormat("EEEE',' dd/MM/yyyy", 'pt_BR').format(_selectedDay);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo do dia',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            dateLabel.isEmpty
                ? dateLabel
                : dateLabel.substring(0, 1).toUpperCase() +
                    dateLabel.substring(1),
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (items.isEmpty)
            _emptyDay()
          else
            ...items.map(_dayItemTile),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_rounded,
                    size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 8),
                Text(
                  'Total do dia: ${items.length} compromisso(s)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyDay() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded,
              size: 40, color: Colors.blueGrey.shade200),
          const SizedBox(height: 8),
          const Text(
            'Nenhum compromisso neste dia.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openAddEditForm(day: _selectedDay),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Adicionar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayItemTile(_AgendaItem item) {
    final timeLabel =
        item.allDay ? 'Dia todo' : DateFormat('HH:mm').format(item.when);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _canEdit ? () => _openAddEditForm(item: item) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 42,
              decoration: BoxDecoration(
                color: item.kind.color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.kind.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.kind.icon, color: item.kind.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.kind.label} · $timeLabel',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: item.kind.color,
                    ),
                  ),
                ],
              ),
            ),
            if (_canEdit)
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _counters() {
    final month = _monthItems();
    final cultos = month.where((e) => e.kind == AgKind.culto).length;
    final eventos = month.where((e) => e.kind == AgKind.evento).length;
    final reunioes = month.where((e) => e.kind == AgKind.reuniao).length;
    return Row(
      children: [
        _counterCard('Todos', month.length, const Color(0xFF1D4ED8),
            Icons.calendar_month_rounded),
        const SizedBox(width: 10),
        _counterCard('Reuniões', reunioes, AgKind.reuniao.color,
            AgKind.reuniao.icon),
        const SizedBox(width: 10),
        _counterCard(
            'Eventos', eventos, AgKind.evento.color, AgKind.evento.icon),
        const SizedBox(width: 10),
        _counterCard('Cultos', cultos, AgKind.culto.color, AgKind.culto.icon),
      ],
    );
  }

  Widget _counterCard(String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AÇÕES
  // ---------------------------------------------------------------------------

  void _openDayEditor(DateTime day) {
    if (!_canEdit) return;
    _openAddEditForm(day: day);
  }

  Future<void> _openAddEditForm({DateTime? day, _AgendaItem? item}) async {
    if (!_canEdit) return;
    final initialDate = item?.when ?? day ?? _selectedDay;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgendaFormSheet(
        tenantId: widget.tenantId,
        item: item,
        initialDate: initialDate,
      ),
    );
    if (result == true) {
      await _load(forceServer: true);
    }
  }
}

extension _PadBottom on Widget {
  Widget paddedBottom() =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: this);
}

/// Bottom sheet de criar/editar culto/evento/reunião.
class _AgendaFormSheet extends StatefulWidget {
  const _AgendaFormSheet({
    required this.tenantId,
    required this.initialDate,
    this.item,
  });

  final String tenantId;
  final DateTime initialDate;
  final _AgendaItem? item;

  @override
  State<_AgendaFormSheet> createState() => _AgendaFormSheetState();
}

class _AgendaFormSheetState extends State<_AgendaFormSheet> {
  late final TextEditingController _titleCtrl;
  late AgKind _kind;
  late DateTime _date;
  TimeOfDay? _time;
  bool _allDay = false;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _titleCtrl = TextEditingController(text: it?.title ?? '');
    _kind = it?.kind ?? AgKind.culto;
    _date = it?.when ?? widget.initialDate;
    _allDay = it?.allDay ?? false;
    _time = (it != null && !it.allDay)
        ? TimeOfDay(hour: it.when.hour, minute: it.when.minute)
        : const TimeOfDay(hour: 19, minute: 30);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  DateTime get _effectiveWhen {
    if (_allDay || _time == null) {
      return DateTime(_date.year, _date.month, _date.day, 0, 0);
    }
    return DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 19, minute: 30),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um título.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final when = _effectiveWhen;
      final payload = <String, dynamic>{
        'title': title,
        'titulo': title,
        'tipo': _kind.id,
        'categoria': _kind.id,
        'startTime': Timestamp.fromDate(when),
        'data': Timestamp.fromDate(when),
        'allDay': _allDay,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_isEdit) {
        await ChurchAgendaLoadService.updateAgendaEvent(
          ref: widget.item!.ref,
          payload: payload,
        );
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        final ref = ChurchUiCollections.agenda(widget.tenantId).doc();
        await ChurchAgendaLoadService.setAgendaEvent(ref: ref, payload: payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir'),
        content: const Text('Remover este compromisso da agenda?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ChurchAgendaLoadService.deleteAgendaEvent(widget.item!.ref);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao excluir: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'Editar compromisso' : 'Novo compromisso',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Título',
                  hintText: 'Ex.: Culto de Oração',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Tipo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final k in AgKind.values) ...[
                    Expanded(child: _kindChip(k)),
                    if (k != AgKind.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _fieldButton(
                      icon: Icons.calendar_today_rounded,
                      label: DateFormat('dd/MM/yyyy').format(_date),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _fieldButton(
                      icon: Icons.access_time_rounded,
                      label: _allDay
                          ? 'Dia todo'
                          : (_time?.format(context) ?? '--:--'),
                      onTap: _allDay ? null : _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dia todo'),
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_isEdit) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _delete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Excluir'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_isEdit ? 'Salvar' : 'Adicionar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindChip(AgKind k) {
    final selected = _kind == k;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _kind = k),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? k.color : k.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: k.color, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(k.icon,
                color: selected ? Colors.white : k.color, size: 22),
            const SizedBox(height: 4),
            Text(
              k.labelPlural,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : k.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF475569)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
