import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/escala_member_payload.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/services/church_schedules_load_service.dart';
import 'package:gestao_yahweh/services/finance_month_cache.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_visual_palette.dart';
import 'package:gestao_yahweh/ui/widgets/color_palette_tabs_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_month_calendar.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_feriados_mes_card.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_preview_actions.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_responsible_picker.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_multi_day_picker_page.dart';
import 'package:gestao_yahweh/ui/pages/church_avisos_page.dart';
import 'package:gestao_yahweh/ui/pages/events_manager_page.dart';

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
enum AgKind { aviso, evento, culto, reuniao, escala, receita, despesa }

extension _AgKindX on AgKind {
  String get id => switch (this) {
    AgKind.aviso => 'aviso',
    AgKind.evento => 'evento',
    AgKind.culto => 'culto',
    AgKind.reuniao => 'reuniao',
    AgKind.escala => 'escala',
    AgKind.receita => 'receita_pendente',
    AgKind.despesa => 'despesa_pendente',
  };

  String get label => switch (this) {
    AgKind.aviso => 'Aviso',
    AgKind.evento => 'Evento',
    AgKind.culto => 'Culto',
    AgKind.reuniao => 'Reunião',
    AgKind.escala => 'Escala',
    AgKind.receita => 'Receita pendente',
    AgKind.despesa => 'Despesa pendente',
  };

  String get labelPlural => switch (this) {
    AgKind.aviso => 'Avisos',
    AgKind.evento => 'Eventos',
    AgKind.culto => 'Cultos',
    AgKind.reuniao => 'Reuniões',
    AgKind.escala => 'Escalas',
    AgKind.receita => 'Receitas pendentes',
    AgKind.despesa => 'Despesas pendentes',
  };

  Color get color => switch (this) {
    AgKind.aviso => AgendaVisualPalette.aviso,
    AgKind.evento => AgendaVisualPalette.evento,
    AgKind.culto => AgendaVisualPalette.culto,
    AgKind.reuniao => AgendaVisualPalette.reuniao,
    AgKind.escala => AgendaVisualPalette.escala,
    AgKind.receita => AgendaVisualPalette.receitaPendente,
    AgKind.despesa => AgendaVisualPalette.despesaPendente,
  };

