import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_month_calendar.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_multi_day_picker_page.dart';

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
    required this.data,
  });

  final String id;
  final String title;
  final DateTime when;
  final AgKind kind;
  final bool allDay;
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
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
          data: data,
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
    // Tela CHEIA (padrão Eventos/Avisos) com botão Voltar — em vez de bottom sheet.
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AgendaFormSheet(
          tenantId: widget.tenantId,
          item: item,
          initialDate: initialDate,
        ),
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
  late final TextEditingController _descCtrl;
  late final TextEditingController _localCtrl;
  late final TextEditingController _responsavelCtrl;
  late final TextEditingController _cepCtrl;
  late final TextEditingController _ruaCtrl;
  late final TextEditingController _bairroCtrl;
  late final TextEditingController _cidadeCtrl;
  late final TextEditingController _complementoCtrl;
  late AgKind _kind;
  late DateTime _date;
  TimeOfDay? _time;
  bool _allDay = false;
  bool _saving = false;

  // Notificar todos (push via Cloud Function onNovaAgendaPush).
  bool _notify = false;

  // Recorrência (culto/evento fixo — repetir toda semana).
  bool _repeatWeekly = false;
  int _weeks = 4;

  // Vários dias — cria uma ocorrência em cada data selecionada (além da principal).
  final List<DateTime> _extraDays = <DateTime>[];

  // Departamentos (reunião).
  List<String> _allDepartments = const [];
  final Set<String> _selectedDepartments = <String>{};

  bool _cepLoading = false;
  bool _churchAddrLoading = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    final d = it?.data ?? const <String, dynamic>{};
    _titleCtrl = TextEditingController(text: it?.title ?? '');
    _descCtrl = TextEditingController(
      text: (d['descricao'] ?? d['description'] ?? d['obs'] ?? '').toString(),
    );
    _localCtrl = TextEditingController(
      text: (d['local'] ?? d['localizacao'] ?? '').toString(),
    );
    _responsavelCtrl = TextEditingController(
      text: (d['responsavel'] ?? d['responsavelNome'] ?? '').toString(),
    );
    _cepCtrl = TextEditingController(text: (d['cep'] ?? '').toString());
    // Endereço separado; retrocompat com o campo único `endereco` legado.
    final legadoEnd = (d['endereco'] ?? d['endereço'] ?? '').toString();
    _ruaCtrl = TextEditingController(
      text: (d['rua'] ?? d['logradouro'] ?? (d['rua'] == null ? legadoEnd : ''))
          .toString(),
    );
    _bairroCtrl = TextEditingController(text: (d['bairro'] ?? '').toString());
    _cidadeCtrl = TextEditingController(
      text: (d['cidade'] ?? d['localidade'] ?? '').toString(),
    );
    _complementoCtrl =
        TextEditingController(text: (d['complemento'] ?? '').toString());
    final deps = d['departamentos'];
    if (deps is List) {
      _selectedDepartments.addAll(
        deps.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }
    _kind = it?.kind ?? AgKind.culto;
    _date = it?.when ?? widget.initialDate;
    _allDay = it?.allDay ?? false;
    _time = (it != null && !it.allDay)
        ? TimeOfDay(hour: it.when.hour, minute: it.when.minute)
        : const TimeOfDay(hour: 19, minute: 30);
    unawaited(_loadDepartments());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _localCtrl.dispose();
    _responsavelCtrl.dispose();
    _cepCtrl.dispose();
    _ruaCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _complementoCtrl.dispose();
    super.dispose();
  }

  DateTime get _effectiveWhen {
    if (_allDay || _time == null) {
      return DateTime(_date.year, _date.month, _date.day, 0, 0);
    }
    return DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ChurchDepartmentsLoadService.load(
        seedTenantId: widget.tenantId,
      );
      final names = <String>[];
      for (final doc in res.docs) {
        final m = doc.data();
        final n = (m['label'] ?? m['nome'] ?? m['name'] ?? m['titulo'] ?? '')
            .toString()
            .trim();
        if (n.isNotEmpty && !names.contains(n)) names.add(n);
      }
      if (!mounted) return;
      setState(() => _allDepartments = names);
    } catch (_) {
      // Departamentos são opcionais — silencioso.
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buscarCep() async {
    final digits = _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) {
      _toast('Informe um CEP com 8 dígitos.');
      return;
    }
    setState(() => _cepLoading = true);
    final r = await fetchCep(digits);
    if (!mounted) return;
    setState(() => _cepLoading = false);
    if (!r.ok) {
      _toast('CEP não encontrado.');
      return;
    }
    setState(() {
      if ((r.logradouro ?? '').trim().isNotEmpty) {
        _ruaCtrl.text = r.logradouro!.trim();
      }
      if ((r.bairro ?? '').trim().isNotEmpty) _bairroCtrl.text = r.bairro!.trim();
      final cidadeUf = [r.localidade, r.uf]
          .where((e) => e != null && e.trim().isNotEmpty)
          .map((e) => e!.trim())
          .join(' - ');
      if (cidadeUf.isNotEmpty) _cidadeCtrl.text = cidadeUf;
    });
  }

  Future<void> _usarEnderecoIgreja() async {
    setState(() => _churchAddrLoading = true);
    try {
      final snap = await ChurchUiCollections.churchDoc(widget.tenantId).get();
      final d = snap.data() ?? const <String, dynamic>{};
      final rua = (d['rua'] ?? d['address'] ?? d['endereco'] ?? '')
          .toString()
          .trim();
      final bairro = (d['bairro'] ?? '').toString().trim();
      final cidade = (d['cidade'] ?? d['localidade'] ?? '').toString().trim();
      final uf = (d['estado'] ?? d['uf'] ?? '').toString().trim();
      final cep = (d['cep'] ?? '').toString().trim();
      final cidadeUf =
          [cidade, uf].where((e) => e.isNotEmpty).join(' - ');
      if (!mounted) return;
      setState(() {
        if (rua.isNotEmpty) _ruaCtrl.text = rua;
        if (bairro.isNotEmpty) _bairroCtrl.text = bairro;
        if (cidadeUf.isNotEmpty) _cidadeCtrl.text = cidadeUf;
        if (cep.isNotEmpty && _cepCtrl.text.trim().isEmpty) _cepCtrl.text = cep;
      });
      if (rua.isEmpty && bairro.isEmpty && cidade.isEmpty && cep.isEmpty) {
        _toast('A igreja ainda não tem endereço cadastrado.');
      }
    } catch (_) {
      _toast('Não foi possível ler o endereço da igreja.');
    } finally {
      if (mounted) setState(() => _churchAddrLoading = false);
    }
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

  /// Monta o payload da agenda para um dado horário. [notify] só é `true` no
  /// primeiro doc de uma série (evita spam de push na recorrência).
  Map<String, dynamic> _buildPayload({
    required DateTime when,
    required bool notify,
    required bool isCreate,
    String? seriesId,
  }) {
    final title = _titleCtrl.text.trim();
    final p = <String, dynamic>{
      'title': title,
      'titulo': title,
      'tipo': _kind.id,
      'categoria': _kind.id,
      'startTime': Timestamp.fromDate(when),
      'data': Timestamp.fromDate(when),
      'allDay': _allDay,
      'active': true,
      'notify': notify,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final desc = _descCtrl.text.trim();
    if (desc.isNotEmpty) p['descricao'] = desc;
    final local = _localCtrl.text.trim();
    if (local.isNotEmpty) p['local'] = local;
    if (_kind == AgKind.reuniao) {
      final resp = _responsavelCtrl.text.trim();
      if (resp.isNotEmpty) p['responsavel'] = resp;
      final cep = _cepCtrl.text.trim();
      if (cep.isNotEmpty) p['cep'] = cep;
      final rua = _ruaCtrl.text.trim();
      if (rua.isNotEmpty) p['rua'] = rua;
      final bairro = _bairroCtrl.text.trim();
      if (bairro.isNotEmpty) p['bairro'] = bairro;
      final cidade = _cidadeCtrl.text.trim();
      if (cidade.isNotEmpty) p['cidade'] = cidade;
      final complemento = _complementoCtrl.text.trim();
      if (complemento.isNotEmpty) p['complemento'] = complemento;
      // Endereço composto (retrocompat com quem lê o campo único `endereco`).
      final composto = [
        [rua, complemento].where((e) => e.isNotEmpty).join(', '),
        bairro,
        cidade,
      ].where((e) => e.isNotEmpty).join(' — ');
      if (composto.isNotEmpty) p['endereco'] = composto;
      if (_selectedDepartments.isNotEmpty) {
        p['departamentos'] = _selectedDepartments.toList();
      }
    }
    if (seriesId != null) p['seriesId'] = seriesId;
    if (isCreate) p['createdAt'] = FieldValue.serverTimestamp();
    return p;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('Informe um título.');
      return;
    }
    setState(() => _saving = true);
    try {
      final when = _effectiveWhen;
      if (_isEdit) {
        await ChurchAgendaLoadService.updateAgendaEvent(
          ref: widget.item!.ref,
          payload: _buildPayload(when: when, notify: _notify, isCreate: false),
        );
      } else if (_repeatWeekly && _weeks > 1) {
        // Culto/evento fixo — cria uma ocorrência por semana (mesma série).
        final seriesId = DateTime.now().millisecondsSinceEpoch.toString();
        for (var i = 0; i < _weeks; i++) {
          final w = when.add(Duration(days: 7 * i));
          final ref = ChurchUiCollections.agenda(widget.tenantId).doc();
          await ChurchAgendaLoadService.setAgendaEvent(
            ref: ref,
            payload: _buildPayload(
              when: w,
              notify: _notify && i == 0,
              isCreate: true,
              seriesId: seriesId,
            ),
          );
        }
      } else if (_extraDays.isNotEmpty) {
        // Vários dias — cria uma ocorrência na data principal + em cada dia extra
        // (mesma série; push só na 1ª para não repetir).
        final seriesId = DateTime.now().millisecondsSinceEpoch.toString();
        final hh = _allDay || _time == null ? 0 : _time!.hour;
        final mm = _allDay || _time == null ? 0 : _time!.minute;
        final allDates = <DateTime>[
          when,
          ..._extraDays.map((d) => DateTime(d.year, d.month, d.day, hh, mm)),
        ];
        for (var i = 0; i < allDates.length; i++) {
          final ref = ChurchUiCollections.agenda(widget.tenantId).doc();
          await ChurchAgendaLoadService.setAgendaEvent(
            ref: ref,
            payload: _buildPayload(
              when: allDates[i],
              notify: _notify && i == 0,
              isCreate: true,
              seriesId: seriesId,
            ),
          );
        }
      } else {
        final ref = ChurchUiCollections.agenda(widget.tenantId).doc();
        await ChurchAgendaLoadService.setAgendaEvent(
          ref: ref,
          payload: _buildPayload(when: when, notify: _notify, isCreate: true),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Falha ao salvar. Verifique a conexão e tente de novo.');
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Cabeçalho FIXO com Voltar no topo — no web o AppBar não estava a
            // aparecer; este header garante o botão em todas as plataformas.
            Container(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Editar compromisso' : 'Novo compromisso',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancelar'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 20 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 6),
              // ---- Campos ricos (variam por tipo) ----
              _sectionLabel('Descrição'),
              const SizedBox(height: 8),
              _multilineField(
                controller: _descCtrl,
                hint: 'Detalhes, tema, observações…',
                minLines: 2,
                maxLines: 4,
              ),
              if (_kind != AgKind.reuniao) ...[
                const SizedBox(height: 14),
                _sectionLabel('Local'),
                const SizedBox(height: 8),
                _multilineField(
                  controller: _localCtrl,
                  hint: _kind == AgKind.culto
                      ? 'Ex.: Templo — Salão principal'
                      : 'Ex.: Onde será o evento',
                  minLines: 1,
                  maxLines: 2,
                ),
              ],
              if (_kind == AgKind.reuniao) _reuniaoFields(),
              if (!_isEdit && _kind != AgKind.reuniao) _recurrenceField(),
              if (!_isEdit && !_repeatWeekly) _multiDaysField(),
              const SizedBox(height: 14),
              _notifyField(),
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
                  if (!_isEdit) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancelar'),
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
          ],
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

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      );

  Widget _multilineField({
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 3,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _addrField(TextEditingController c, String hint, IconData icon) {
    return TextField(
      controller: c,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Linha marcável de departamento — moderna, colorida, nome sempre visível.
  Widget _depTile({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = AgKind.reuniao.color; // roxo
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.12)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : const Color(0xFFE2E8F0),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: selected ? color : color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 16, color: selected ? Colors.white : color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected ? color : Colors.blueGrey.shade200,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reuniaoFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _sectionLabel('Responsável'),
        const SizedBox(height: 8),
        TextField(
          controller: _responsavelCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Quem organiza a reunião',
            isDense: true,
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),
        _sectionLabel('Localização'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cepCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'CEP',
                  hintText: '00000-000',
                  isDense: true,
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed: _cepLoading ? null : _buscarCep,
                icon: _cepLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded, size: 18),
                label: const Text('Buscar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _churchAddrLoading ? null : _usarEnderecoIgreja,
            icon: _churchAddrLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.church_rounded, size: 18),
            label: const Text('Usar endereço da igreja'),
          ),
        ),
        const SizedBox(height: 8),
        _addrField(_ruaCtrl, 'Rua e número', Icons.signpost_outlined),
        const SizedBox(height: 8),
        _addrField(_bairroCtrl, 'Bairro', Icons.map_outlined),
        const SizedBox(height: 8),
        _addrField(_cidadeCtrl, 'Cidade / UF', Icons.location_city_rounded),
        const SizedBox(height: 8),
        _addrField(_complementoCtrl, 'Complemento (opcional)',
            Icons.add_location_alt_outlined),
        const SizedBox(height: 14),
        Row(
          children: [
            _sectionLabel('Departamento(s)'),
            const Spacer(),
            if (_selectedDepartments.isNotEmpty)
              Text(
                '${_selectedDepartments.length} selecionado(s)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AgKind.reuniao.color,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_allDepartments.isEmpty)
          Text(
            'Nenhum departamento cadastrado.',
            style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade400),
          )
        else ...[
          _depTile(
            label: 'Todos os departamentos',
            icon: Icons.done_all_rounded,
            selected: _selectedDepartments.length == _allDepartments.length,
            onTap: () => setState(() {
              if (_selectedDepartments.length == _allDepartments.length) {
                _selectedDepartments.clear();
              } else {
                _selectedDepartments
                  ..clear()
                  ..addAll(_allDepartments);
              }
            }),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final dep in _allDepartments)
                    _depTile(
                      label: dep,
                      icon: Icons.groups_rounded,
                      selected: _selectedDepartments.contains(dep),
                      onTap: () => setState(() {
                        if (_selectedDepartments.contains(dep)) {
                          _selectedDepartments.remove(dep);
                        } else {
                          _selectedDepartments.add(dep);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _recurrenceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _kind == AgKind.culto ? 'Culto fixo (toda semana)' : 'Repetir toda semana',
          ),
          subtitle: const Text('Cria uma ocorrência por semana'),
          value: _repeatWeekly,
          onChanged: (v) => setState(() => _repeatWeekly = v),
        ),
        if (_repeatWeekly)
          Row(
            children: [
              const Text('Por', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _weeks > 2
                    ? () => setState(() => _weeks--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text(
                '$_weeks semanas',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              IconButton(
                onPressed: _weeks < 26
                    ? () => setState(() => _weeks++)
                    : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
      ],
    );
  }

  Widget _multiDaysField() {
    final df = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _sectionLabel('Vários dias (opcional)'),
        const SizedBox(height: 4),
        Text(
          'Cria o mesmo item também nos dias escolhidos, além da data acima.',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _extraDays)
              InputChip(
                label: Text(df.format(d)),
                onDeleted: () => setState(() => _extraDays.remove(d)),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Escolher no calendário'),
              onPressed: _pickDaysCalendar,
            ),
          ],
        ),
      ],
    );
  }

  /// Abre o calendário multi-dias (padrão Controle Total): marca os dias,
  /// Cancelar/Confirmar, voltar no topo. Substitui a lista de dias extras.
  Future<void> _pickDaysCalendar() async {
    final result = await Navigator.of(context).push<List<DateTime>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => YahwehMultiDayPickerPage(
          initialSelected: _extraDays,
          accent: _kind.color,
        ),
      ),
    );
    if (result == null) return;
    final main = DateTime(_date.year, _date.month, _date.day);
    setState(() {
      _extraDays
        ..clear()
        ..addAll(result.where((d) =>
            !(d.year == main.year &&
                d.month == main.month &&
                d.day == main.day)))
        ..sort();
    });
  }

  Widget _notifyField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        secondary: const Icon(Icons.notifications_active_rounded,
            color: Color(0xFF2563EB)),
        title: const Text(
          'Notificar todos',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Envia um aviso (push) para os membros da igreja',
          style: TextStyle(fontSize: 12),
        ),
        value: _notify,
        onChanged: (v) => setState(() => _notify = v),
      ),
    );
  }
}
