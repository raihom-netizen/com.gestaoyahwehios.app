import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/member_schedule_availability_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:table_calendar/table_calendar.dart';

/// Calendário para o membro marcar dias em que não pode servir (viagem, etc.).
class MemberScheduleAvailabilityPage extends StatefulWidget {
  final String tenantId;
  final String memberDocId;

  const MemberScheduleAvailabilityPage({
    super.key,
    required this.tenantId,
    required this.memberDocId,
  });

  @override
  State<MemberScheduleAvailabilityPage> createState() =>
      _MemberScheduleAvailabilityPageState();
}

class _MemberScheduleAvailabilityPageState
    extends State<MemberScheduleAvailabilityPage> {
  late final Future<_BootstrapResult> _bootstrap;

  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  Set<String> _ymds = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap = _loadBootstrap();
    _bootstrap.then((r) {
      if (!mounted || !r.doc.exists || r.forbidden) return;
      setState(() => _ymds = Set<String>.from(r.initialYmds));
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _memberDoc(String tid) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('membros')
        .doc(widget.memberDocId)
        .get();
  }

  Future<_BootstrapResult> _loadBootstrap() async {
    final tid = await TenantResolverService.resolveEffectiveTenantId(
        widget.tenantId);
    final doc = await _memberDoc(tid);
    if (!doc.exists) {
      return _BootstrapResult(
        tid: tid,
        doc: doc,
        forbidden: false,
        nome: '',
        initialYmds: {},
      );
    }
    final data = doc.data() ?? {};
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final authUid = (data['authUid'] ?? '').toString();
    final forbidden =
        authUid.isNotEmpty && uid != null && authUid != uid;
    final nome =
        (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString().trim();
    final ymds = MemberScheduleAvailability.parseYmdList(
      data[MemberScheduleAvailability.fieldYmds],
    ).toSet();
    return _BootstrapResult(
      tid: tid,
      doc: doc,
      forbidden: forbidden,
      nome: nome,
      initialYmds: ymds,
    );
  }

  Future<void> _persist(String tid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'Faça login para salvar.');
      return;
    }
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('membros')
        .doc(widget.memberDocId);
    final snap = await ref.get();
    if (!snap.exists) {
      setState(() => _error = 'Cadastro de membro não encontrado.');
      return;
    }
    final authUid = (snap.data()?['authUid'] ?? '').toString();
    if (authUid.isNotEmpty && authUid != uid) {
      setState(
          () => _error = 'Apenas o titular da conta pode alterar esta agenda.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sorted = _ymds.toList()..sort();
      await MemberScheduleAvailability.saveYmds(
          memberRef: ref, sortedYmds: sorted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Disponibilidade salva.'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static DateTime _parseYmd(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return DateTime.now();
    return DateTime(
      int.tryParse(p[0]) ?? 0,
      int.tryParse(p[1]) ?? 1,
      int.tryParse(p[2]) ?? 1,
    );
  }

  static String _formatYmdPt(String ymd) {
    final d = _parseYmd(ymd);
    const dias = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    const meses = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    final wd = dias[(d.weekday - 1).clamp(0, 6)];
    final m = meses[(d.month - 1).clamp(0, 11)];
    return '$wd, ${d.day} de $m de ${d.year}';
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar todos os dias?'),
        content: const Text(
          'Todos os dias marcados como indisponíveis serão removidos da lista. '
          'Toque em Salvar para gravar no servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            child: const Text('Limpar lista'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _ymds.clear();
        _error = null;
      });
    }
  }

  void _removeYmd(String ymd) {
    setState(() {
      _ymds.remove(ymd);
      _error = null;
    });
  }

  Widget _buildPremiumScaffold({
    required String title,
    required Widget body,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Text(title),
        actions: actions,
        bottom: bottom,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapResult>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildPremiumScaffold(
            title: 'Indisponibilidade',
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final r = snap.data;
        if (r == null) {
          return _buildPremiumScaffold(
            title: 'Indisponibilidade',
            body: Center(
              child: Padding(
                padding: ThemeCleanPremium.pagePadding(context),
                child: Text(
                  'Não foi possível carregar.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ),
          );
        }
        if (!r.doc.exists) {
          return _buildPremiumScaffold(
            title: 'Indisponibilidade',
            body: Center(
              child: Padding(
                padding: ThemeCleanPremium.pagePadding(context),
                child: Text(
                  'Membro não encontrado.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ),
          );
        }
        if (r.forbidden) {
          return _buildPremiumScaffold(
            title: 'Indisponibilidade',
            body: Center(
              child: Padding(
                padding: ThemeCleanPremium.pagePadding(context),
                child: Text(
                  'Somente o próprio membro pode marcar indisponibilidade nesta conta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              ),
            ),
          );
        }

        final tid = r.tid;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            appBar: AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              title: const Text(
                'Indisponibilidade',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => _persist(tid),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
              bottom: const TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Color(0xFFB8D4F5),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(
                    height: 48,
                    icon: Icon(Icons.calendar_month_rounded, size: 22),
                    text: 'Calendário',
                  ),
                  Tab(
                    height: 48,
                    icon: Icon(Icons.event_busy_rounded, size: 22),
                    text: 'Dias marcados',
                  ),
                ],
              ),
            ),
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: ThemeCleanPremium.churchPanelBodyGradient,
              ),
              child: SafeArea(
                child: TabBarView(
                  children: [
                    _CalendarTab(
                      nome: r.nome,
                      focused: _focused,
                      selected: _selected,
                      ymds: _ymds,
                      error: _error,
                      saving: _saving,
                      onPersist: () => _persist(tid),
                      onDaySelected: (selected, focused) {
                        setState(() {
                          _selected = selected;
                          _focused = focused;
                          final k = MemberScheduleAvailability.ymd(selected);
                          if (_ymds.contains(k)) {
                            _ymds.remove(k);
                          } else {
                            _ymds.add(k);
                          }
                          _error = null;
                        });
                      },
                      onPageChanged: (f) => setState(() => _focused = f),
                    ),
                    _ListTab(
                      ymds: _ymds,
                      onRemove: _removeYmd,
                      onClearAll: _confirmClearAll,
                      formatYmd: _formatYmdPt,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarTab extends StatelessWidget {
  final String nome;
  final DateTime focused;
  final DateTime selected;
  final Set<String> ymds;
  final String? error;
  final bool saving;
  final VoidCallback onPersist;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onPageChanged;

  const _CalendarTab({
    required this.nome,
    required this.focused,
    required this.selected,
    required this.ymds,
    required this.error,
    required this.saving,
    required this.onPersist,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return ListView(
      padding: pad,
      children: [
        if (nome.isNotEmpty)
          Text(
            nome,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        Text(
          'Toque nos dias em que você não poderá servir (viagem, trabalho, etc.). '
          'O líder verá um aviso ao montar a escala.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        Container(
          decoration: ThemeCleanPremium.premiumSurfaceCard,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: TableCalendar<void>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: focused,
              selectedDayPredicate: (d) => isSameDay(d, selected),
              startingDayOfWeek: StartingDayOfWeek.sunday,
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: ThemeCleanPremium.primary,
                  shape: BoxShape.circle,
                ),
                outsideDaysVisible: true,
                markersMaxCount: 1,
                markerDecoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              eventLoader: (day) {
                final k = MemberScheduleAvailability.ymd(day);
                return ymds.contains(k) ? const ['u'] : const [];
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (ctx, day, _) {
                  final k = MemberScheduleAvailability.ymd(day);
                  if (!ymds.contains(k)) return null;
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange.shade700),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
                selectedBuilder: (ctx, day, _) {
                  final k = MemberScheduleAvailability.ymd(day);
                  final mark = ymds.contains(k);
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: mark
                          ? Colors.deepOrange.shade600
                          : ThemeCleanPremium.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
            ),
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange.shade700),
              ),
            ),
            const SizedBox(width: ThemeCleanPremium.spaceSm),
            Expanded(
              child: Text(
                'Dia destacado = indisponível nesta data (todos os ministérios).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(
                color: ThemeCleanPremium.error.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              error!,
              style: const TextStyle(
                color: ThemeCleanPremium.error,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: ThemeCleanPremium.spaceLg),
        SizedBox(
          width: double.infinity,
          height: ThemeCleanPremium.minTouchTarget,
          child: FilledButton.icon(
            onPressed: saving ? null : onPersist,
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Salvar alterações'),
          ),
        ),
      ],
    );
  }
}

class _ListTab extends StatelessWidget {
  final Set<String> ymds;
  final void Function(String ymd) onRemove;
  final Future<void> Function() onClearAll;
  final String Function(String ymd) formatYmd;

  const _ListTab({
    required this.ymds,
    required this.onRemove,
    required this.onClearAll,
    required this.formatYmd,
  });

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    final sorted = ymds.toList()..sort();
    return ListView(
      padding: pad,
      children: [
        Text(
          'Gerencie os dias já marcados: exclua um dia quando puder servir ou limpe a lista inteira. '
          'Alterações só entram após Salvar.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        if (sorted.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceLg,
              vertical: ThemeCleanPremium.spaceXxl,
            ),
            decoration: ThemeCleanPremium.premiumSurfaceCard,
            child: Column(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  size: 56,
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                Text(
                  'Nenhum dia indisponível',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Text(
                  'Use a aba Calendário para marcar datas ou confira se já salvou antes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else ...[
          Container(
            decoration: ThemeCleanPremium.premiumSurfaceCard,
            child: Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceMd,
                      vertical: ThemeCleanPremium.spaceXs,
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      foregroundColor: ThemeCleanPremium.primary,
                      child: const Icon(Icons.event_busy_rounded, size: 22),
                    ),
                    title: Text(
                      formatYmd(sorted[i]),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      sorted[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remover este dia',
                      onPressed: () => onRemove(sorted[i]),
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: ThemeCleanPremium.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          OutlinedButton.icon(
            onPressed: onClearAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeCleanPremium.error,
              side: BorderSide(color: ThemeCleanPremium.error.withValues(alpha: 0.5)),
              minimumSize: const Size(
                double.infinity,
                ThemeCleanPremium.minTouchTarget,
              ),
            ),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Limpar todos os dias'),
          ),
        ],
      ],
    );
  }
}

class _BootstrapResult {
  final String tid;
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final bool forbidden;
  final String nome;
  final Set<String> initialYmds;

  _BootstrapResult({
    required this.tid,
    required this.doc,
    required this.forbidden,
    required this.nome,
    required this.initialYmds,
  });
}