  IconData get icon => switch (this) {
    AgKind.aviso => Icons.campaign_rounded,
    AgKind.evento => Icons.celebration_rounded,
    AgKind.culto => Icons.church_rounded,
    AgKind.reuniao => Icons.groups_rounded,
    AgKind.escala => Icons.badge_rounded,
    AgKind.receita => Icons.south_west_rounded,
    AgKind.despesa => Icons.north_east_rounded,
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

  Color get color =>
      AgendaVisualPalette.hexToColor(
        (data['colorHex'] ?? data['color'] ?? data['calendarColorHex'])
            ?.toString(),
      ) ??
      kind.color;
}

/// Ficha completa do compromisso (evento / culto / reunião).
///
/// Antes o "Ver detalhes" mostrava uma linha só («Evento · data hora») e o
/// gestor não via descrição, local, responsável nem quem está escalado.
Future<void> _showAgendaItemDetails(
  BuildContext context,
  _AgendaItem item, {
  VoidCallback? onEdit,
}) async {
  final d = item.data;

  String pick(List<String> keys) {
    for (final k in keys) {
      final v = (d[k] ?? '').toString().trim();
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  List<String> pickList(List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v is List && v.isNotEmpty) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  final dataLabel = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(item.when);
  final horaLabel = item.allDay
      ? 'Dia inteiro'
      : DateFormat('HH:mm', 'pt_BR').format(item.when);
  final descricao = pick([
    'description',
    'descricao',
    'text',
    'body',
    'mensagem',
    'observacao',
    'obs',
  ]);
  final local = pick([
    'location',
    'local',
    'endereco',
    'enderecoCompleto',
    'localNome',
  ]);
  final responsavel = pick([
    'responsavel',
    'responsavelNome',
    'ministro',
    'pregador',
    'dirigente',
  ]);
  final departamento = pick([
    'departmentName',
    'departamento',
    'departamentoNome',
  ]);
  final categoria = pick(['category', 'categoria', 'categoriaNome']);
  final parsedEscalados = EscalaMemberPayload.parseMembers(d);
  final escalados = parsedEscalados.isNotEmpty
      ? parsedEscalados.map((e) => e.name).where((e) => e.isNotEmpty).toList()
      : pickList(['memberNames', 'participantes']);

  final linhas = <({IconData icon, String label, String value})>[
    (icon: Icons.event_rounded, label: 'Tipo', value: item.kind.label),
    (icon: Icons.calendar_month_rounded, label: 'Data', value: dataLabel),
    (icon: Icons.schedule_rounded, label: 'Horário', value: horaLabel),
    if (categoria.isNotEmpty)
      (icon: Icons.local_offer_rounded, label: 'Categoria', value: categoria),
    if (departamento.isNotEmpty)
      (icon: Icons.groups_rounded, label: 'Departamento', value: departamento),
    if (responsavel.isNotEmpty)
      (icon: Icons.person_rounded, label: 'Responsável', value: responsavel),
    if (local.isNotEmpty)
      (icon: Icons.place_rounded, label: 'Local', value: local),
    if (escalados.isNotEmpty)
      (
        icon: Icons.people_alt_rounded,
        label: 'Escalados (${escalados.length})',
        value: escalados.join(' · '),
      ),
    if (descricao.isNotEmpty)
      (icon: Icons.notes_rounded, label: 'Descrição', value: descricao),
  ];

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [item.color, item.color.withValues(alpha: 0.72)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.kind.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                height: 1.15,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in linhas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(l.icon, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            SelectableText(
                              l.value,
                              style: const TextStyle(
                                fontSize: 14.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
        // Tocar no compromisso passou a abrir esta ficha em vez do editor —
        // sem este botão o gestor perdia o atalho para editar.
        if (onEdit != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onEdit();
            },
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Editar'),
          ),
        if (escalados.isNotEmpty)
          FilledButton.tonalIcon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (listContext) => AlertDialog(
                title: Text('Todos os escalados (${escalados.length})'),
                content: SizedBox(
                  width: 420,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: escalados.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(escalados[i]),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(listContext),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.groups_rounded),
            label: const Text('Ver todos os escalados'),
          ),
      ],
    ),
  );
}

/// Etiqueta compacta dos cards da agenda (preview por tipo).
Widget _agendaKindChip(String text, Color color, {IconData? icon}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(999),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
      ],
      Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  ),
);

class _AgendaCalendarioPageState extends State<AgendaCalendarioPage> {
  late DateTime _visibleMonth;
  DateTime _selectedDay = _dateOnly(DateTime.now());
  final Map<String, List<_AgendaItem>> _byDay = {};
  bool _loading = true;
  String? _softError;
  bool _funcoesOpen = false;
  bool _showFinance = false;

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
    if (hay.contains('aviso')) return AgKind.aviso;
    if (hay.contains('culto')) return AgKind.culto;
    if (hay.contains('reuni') || hay.contains('lideranca')) {
      return AgKind.reuniao;
    }
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
      final loads = await Future.wait([
        ChurchAgendaLoadService.loadAll(
          seedTenantId: widget.tenantId,
          forceServer: forceServer,
        ),
        ChurchSchedulesLoadService.loadEscalas(
          seedTenantId: widget.tenantId,
          forceServer: forceServer,
          limit: ChurchSchedulesLoadService.kEscalasDefaultLimit,
        ),
      ]);
      final res = loads[0] as ChurchAgendaLoadResult;
      final schedules = loads[1] as ChurchSchedulesLoadResult;
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
      for (final doc in schedules.docs) {
        final data = doc.data();
        if (data['active'] == false) continue;
        final rawDate = data['date'] ?? data['startTime'] ?? data['data'];
        final when = rawDate is Timestamp
            ? rawDate.toDate()
            : DateTime.tryParse(rawDate?.toString() ?? '');
        if (when == null) continue;
        final title =
            (data['title'] ??
                    data['titulo'] ??
                    data['departmentName'] ??
                    'Escala')
                .toString()
                .trim();
        final item = _AgendaItem(
          id: doc.id,
          title: title.isEmpty ? 'Escala' : title,
          when: when,
          kind: AgKind.escala,
          allDay: data['allDay'] == true,
          ref: doc.reference,
          data: {...data, 'sourceModule': 'escala'},
        );
        map.putIfAbsent(_keyFor(when), () => []).add(item);
      }
      if (_showFinance) {
        final finance = await FinanceMonthCache.fetchMonth(
          widget.tenantId,
          _visibleMonth,
          forceServer: forceServer,
        );
        for (final entry in finance.entries) {
          final item = _AgendaItem(
            id: entry.id,
            title: entry.description.trim().isEmpty
                ? entry.category
                : entry.description,
            when: entry.date,
            kind: entry.isIncome ? AgKind.receita : AgKind.despesa,
            allDay: true,
            ref: ChurchUiCollections.financeiro(widget.tenantId).doc(entry.id),
            data: {
              'sourceModule': 'financeiro',
              'amount': entry.amount,
              'category': entry.category,
              'status': entry.status,
              if (entry.calendarColorHex != null)
                'calendarColorHex': entry.calendarColorHex,
            },
          );
          map.putIfAbsent(_keyFor(entry.date), () => []).add(item);
        }
      }
      for (final list in map.values) {
        list.sort((a, b) => a.when.compareTo(b.when));
      }
      if (!mounted) return;
      setState(() {
        _byDay
          ..clear()
          ..addAll(map);
        _softError = res.softError ?? schedules.softError;
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
    if (_showFinance) unawaited(_load());
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
          AgendaFeriadosDoMesCard(
            visibleMonth: _visibleMonth,
            onDiaTocado: (dia) => setState(() => _selectedDay = dia),
          ),
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
                  const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
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
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                    ),
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
                  _funcTile(Icons.today_rounded, 'Ir para hoje', _goToday),
                  _funcTile(
                    Icons.refresh_rounded,
                    'Recarregar do servidor',
                    () => _load(forceServer: true),
                  ),
                  SwitchListTile.adaptive(
                    value: _showFinance,
                    onChanged: (value) {
                      setState(() => _showFinance = value);
                      unawaited(_load());
                    },
                    secondary: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                    ),
                    title: const Text(
                      'Pendências financeiras no calendário',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Desativado por padrão · receitas verdes e despesas vermelhas',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AgendaVisualPalette.receitaPendente,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 20,
              ),
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
            // MESMA porta do toque no dia: escolher aviso / evento / reunião
            // abria aqui um formulário simples e ali o editor completo — dois
            // caminhos com resultados diferentes para a mesma intenção.
            onTap: () => unawaited(_openDayCreateMenu(_selectedDay)),
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
          const Icon(
            Icons.touch_app_rounded,
            color: Color(0xFF059669),
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Um toque seleciona o dia. Toque novamente para abrir a prévia completa de avisos, eventos, cultos, reuniões, escalas e financeiro opcional.',
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
    final dayColorBands = <String, List<Color>>{};
    _byDay.forEach((key, items) {
      if (items.isEmpty) return;
      final kinds = items.map((e) => e.kind).toSet();
      dayColors[key] = kinds.length == 1
          ? items.first.color
          : const Color(0xFF0EA5A4);
      dayCounts[key] = items.length;
      dayColorBands[key] = items.map((e) => e.color).toSet().toList();
    });
    return YahwehMonthCalendar(
      visibleMonth: _visibleMonth,
      selectedDay: _selectedDay,
      dayColors: dayColors,
      dayCounts: dayCounts,
      dayColorBands: dayColorBands,
      onMonthDelta: _changeMonth,
      onDayTap: (day) => setState(() => _selectedDay = day),
      onDaySelectedTap: (day) => _openDayEditor(day),
      // O card «Feriados do mês» logo abaixo já lista tudo — o rodapé embutido
      // repetiria a mesma informação.
      showHolidayFooter: false,
    );
  }

  Widget _resumoDoDia() {
    final items = _itemsOf(_selectedDay);
    final dateLabel = DateFormat(
      "EEEE',' dd/MM/yyyy",
      'pt_BR',
    ).format(_selectedDay);
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
          else ...[
            for (final kind in const [
              AgKind.aviso,
              AgKind.evento,
              AgKind.culto,
              AgKind.reuniao,
              AgKind.escala,
              AgKind.receita,
              AgKind.despesa,
            ])
              if (items.any((e) => e.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Row(
                    children: [
                      Icon(kind.icon, size: 18, color: kind.color),
                      const SizedBox(width: 7),
                      Text(
                        kind.labelPlural,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: kind.color,
                        ),
                      ),
                    ],
                  ),
                ),
                ...items.where((e) => e.kind == kind).map(_dayItemTile),
              ],
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_rounded,
                  size: 18,
                  color: Color(0xFF475569),
                ),
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
          Icon(
            Icons.event_available_rounded,
            size: 40,
            color: Colors.blueGrey.shade200,
          ),
          const SizedBox(height: 8),
          const Text(
            'Nenhum compromisso neste dia.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => unawaited(_openDayCreateMenu(_selectedDay)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Adicionar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayItemTile(_AgendaItem item) {
    final timeLabel = item.allDay
        ? 'Dia todo'
        : DateFormat('HH:mm').format(item.when);
    final location = (item.data['location'] ?? item.data['local'] ?? '')
        .toString()
        .trim();
    final color = item.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // Abre a FICHA, não o editor: antes o toque ia direto para o
          // formulário e só funcionava para quem tinha permissão — um membro
          // comum não conseguia ver detalhe nenhum do compromisso.
          onTap: () => _showAgendaItemDetails(
            context,
            item,
            onEdit: _canEdit ? () => _openAddEditForm(item: item) : null,
          ),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EDF5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.045),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // IntrinsicHeight e obrigatorio: sem ele, `stretch` dentro de um
            // ListView (altura ilimitada) faz a linha tentar ocupar altura
            // infinita e o «Resumo do dia» estica sem fim.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Faixa de cor por tipo: culto azul, evento laranja, reunião roxo.
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color, color.withValues(alpha: 0.55)],
                      ),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withValues(alpha: 0.95),
                                  color.withValues(alpha: 0.70),
                                ],
                              ),
                            ),
                            child: Icon(
                              item.kind.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _agendaChip(item.kind.label, color),
                                    _agendaChip(
                                      timeLabel,
                                      const Color(0xFF475569),
                                      icon: Icons.schedule_rounded,
                                    ),
                                  ],
                                ),
                                if (location.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.place_rounded,
                                        size: 13,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          location,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // As mesmas três ações da prévia do mês: ver
                          // detalhes, alterar e excluir. Antes o resumo do dia
                          // só tinha uma seta — para editar ou apagar era
                          // preciso descobrir o caminho pelos cards do mês.
                          AgendaPreviewActions(
                            compact: true,
                            onDetails: () => _showAgendaItemDetails(
                              context,
                              item,
                              onEdit: _canEditAgendaItem(item)
                                  ? () => _openAddEditForm(item: item)
                                  : null,
                            ),
                            canEdit: _canEditAgendaItem(item),
                            onEdit: () =>
                                unawaited(_editAgendaItemFromPreview(item)),
                            onDelete: () =>
                                unawaited(_removerItemDaAgenda(item)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Etiqueta compacta usada nos cards da agenda.
  Widget _agendaChip(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _counters() {
    final month = _monthItems();
    final avisos = month.where((e) => e.kind == AgKind.aviso).length;
    final eventos = month.where((e) => e.kind == AgKind.evento).length;
    final reunioes = month.where((e) => e.kind == AgKind.reuniao).length;
    return Row(
      children: [
        _counterCard(
          'Todos',
          month.length,
          const Color(0xFF1D4ED8),
          Icons.calendar_month_rounded,
          onTap: () => _openKindPreview(
            context,
            title: 'Todos',
            items: month,
            canEdit: _canEditAgendaItem,
            onEdit: _editAgendaItemFromPreview,
            onDelete: _deleteAgendaItemFromPreview,
          ),
        ),
        const SizedBox(width: 10),
        _counterCard(
          'Reuniões',
          reunioes,
          AgKind.reuniao.color,
          AgKind.reuniao.icon,
          onTap: () => _openKindPreview(
            context,
            title: 'Reuniões',
            items: month.where((e) => e.kind == AgKind.reuniao).toList(),
            canEdit: _canEditAgendaItem,
            onEdit: _editAgendaItemFromPreview,
            onDelete: _deleteAgendaItemFromPreview,
          ),
        ),
        const SizedBox(width: 10),
        _counterCard(
          'Eventos',
          eventos,
          AgKind.evento.color,
          AgKind.evento.icon,
          onTap: () => _openKindPreview(
            context,
            title: 'Eventos',
            items: month.where((e) => e.kind == AgKind.evento).toList(),
            canEdit: _canEditAgendaItem,
            onEdit: _editAgendaItemFromPreview,
            onDelete: _deleteAgendaItemFromPreview,
          ),
        ),
        const SizedBox(width: 10),
        _counterCard(
          'Avisos',
          avisos,
          AgKind.aviso.color,
          AgKind.aviso.icon,
          onTap: () => _openKindPreview(
            context,
            title: 'Avisos',
            items: month.where((e) => e.kind == AgKind.aviso).toList(),
            canEdit: _canEditAgendaItem,
            onEdit: _editAgendaItemFromPreview,
            onDelete: _deleteAgendaItemFromPreview,
          ),
        ),
      ],
    );
  }

  Widget _counterCard(
    String label,
    int value,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AÇÕES
  // ---------------------------------------------------------------------------

  void _openDayEditor(DateTime day) {
    unawaited(_openDayCreateMenu(day));
  }

  /// Prévia do dia em **tela cheia**.
  ///
  /// Era um bottom sheet com altura igual à da tela dentro de uma folha que
  /// nunca chega à altura toda: o conteúdo transbordava, o rodapé ficava fora
  /// do ecrã e o texto do fundo aparecia por baixo do card. Uma rota inteira
  /// resolve isso e ainda dá espaço para as ações de cada compromisso.
  ///
  /// Devolve o tipo escolhido em «Adicionar» — é a MESMA porta que o botão
  /// «Novo» e o «Adicionar» do resumo do dia usam, para os três caminhos
  /// abrirem exatamente o mesmo editor.
  Future<void> _openDayCreateMenu(DateTime day) async {
    final choice = await Navigator.of(context).push<AgKind>(
      MaterialPageRoute<AgKind>(
        fullscreenDialog: true,
        builder: (_) => _AgendaDiaPreviewPage(
          day: day,
          canEdit: _canEdit,
          itemsBuilder: () => _itemsOf(day),
          canEditItem: _canEditAgendaItem,
          onDetails: (item) => _showAgendaItemDetails(
            context,
            item,
            onEdit: _canEditAgendaItem(item)
                ? () => _openAddEditForm(item: item)
                : null,
          ),
          onEdit: _editAgendaItemFromPreview,
          onDelete: _removerItemDaAgenda,
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _abrirEditorDoTipo(choice, day);
  }

  /// Abre o editor completo do tipo escolhido — aviso, evento/culto ou reunião.
  Future<void> _abrirEditorDoTipo(AgKind kind, DateTime day) async {
    if (kind == AgKind.aviso) {
      await openChurchAvisoEditor(
        context: context,
        tenantId: widget.tenantId,
        role: widget.role,
        permissions: widget.permissions ?? const [],
        initialDate: day,
      );
    } else if (kind == AgKind.evento || kind == AgKind.culto) {
      await openChurchEventEditor(
        context: context,
        tenantId: widget.tenantId,
        initialDate: day,
      );
    } else {
      await openChurchEventEditor(
        context: context,
        tenantId: widget.tenantId,
        initialDate: day,
        meetingMode: true,
      );
    }
    if (mounted) await _load(forceServer: true);
  }

  Future<void> _openAddEditForm({
    DateTime? day,
    _AgendaItem? item,
    AgKind? initialKind,
  }) async {
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
          initialKind: initialKind,
        ),
      ),
    );
    if (result == true) {
      await _load(forceServer: true);
    }
  }

  bool _canEditAgendaItem(_AgendaItem item) {
    if ((item.data['sourceModule'] ?? 'agenda') != 'agenda') return false;
    final role = widget.role.toLowerCase();
    if (role.contains('líder') || role.contains('lider')) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final author =
          (item.data['createdByUid'] ??
                  item.data['createdBy'] ??
                  item.data['authorUid'] ??
                  '')
              .toString();
      return uid.isNotEmpty && uid == author;
    }
    return _canEdit;
  }

  Future<void> _editAgendaItemFromPreview(_AgendaItem item) async {
    if (!_canEditAgendaItem(item)) return;
    await _openAddEditForm(item: item);
  }

  Future<void> _deleteAgendaItemFromPreview(_AgendaItem item) =>
      _removerItemDaAgenda(item);

  /// Remove um compromisso **por inteiro**: pergunta, apaga o documento de
  /// origem (evento ou aviso), o espelho na agenda e as imagens/vídeos no
  /// Storage.
  ///
  /// Antes apagava só o doc da `agenda`. O evento continuava no módulo
  /// Eventos, no mural e no site público, e as fotos ficavam a ocupar Storage
  /// para sempre — o utilizador via o item «voltar» e pagava armazenamento por
  /// ficheiros que já ninguém alcançava.
  Future<void> _removerItemDaAgenda(_AgendaItem item) async {
    if (!_canEditAgendaItem(item)) return;

    final rotulo = item.kind.label.toLowerCase();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: Color(0xFFDC2626),
          size: 30,
        ),
        title: Text('Remover $rotulo?'),
        content: Text(
          'Deseja realmente remover "${item.title}"?\n\n'
          'Isto apaga o registo do calendário, do módulo de origem e as '
          'fotos ou vídeos guardados. Não dá para desfazer.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final tid = ChurchRepository.churchId(widget.tenantId);
    final eventoId = (item.data['noticiaId'] ?? item.data['eventoId'] ?? '')
        .toString()
        .trim();
    final avisoId = (item.data['avisoId'] ?? '').toString().trim();

    try {
      if (eventoId.isNotEmpty) {
        // Apaga o evento de origem (Firestore + Storage + mural/site) e o
        // espelho que ele mantém na agenda.
        await ChurchEventosLoadService.deleteOne(
          churchIdHint: tid,
          docId: eventoId,
        );
        await ChurchFeedAgendaSyncService.deleteForEvento(
          tenantId: tid,
          eventoId: eventoId,
        );
      } else if (avisoId.isNotEmpty) {
        await ChurchAvisosService.deleteOne(churchIdHint: tid, docId: avisoId);
        await ChurchFeedAgendaSyncService.deleteForAviso(
          tenantId: tid,
          avisoId: avisoId,
        );
      }

      // O doc da agenda pode já ter desaparecido com o espelho; apagar de novo
      // é inofensivo e garante que nada fica para trás.
      await ChurchAgendaLoadService.deleteAgendaEvent(item.ref);

      // Compromisso criado direto na agenda também pode ter imagens.
      if (eventoId.isEmpty && avisoId.isEmpty) {
        await ChurchCanonicalMediaDeleteService.purgeFeedPostDeleted(
          tenantId: tid,
          postId: item.id,
          isEvento: item.kind != AgKind.aviso,
          data: item.data,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.kind.label} removido.'),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível remover: $e'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
    if (mounted) await _load(forceServer: true);
  }
}

extension _PadBottom on Widget {
  Widget paddedBottom() =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: this);
}

/// Prévia da Agenda.
Future<void> _openKindPreview(
  BuildContext context, {
  required String title,
  required List<_AgendaItem> items,
  required bool Function(_AgendaItem) canEdit,
  required Future<void> Function(_AgendaItem) onEdit,
  required Future<void> Function(_AgendaItem) onDelete,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _AgendaKindPreviewPage(
        title: title,
        items: items,
        canEdit: canEdit,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    ),
  );
}

/// Prévia completa de um dia — tela cheia.
///
/// Junta as duas coisas que se quer ao tocar num dia: **ver o que já existe**
/// (com ver detalhes / alterar / excluir) e **acrescentar** aviso, evento/culto
/// ou reunião. Devolve o [AgKind] escolhido em «Adicionar», ou `null` se a
/// pessoa apenas voltou.
class _AgendaDiaPreviewPage extends StatefulWidget {
  const _AgendaDiaPreviewPage({
    required this.day,
    required this.canEdit,
    required this.itemsBuilder,
    required this.canEditItem,
    required this.onDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime day;
  final bool canEdit;

  /// Lido a cada reconstrução — depois de excluir, a lista reflete o estado
  /// novo sem esta página precisar de guardar cópia dos dados.
  final List<_AgendaItem> Function() itemsBuilder;

  final bool Function(_AgendaItem) canEditItem;
  final Future<void> Function(_AgendaItem) onDetails;
  final Future<void> Function(_AgendaItem) onEdit;
  final Future<void> Function(_AgendaItem) onDelete;

  @override
  State<_AgendaDiaPreviewPage> createState() => _AgendaDiaPreviewPageState();
}

class _AgendaDiaPreviewPageState extends State<_AgendaDiaPreviewPage> {
  static final BoxDecoration _cartao = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Future<void> _executar(Future<void> Function() acao) async {
    await acao();
    if (mounted) setState(() {});
  }

  /// Lista do dia à prova de falha: um erro a montar os itens não pode
  /// esvaziar a página inteira — era assim que o segundo toque no dia abria um
  /// ecrã em branco, sem sequer as opções de adicionar aviso/evento/reunião.
  List<_AgendaItem> _itensSeguros() {
    try {
      return widget.itemsBuilder();
    } catch (e, st) {
      debugPrint('AgendaDiaPreview: falha a montar itens do dia: $e');
      debugPrint('$st');
      return const <_AgendaItem>[];
    }
  }

  /// `pt_BR` pode não estar carregado (arranque a frio na web) e o `DateFormat`
  /// atira — sem isto o `build` inteiro morria antes de desenhar o que quer que
  /// fosse.
  String _tituloSeguro() {
    String bruto;
    try {
      bruto = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(widget.day);
    } catch (_) {
      bruto = DateFormat('dd/MM/yyyy').format(widget.day);
    }
    if (bruto.isEmpty) return bruto;
    return bruto.substring(0, 1).toUpperCase() + bruto.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itensSeguros();
    final titulo = _tituloSeguro();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Retornar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Resumo completo do dia',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
            ),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: _corpoSeguro(itens),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _rodape(context),
    );
  }

  /// Conteúdo da prévia com rede de segurança.
  ///
  /// Se montar um cartão falhar (dados estranhos, paleta, o que for), a página
  /// inteira ficava em branco — sem lista **e** sem os botões de adicionar. Aqui
  /// o erro vira uma mensagem e as opções AVISO/EVENTO/REUNIÃO continuam de pé.
  List<Widget> _corpoSeguro(List<_AgendaItem> itens) {
    try {
      return _corpo(itens);
    } catch (e, st) {
      debugPrint('AgendaDiaPreview: falha a montar o corpo: $e');
      debugPrint('$st');
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cartao,
          child: const Text(
            'Não foi possível mostrar os compromissos deste dia. '
            'Pode acrescentar normalmente nas opções abaixo.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (widget.canEdit) ..._opcoesAdicionar(),
      ];
    }
  }

  List<Widget> _opcoesAdicionar() => [
    _secao(
      icone: Icons.add_circle_rounded,
      titulo: 'Adicionar neste dia',
    ),
    const SizedBox(height: 10),
    _escolha(
      kind: AgKind.aviso,
      title: 'AVISO',
      subtitle: 'Aviso completo com fotos, vídeo e validade',
      icon: Icons.campaign_rounded,
      color: AgendaVisualPalette.aviso,
    ),
    const SizedBox(height: 10),
    _escolha(
      kind: AgKind.evento,
      title: 'EVENTO / CULTO',
      subtitle: 'Evento completo com galeria, vídeo e localização',
      icon: Icons.celebration_rounded,
      color: AgKind.evento.color,
    ),
    const SizedBox(height: 10),
    _escolha(
      kind: AgKind.reuniao,
      title: 'REUNIÃO',
      subtitle: 'Responsáveis, departamentos, data e localização',
      icon: Icons.groups_rounded,
      color: AgKind.reuniao.color,
    ),
  ];

  List<Widget> _corpo(List<_AgendaItem> itens) {
    return [
                _secao(
                  icone: Icons.event_note_rounded,
                  titulo: 'Prévia do dia',
                  contador: '${itens.length}',
                ),
                const SizedBox(height: 10),
                if (itens.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 26,
                    ),
                    decoration: _cartao,
                    child: const Column(
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 34,
                          color: Color(0xFFCBD5E1),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Nenhum compromisso neste dia.',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF334155),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Use as opções abaixo para acrescentar.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in itens) _itemCard(item),
                if (widget.canEdit) ...[
                  const SizedBox(height: 18),
                  _secao(
                    icone: Icons.add_circle_rounded,
                    titulo: 'Adicionar neste dia',
                  ),
                  const SizedBox(height: 10),
                  _escolha(
                    kind: AgKind.aviso,
                    title: 'AVISO',
                    subtitle: 'Aviso completo com fotos, vídeo e validade',
                    icon: Icons.campaign_rounded,
                    color: AgendaVisualPalette.aviso,
                  ),
                  const SizedBox(height: 10),
                  _escolha(
                    kind: AgKind.evento,
                    title: 'EVENTO / CULTO',
                    subtitle:
                        'Evento completo com galeria, vídeo e localização',
                    icon: Icons.celebration_rounded,
                    color: AgKind.evento.color,
                  ),
                  const SizedBox(height: 10),
                  _escolha(
                    kind: AgKind.reuniao,
                    title: 'REUNIÃO',
                    subtitle:
                        'Responsáveis, departamentos, data e localização',
                    icon: Icons.groups_rounded,
                    color: AgKind.reuniao.color,
                  ),
                ] else ...[
                  // Sem permissão de edição a página ficava sem nada abaixo da
                  // lista — o utilizador via um ecrã vazio e não percebia
                  // porquê.
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    decoration: _cartao,
                    child: const Text(
                      'Só a liderança com permissão na Agenda pode acrescentar '
                      'avisos, eventos ou reuniões neste dia.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
    ];
  }

  Widget _rodape(BuildContext context) {
    return SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Retornar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF475569),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _secao({
    required IconData icone,
    required String titulo,
    String? contador,
  }) {
    return Row(
      children: [
        Icon(icone, size: 18, color: const Color(0xFF1D4ED8)),
        const SizedBox(width: 7),
        Text(
          titulo.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: Color(0xFF334155),
          ),
        ),
        if (contador != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              contador,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _itemCard(_AgendaItem item) {
    final hora = item.allDay
        ? 'Dia todo'
        : DateFormat('HH:mm').format(item.when);
    final local = (item.data['location'] ?? item.data['local'] ?? '')
        .toString()
        .trim();
    final cor = item.color;
    final podeEditar = widget.canEditItem(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _executar(() => widget.onDetails(item)),
          child: Ink(
            decoration: _cartao,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [cor, cor.withValues(alpha: 0.55)],
                      ),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 13, 8, 13),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cor.withValues(alpha: 0.95),
                                  cor.withValues(alpha: 0.70),
                                ],
                              ),
                            ),
                            child: Icon(
                              item.kind.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _agendaKindChip(item.kind.label, cor),
                                    _agendaKindChip(
                                      hora,
                                      const Color(0xFF475569),
                                      icon: Icons.schedule_rounded,
                                    ),
                                  ],
                                ),
                                if (local.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.place_rounded,
                                        size: 13,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          local,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AgendaPreviewActions(
                            compact: true,
                            onDetails: () =>
                                _executar(() => widget.onDetails(item)),
                            canEdit: podeEditar,
                            onEdit: () => _executar(() => widget.onEdit(item)),
                            onDelete: () =>
                                _executar(() => widget.onDelete(item)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _escolha({
    required AgKind kind,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => Navigator.pop(context, kind),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.72)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaKindPreviewPage extends StatelessWidget {
  const _AgendaKindPreviewPage({
    required this.title,
    required this.items,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });
  final String title;
  final List<_AgendaItem> items;
  final bool Function(_AgendaItem) canEdit;
  final Future<void> Function(_AgendaItem) onEdit;
  final Future<void> Function(_AgendaItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retornar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
      ),
      body: items.isEmpty
          ? const Center(child: Text('Nenhum compromisso encontrado.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final item = items[index];
                final date = DateFormat('dd/MM/yyyy').format(item.when);
                final time = item.allDay
                    ? 'Dia todo'
                    : DateFormat('HH:mm').format(item.when);
                final location =
                    (item.data['location'] ?? item.data['local'] ?? '')
                        .toString()
                        .trim();
                final color = item.color;
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    // O toque abria uma ficha pobre (tipo, data e hora numa
                    // linha) enquanto o menu de acoes abria a completa.
                    // Agora os dois caminhos abrem a mesma ficha.
                    onTap: () => _showAgendaItemDetails(
                      context,
                      item,
                      onEdit: canEdit(item) ? () => onEdit(item) : null,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8EDF5)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      // Mesmo motivo do card do dia: sem IntrinsicHeight o
                      // `stretch` estica sem limite dentro da lista.
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 6,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    color,
                                    color.withValues(alpha: 0.55),
                                  ],
                                ),
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(18),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  6,
                                  14,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            color.withValues(alpha: 0.95),
                                            color.withValues(alpha: 0.70),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        item.kind.icon,
                                        color: Colors.white,
                                        size: 23,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              _agendaKindChip(
                                                item.kind.label,
                                                color,
                                              ),
                                              _agendaKindChip(
                                                date,
                                                const Color(0xFF475569),
                                                icon: Icons
                                                    .calendar_today_rounded,
                                              ),
                                              _agendaKindChip(
                                                time,
                                                const Color(0xFF475569),
                                                icon: Icons.schedule_rounded,
                                              ),
                                            ],
                                          ),
                                          if (location.isNotEmpty) ...[
                                            const SizedBox(height: 5),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.place_rounded,
                                                  size: 13,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                                const SizedBox(width: 3),
                                                Expanded(
                                                  child: Text(
                                                    location,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF64748B),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    AgendaPreviewActions(
                                      onDetails: () => _showAgendaItemDetails(
                                        context,
                                        item,
                                        onEdit: canEdit(item)
                                            ? () => onEdit(item)
                                            : null,
                                      ),
                                      canEdit: canEdit(item),
                                      onEdit: () => onEdit(item),
                                      onDelete: () => onDelete(item),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _AgendaFormSheet extends StatefulWidget {
  const _AgendaFormSheet({
    required this.tenantId,
    required this.initialDate,
    this.item,
    this.initialKind,
  });

  final String tenantId;
  final DateTime initialDate;
  final _AgendaItem? item;
  final AgKind? initialKind;

  @override
  State<_AgendaFormSheet> createState() => _AgendaFormSheetState();
}

class _AgendaFormSheetState extends State<_AgendaFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _localCtrl;
  late final TextEditingController _responsavelCtrl;
  Set<String> _responsibleIds = <String>{};
  List<String> _responsibleNames = <String>[];
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
  DateTime? _validUntil;
  late String _colorHex;

  // Notificar todos (push via Cloud Function onNovaAgendaPush).
  bool _notify = false;
  bool _publishPublic = false;

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
    _publishPublic =
        d['publicarNoSite'] == true || d['publicar_no_site'] == true;
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
    _complementoCtrl = TextEditingController(
      text: (d['complemento'] ?? '').toString(),
    );
    final deps = d['departamentos'];
    if (deps is List) {
      _selectedDepartments.addAll(
        deps.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }
    _kind = it?.kind ?? widget.initialKind ?? AgKind.evento;
    _colorHex =
        (d['colorHex'] ??
                d['color'] ??
                '#${AgendaVisualPalette.colorToHex(_kind.color)}')
            .toString();
    _date = it?.when ?? widget.initialDate;
    _allDay = it?.allDay ?? false;
    final validRaw = d['validUntil'] ?? d['expiresAt'];
    if (validRaw is Timestamp) _validUntil = validRaw.toDate();
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
    return DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time!.hour,
      _time!.minute,
    );
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
      if ((r.bairro ?? '').trim().isNotEmpty) {
        _bairroCtrl.text = r.bairro!.trim();
      }
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
      final cidadeUf = [cidade, uf].where((e) => e.isNotEmpty).join(' - ');
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
      'colorHex': _colorHex.startsWith('#') ? _colorHex : '#$_colorHex',
      'notify': notify,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final desc = _descCtrl.text.trim();
    if (desc.isNotEmpty) p['descricao'] = desc;
    final local = _localCtrl.text.trim();
    if (local.isNotEmpty) p['local'] = local;
    if (_responsibleIds.isNotEmpty) {
      p['responsavelIds'] = _responsibleIds.toList();
    }
    if (_responsibleNames.isNotEmpty) p['responsaveis'] = _responsibleNames;
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
      ].where((e) => e.isNotEmpty).join(' ? ');
      if (composto.isNotEmpty) p['endereco'] = composto;
      if (_selectedDepartments.isNotEmpty) {
        p['departamentos'] = _selectedDepartments.toList();
      }
      if (_validUntil != null) {
        p['validUntil'] = Timestamp.fromDate(
          DateTime(
            _validUntil!.year,
            _validUntil!.month,
            _validUntil!.day,
            23,
            59,
          ),
        );
        p['expiresAt'] = p['validUntil'];
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
        // (mesma série; push só na 1? para não repetir).
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao excluir: $e')));
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
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
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
                    const Text(
                      'Tipo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final k in const [
                          AgKind.aviso,
                          AgKind.evento,
                          AgKind.culto,
                          AgKind.reuniao,
                        ]) ...[
                          Expanded(child: _kindChip(k)),
                          if (k != AgKind.reuniao) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await mostrarSeletorDeCores(
                          context,
                          titulo: 'Cor no calendário',
                          selecionadaHex: _colorHex,
                        );
                        if (picked != null && mounted)
                          setState(() => _colorHex = picked);
                      },
                      icon: CircleAvatar(
                        radius: 8,
                        backgroundColor:
                            AgendaVisualPalette.hexToColor(_colorHex) ??
                            _kind.color,
                      ),
                      label: const Text('Escolher cor no calendário'),
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
                        hint: _kind == AgKind.evento
                            ? 'Ex.: Templo — Salão principal'
                            : 'Ex.: Onde será o evento',
                        minLines: 1,
                        maxLines: 2,
                      ),
                    ],
                    if (_kind == AgKind.reuniao) _reuniaoFields(),
                    if (_kind == AgKind.aviso || _kind == AgKind.evento)
                      _responsiblePickerField(),
                    if (!_isEdit && _kind != AgKind.reuniao) _recurrenceField(),
                    if (!_isEdit && !_repeatWeekly) _multiDaysField(),
                    const SizedBox(height: 14),
                    _notifyField(),
                    const SizedBox(height: 8),
                    _publishField(),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
      onTap: () => setState(() {
        _kind = k;
        _colorHex = '#${AgendaVisualPalette.colorToHex(k.color)}';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? k.color : k.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: k.color, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(k.icon, color: selected ? Colors.white : k.color, size: 22),
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
                  child: Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : color,
                  ),
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
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
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

  Widget _responsiblePickerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Respons\u00e1veis'),
        const SizedBox(height: 8),
        AgendaResponsiblePicker(
          tenantId: widget.tenantId,
          selectedIds: _responsibleIds,
          onChanged: (ids, names) => setState(() {
            _responsibleIds = ids;
            _responsibleNames = names;
            _responsavelCtrl.text = names.join(', ');
          }),
        ),
      ],
    );
  }

  Widget _reuniaoFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _sectionLabel('Respons\u00e1vel'),
        const SizedBox(height: 8),
        _responsiblePickerField(),
        const SizedBox(height: 14),
        _sectionLabel('Localiza\u00e7\u00e3o'),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
        _addrField(
          _complementoCtrl,
          'Complemento (opcional)',
          Icons.add_location_alt_outlined,
        ),
        const SizedBox(height: 14),
        _sectionLabel('Validade da reunião'),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _validUntil ?? _date,
              firstDate: _date,
              lastDate: DateTime(_date.year + 5),
              locale: const Locale('pt', 'BR'),
            );
            if (picked != null && mounted) {
              setState(() => _validUntil = picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
            decoration: BoxDecoration(
              color: AgKind.reuniao.color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AgKind.reuniao.color.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: AgKind.reuniao.color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _validUntil == null
                        ? 'Definir data de validade'
                        : DateFormat('dd/MM/yyyy').format(_validUntil!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_validUntil != null)
                  IconButton(
                    tooltip: 'Sem validade',
                    onPressed: () => setState(() => _validUntil = null),
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
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
            _kind == AgKind.aviso
                ? 'Culto fixo (toda semana)'
                : 'Repetir toda semana',
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
                onPressed: _weeks > 2 ? () => setState(() => _weeks--) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text(
                '$_weeks semanas',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              IconButton(
                onPressed: _weeks < 26 ? () => setState(() => _weeks++) : null,
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
        ..addAll(
          result.where(
            (d) =>
                !(d.year == main.year &&
                    d.month == main.month &&
                    d.day == main.day),
          ),
        )
        ..sort();
    });
  }

  Widget _publishField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        secondary: const Icon(Icons.public_rounded, color: Color(0xFF15803D)),
        title: const Text(
          'Publicar no site p\u00fablico',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Permite que este registro apare\u00e7a no site p\u00fablico da igreja',
          style: TextStyle(fontSize: 12),
        ),
        value: _publishPublic,
        onChanged: (value) => setState(() => _publishPublic = value),
      ),
    );
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
        secondary: const Icon(
          Icons.notifications_active_rounded,
          color: Color(0xFF2563EB),
        ),
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
