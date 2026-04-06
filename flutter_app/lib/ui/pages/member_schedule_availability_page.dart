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

  Future<DocumentSnapshot<Map<String, dynamic>>> _memberDoc(
      String tid) {
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapResult>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Indisponibilidade')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final r = snap.data;
        if (r == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Indisponibilidade')),
            body: const Center(child: Text('Não foi possível carregar.')),
          );
        }
        if (!r.doc.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Indisponibilidade')),
            body: const Center(child: Text('Membro não encontrado.')),
          );
        }
        if (r.forbidden) {
          return Scaffold(
            appBar: AppBar(title: const Text('Indisponibilidade')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Somente o próprio membro pode marcar indisponibilidade nesta conta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ),
          );
        }

        final tid = r.tid;
        return Scaffold(
          backgroundColor: ThemeCleanPremium.surfaceVariant,
          appBar: AppBar(
            title: const Text('Indisponibilidade para escalas'),
            actions: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _persist(tid),
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: ThemeCleanPremium.pagePadding(context),
              children: [
                if (r.nome.isNotEmpty)
                  Text(
                    r.nome,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Toque nos dias em que você não poderá servir (viagem, trabalho, etc.). O líder verá um aviso ao montar a escala.',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: TableCalendar<void>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2035, 12, 31),
                    focusedDay: _focused,
                    selectedDayPredicate: (d) => isSameDay(d, _selected),
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.15),
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
                      return _ymds.contains(k) ? const ['u'] : const [];
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (ctx, day, _) {
                        final k = MemberScheduleAvailability.ymd(day);
                        if (!_ymds.contains(k)) return null;
                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.orange.shade700),
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
                        final mark = _ymds.contains(k);
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
                      });
                    },
                    onPageChanged: (f) => setState(() => _focused = f),
                  ),
                ),
                const SizedBox(height: 16),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dia destacado = indisponível nesta data (todos os ministérios).',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: ThemeCleanPremium.error)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _persist(tid),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Salvar alterações'),
                ),
              ],
            ),
          ),
        );
      },
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
