import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/schedule_swap_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/member_schedule_availability_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

class MySchedulesPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  const MySchedulesPage({super.key, required this.tenantId, required this.cpf, required this.role});

  @override
  State<MySchedulesPage> createState() => _MySchedulesPageState();
}

/// Filtro de período: diario, mes_anterior, mes_atual, anual, periodo
const _filterKeys = [
  ('diario', 'Diário'),
  ('mes_anterior', 'Mês anterior'),
  ('mes_atual', 'Mês atual'),
  ('anual', 'Anual'),
  ('periodo', 'Por período'),
];

class _MySchedulesPageState extends State<MySchedulesPage> {
  late final String _cpfDigits;
  late Future<String> _effectiveTidFuture;
  late DateTime _focusedMonth;
  DateTime? _selectedDay;
  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _eventsByDay = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = [];
  bool _loading = true;
  String _dateFilter = 'mes_atual';
  DateTime? _periodStart;
  DateTime? _periodEnd;

  static const _deptColors = [
    Color(0xFF3B82F6), Color(0xFF16A34A), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF8B5CF6), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF059669),
  ];

  @override
  void initState() {
    super.initState();
    _cpfDigits = widget.cpf.replaceAll(RegExp(r'[^0-9]'), '');
    _effectiveTidFuture = TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _selectedDay = DateTime.now();
    _load();
  }

  bool get _isAdmin {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tid = await _effectiveTidFuture;
      final schedules = FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('escalas');
      final members = FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      if (_isAdmin) {
        final snap = await schedules.orderBy('date').limit(200).get();
        docs = snap.docs;
      } else {
        final deptIds = await _loadMemberDepartments(members);
        final byMember = _cpfDigits.isNotEmpty
            ? (await schedules.where('memberCpfs', arrayContains: _cpfDigits).get()).docs
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final byDept = deptIds.isNotEmpty && deptIds.length <= 10
            ? (await schedules.where('departmentId', whereIn: deptIds).get()).docs
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in byMember) map[d.id] = d;
        for (final d in byDept) map.putIfAbsent(d.id, () => d);
        docs = map.values.toList()..sort((a, b) {
          final da = (a.data()['date'] as Timestamp?)?.toDate();
          final db = (b.data()['date'] as Timestamp?)?.toDate();
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
      }
      _allDocs = docs;
      _buildEventMap();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _buildEventMap() {
    _eventsByDay = {};
    for (final d in _allDocs) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      _eventsByDay.putIfAbsent(key, () => []).add(d);
    }
  }

  /// Documentos filtrados pelo período selecionado.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filteredDocs {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final endOfLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);

    return _allDocs.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) return false;
      switch (_dateFilter) {
        case 'diario':
          return dt.isAfter(startOfToday.subtract(const Duration(days: 1))) && dt.isBefore(endOfToday.add(const Duration(days: 1)));
        case 'mes_anterior':
          return !dt.isBefore(startOfLastMonth) && !dt.isAfter(endOfLastMonth);
        case 'mes_atual':
          return !dt.isBefore(startOfMonth) && !dt.isAfter(endOfMonth);
        case 'anual':
          return !dt.isBefore(startOfYear) && !dt.isAfter(endOfYear);
        case 'periodo':
          if (_periodStart == null || _periodEnd == null) return true;
          final start = DateTime(_periodStart!.year, _periodStart!.month, _periodStart!.day);
          final end = DateTime(_periodEnd!.year, _periodEnd!.month, _periodEnd!.day, 23, 59, 59);
          return !dt.isBefore(start) && !dt.isAfter(end);
        default:
          return true;
      }
    }).toList();
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> get _eventsByDayFiltered {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in _filteredDocs) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(d);
    }
    for (final k in map.keys) {
      map[k]!.sort((a, b) {
        final ta = (a.data()['time'] ?? '').toString();
        final tb = (b.data()['time'] ?? '').toString();
        return ta.compareTo(tb);
      });
    }
    return map;
  }

  Future<List<String>> _loadMemberDepartments(CollectionReference<Map<String, dynamic>> members) async {
    if (_cpfDigits.isEmpty) return [];
    final byId = await members.doc(_cpfDigits).get();
    if (byId.exists) return _deptList(byId.data());
    final q = await members.where('CPF', isEqualTo: _cpfDigits).limit(1).get();
    if (q.docs.isNotEmpty) return _deptList(q.docs.first.data());
    return [];
  }

  List<String> _deptList(Map<String, dynamic>? data) {
    final raw = data?['DEPARTAMENTOS'];
    return raw is List ? raw.map((e) => e.toString()).toList() : [];
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Retorna a chave de CPF usada no documento (igual à de memberCpfs/confirmations).
  String _confirmationKey(Map<String, dynamic> data) {
    final raw = data['memberCpfs'];
    final normalized = _cpfDigits.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw is List) {
      for (final e in raw) {
        final c = e?.toString() ?? '';
        if (c.replaceAll(RegExp(r'[^0-9]'), '') == normalized) return c;
      }
    }
    return _cpfDigits;
  }

  Future<void> _abrirPedidoTroca(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> escalaDoc,
  ) async {
    if (_cpfDigits.length != 11) return;
    final m = escalaDoc.data();
    final deptId = (m['departmentId'] ?? '').toString();
    if (deptId.isEmpty) return;
    DateTime? escDt;
    try {
      escDt = (m['date'] as Timestamp?)?.toDate();
    } catch (_) {}
    if (escDt == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data da escala inválida.')),
      );
      return;
    }
    final escalaTime = (m['time'] ?? '19:00').toString();
    final escalaTitle = (m['title'] ?? 'Escala').toString().trim();
    final escalaDateLabel = DateFormat('dd/MM/yyyy', 'pt_BR').format(escDt);
    final memberCpfs =
        ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final currentNorm = <String>{
      for (final c in memberCpfs) c.replaceAll(RegExp(r'[^0-9]'), ''),
    };

    final tid = await _effectiveTidFuture;
    if (!context.mounted) return;

    String solicitanteNome = '';
    try {
      final col =
          FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');
      final byId = await col.doc(_cpfDigits).get();
      if (byId.exists) {
        final d = byId.data()!;
        solicitanteNome =
            (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      } else {
        final q = await col.where('CPF', isEqualTo: _cpfDigits).limit(1).get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          solicitanteNome =
              (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    List<ScheduleSwapCandidate> candidates;
    try {
      candidates = await ScheduleSwapService.filterFreeCandidates(
        tenantId: tid,
        departmentId: deptId,
        solicitanteCpfDigits: _cpfDigits,
        escalaDay: escDt,
        escalaTime: escalaTime,
        currentEscalaMemberCpfsNorm: currentNorm,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar irmãos disponíveis: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não há irmãos livres neste horário (outra escala no mesmo dia ou indisponibilidade no calendário).',
          ),
        ),
      );
      return;
    }

    final chosen = await showDialog<ScheduleSwapCandidate?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Solicitar troca'),
        content: SizedBox(
          width: 320,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Só aparecem irmãos do mesmo departamento livres nesta data e horário.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final o = candidates[i];
                    return ListTile(
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: Text(o.nome),
                      subtitle: const Text(
                        'Livre neste horário',
                        style: TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, o),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('escala_trocas')
          .add({
        'escalaId': escalaDoc.id,
        'departmentId': deptId,
        'solicitanteCpf': _cpfDigits,
        'alvoCpf': chosen.cpf,
        'status': 'pendente_alvo',
        'solicitanteNome': solicitanteNome.isNotEmpty ? solicitanteNome : _cpfDigits,
        'escalaTitle': escalaTitle,
        'escalaDateLabel': escalaDateLabel,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Convite enviado para ${chosen.nome}. Quando aceitar, a escala será atualizada e o líder notificado.',
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registrar pedido: $e')),
        );
      }
    }
  }

  Future<void> _respondTrocaConvite(String tid, String trocaId, bool accept) async {
    try {
      await ScheduleSwapService.respondSwap(
        tenantId: tid,
        trocaId: trocaId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          accept
              ? 'Troca confirmada. A escala foi atualizada e o líder foi avisado.'
              : 'Você recusou o pedido. O irmão foi avisado.',
        ),
      );
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Não foi possível concluir.'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  Widget _buildIncomingSwapInvites() {
    if (_cpfDigits.length != 11) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: _effectiveTidFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final tid = snap.data!;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('igrejas')
              .doc(tid)
              .collection('escala_trocas')
              .where('alvoCpf', isEqualTo: _cpfDigits)
              .snapshots(),
          builder: (context, tSnap) {
            if (!tSnap.hasData) return const SizedBox.shrink();
            final items = tSnap.data!.docs
                .where(
                    (d) => (d.data()['status'] ?? '').toString() == 'pendente_alvo')
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mail_outline_rounded,
                          color: Colors.deepPurple.shade700, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Convites de troca',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.deepPurple.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final doc in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              (doc.data()['solicitanteNome'] ?? 'Um irmão')
                                  .toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'pediu para você assumir esta escala.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                (doc.data()['escalaDateLabel'] ?? '').toString(),
                                (doc.data()['escalaTitle'] ?? '').toString(),
                              ].where((s) => s.trim().isNotEmpty).join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _respondTrocaConvite(
                                        tid, doc.id, true),
                                    icon: const Icon(Icons.check_rounded, size: 20),
                                    label: const Text('Aceitar'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _respondTrocaConvite(
                                        tid, doc.id, false),
                                    icon: const Icon(Icons.close_rounded, size: 20),
                                    label: const Text('Recusar'),
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
            );
          },
        );
      },
    );
  }

  Future<String?> _resolveMemberDocId(String tid) async {
    if (_cpfDigits.length != 11) return null;
    final col =
        FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');
    final byId = await col.doc(_cpfDigits).get();
    if (byId.exists) return _cpfDigits;
    for (final field in ['CPF', 'cpf']) {
      final q = await col.where(field, isEqualTo: _cpfDigits).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.id;
    }
    return null;
  }

  Future<void> _openAvailabilityCalendar() async {
    if (_cpfDigits.length != 11) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Informe o CPF no cadastro para usar o calendário de indisponibilidade.')),
      );
      return;
    }
    final tid = await _effectiveTidFuture;
    if (!context.mounted) return;
    final mid = await _resolveMemberDocId(tid);
    if (!context.mounted) return;
    if (mid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cadastro de membro não encontrado para este CPF.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MemberScheduleAvailabilityPage(
          tenantId: widget.tenantId,
          memberDocId: mid,
        ),
      ),
    );
    if (!context.mounted) return;
    await _load();
  }

  Future<void> _confirmPresence(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) async {
    if (_cpfDigits.isEmpty) return;
    final key = _confirmationKey(doc.data() ?? {});
    final updates = <String, dynamic>{};
    if (status.isEmpty) {
      updates['confirmations.$key'] = FieldValue.delete();
      updates['unavailabilityReasons.$key'] = FieldValue.delete();
    } else {
      updates['confirmations.$key'] = status;
      if (status == 'indisponivel' && (motivo ?? '').trim().isNotEmpty) {
        updates['unavailabilityReasons.$key'] = {'reason': motivo!.trim(), 'at': FieldValue.serverTimestamp()};
      } else if (status != 'indisponivel') {
        updates['unavailabilityReasons.$key'] = FieldValue.delete();
      }
    }
    await doc.reference.update(updates);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final now = DateTime.now();
    final todayKey = _dayKey(now);
    final eventsByDay = _eventsByDayFiltered;
    final selectedKey = _selectedDay != null ? _dayKey(_selectedDay!) : todayKey;
    final selectedEvents = eventsByDay[selectedKey] ?? [];

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        elevation: 0,
        title: const Text('Minhas Escalas', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Indisponibilidade para escalas',
            onPressed: _openAvailabilityCalendar,
            icon: const Icon(Icons.event_busy_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: ThemeCleanPremium.pagePadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isMobile)
                        Padding(
                          padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                          child: OutlinedButton.icon(
                            onPressed: _openAvailabilityCalendar,
                            icon: const Icon(Icons.event_busy_rounded, size: 20),
                            label: const Text('Dias em que não posso servir'),
                          ),
                        ),
                      _buildIncomingSwapInvites(),
                      _buildSummary(now),
                      const SizedBox(height: ThemeCleanPremium.spaceSm),
                      _buildFilterChips(context),
                      const SizedBox(height: 20),
                      _buildCalendar(now, eventsByDay),
                      const SizedBox(height: 20),
                      _buildSelectedDayHeader(selectedKey),
                      const SizedBox(height: 10),
                      if (selectedEvents.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd), boxShadow: ThemeCleanPremium.softUiCardShadow),
                          child: Column(children: [
                            Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text('Nenhuma escala neste dia.', style: TextStyle(color: Colors.grey.shade600)),
                          ]),
                        )
                      else
                        for (final ev in selectedEvents) _buildEventCard(ev, now),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSummary(DateTime now) {
    final filtered = _filteredDocs;
    final thisMonth = filtered.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      return dt != null && dt.month == now.month && dt.year == now.year;
    }).toList();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final upcoming = filtered.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      return dt != null && !dt.isBefore(startOfToday);
    }).toList();
    final confirmed = filtered.where((d) {
      final conf = (d.data()['confirmations'] as Map<String, dynamic>?) ?? {};
      return conf[_cpfDigits] == 'confirmado';
    }).toList();

    return Row(children: [
      Expanded(
        child: _SummaryCard(
          value: '${thisMonth.length}',
          label: 'Este mês',
          icon: Icons.calendar_month_rounded,
          color: ThemeCleanPremium.primary,
          onTap: () => _openListaDetalhada(context, 'Este mês', thisMonth, now),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          value: '${upcoming.length}',
          label: 'Próximas',
          icon: Icons.upcoming_rounded,
          color: const Color(0xFF0891B2),
          onTap: () => _openListaDetalhada(context, 'Próximas', upcoming, now),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          value: '${confirmed.length}',
          label: 'Confirmadas',
          icon: Icons.check_circle_rounded,
          color: ThemeCleanPremium.success,
          onTap: () => _openListaDetalhada(context, 'Confirmadas', confirmed, now),
        ),
      ),
    ]);
  }

  void _openListaDetalhada(
    BuildContext context,
    String titulo,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MinhaEscalaListaPage(
          titulo: titulo,
          docs: docs,
          now: now,
          cpfDigits: _cpfDigits,
          onConfirm: _confirmPresence,
          onPop: () => setState(() {}),
          onRequestSwap: _cpfDigits.length == 11
              ? (d) => _abrirPedidoTroca(context, d)
              : null,
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'Período',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._filterKeys.map((e) {
                final selected = _dateFilter == e.$1;
                return FilterChip(
                  label: Text(e.$2, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
                  selected: selected,
                  onSelected: (v) => setState(() => _dateFilter = v == true ? e.$1 : _dateFilter),
                  selectedColor: ThemeCleanPremium.primary.withOpacity(0.15),
                  checkmarkColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                );
              }),
              if (_dateFilter == 'periodo') ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _periodStart ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _periodStart = d);
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(_periodStart == null ? 'Início' : DateFormat('dd/MM/yyyy').format(_periodStart!)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _periodEnd ?? _periodStart ?? DateTime.now(),
                      firstDate: _periodStart ?? DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _periodEnd = d);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(_periodEnd == null ? 'Fim' : DateFormat('dd/MM/yyyy').format(_periodEnd!)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(DateTime now, Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> eventsByDay) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final startWeekday = firstDay.weekday % 7;
    final meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd), boxShadow: ThemeCleanPremium.softUiCardShadow),
      child: Column(
        children: [
          Row(children: [
            IconButton(
              onPressed: () => setState(() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1); }),
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
            ),
            Expanded(
              child: Text(
                '${meses[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => setState(() { _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1); }),
              icon: const Icon(Icons.chevron_right_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
                .map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500)))))
                .toList(),
          ),
          const SizedBox(height: 6),
          ...List.generate(((startWeekday + daysInMonth) / 7).ceil(), (week) {
            return Row(
              children: List.generate(7, (col) {
                final dayNum = week * 7 + col - startWeekday + 1;
                if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox(height: 44));
                final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
                final key = _dayKey(date);
                final events = eventsByDay[key] ?? [];
                final isToday = key == _dayKey(now);
                final isSelected = _selectedDay != null && key == _dayKey(_selectedDay!);

                final dotColors = <Color>{};
                for (final ev in events) {
                  final deptId = (ev.data()['departmentId'] ?? '').toString();
                  dotColors.add(_deptColors[deptId.hashCode.abs() % _deptColors.length]);
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = date),
                    child: Container(
                      height: 44,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isSelected ? ThemeCleanPremium.primary : isToday ? ThemeCleanPremium.primary.withOpacity(0.08) : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected ? Colors.white : isToday ? ThemeCleanPremium.primary : ThemeCleanPremium.onSurface,
                            ),
                          ),
                          if (dotColors.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: dotColors.take(3).map((c) => Container(
                                width: 5, height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(color: isSelected ? Colors.white : c, shape: BoxShape.circle),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSelectedDayHeader(String key) {
    final events = _eventsByDay[key] ?? [];
    final parts = key.split('-');
    final dayNum = parts.length == 3 ? int.tryParse(parts[2]) ?? 0 : 0;
    final monthNum = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final meses = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    return Row(children: [
      Text('$dayNum de ${monthNum > 0 && monthNum <= 12 ? meses[monthNum] : ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: ThemeCleanPremium.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text('${events.length} escala(s)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primary)),
      ),
    ]);
  }

  Widget _buildEventCard(QueryDocumentSnapshot<Map<String, dynamic>> doc, DateTime now) {
    return _ScaleEventCard(
      doc: doc,
      now: now,
      cpfDigits: _cpfDigits,
      deptColors: _deptColors,
      onConfirm: (d, status, [motivo]) => _confirmPresence(d, status, motivo),
      onRequestSwap: _cpfDigits.length == 11
          ? () => _abrirPedidoTroca(context, doc)
          : null,
    );
  }
}

/// Card de uma frente de escala (reutilizado na lista detalhada).
class _ScaleEventCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final DateTime now;
  final String cpfDigits;
  final List<Color> deptColors;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm;
  final VoidCallback? onRequestSwap;

  const _ScaleEventCard({
    required this.doc,
    required this.now,
    required this.cpfDigits,
    required this.deptColors,
    required this.onConfirm,
    this.onRequestSwap,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final title = (m['title'] ?? '').toString();
    final dept = (m['departmentName'] ?? '').toString();
    final time = (m['time'] ?? '').toString();
    final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};
    String myStatus = (confirmations[cpfDigits] ?? '').toString();
    if (myStatus.isEmpty && cpfs.contains(cpfDigits)) {
      for (final k in confirmations.keys) {
        if ((k ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '') == cpfDigits.replaceAll(RegExp(r'[^0-9]'), '')) {
          myStatus = (confirmations[k] ?? '').toString();
          break;
        }
      }
    }
    final unavailabilityReasons = (m['unavailabilityReasons'] as Map<String, dynamic>?) ?? {};
    String? myReason;
    for (final k in unavailabilityReasons.keys) {
      if ((k ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '') == cpfDigits.replaceAll(RegExp(r'[^0-9]'), '')) {
        final v = unavailabilityReasons[k];
        if (v is Map && v['reason'] != null) myReason = v['reason'].toString();
        break;
      }
    }
    final deptId = (m['departmentId'] ?? '').toString();
    final color = deptColors[deptId.hashCode.abs() % deptColors.length];
    DateTime? dt;
    try { dt = (m['date'] as Timestamp).toDate(); } catch (_) {}
    final isFuture = dt != null && dt.isAfter(now.subtract(const Duration(hours: 12)));
    final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 5, height: 140, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    if (time.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                      ),
                  ]),
                  if (dept.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(dept, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
                  ],
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(names.length.clamp(0, 6), (i) {
                        final n = i < names.length ? names[i] : '';
                        final c = i < cpfs.length ? cpfs[i] : '';
                        final conf = (confirmations[c] ?? '').toString();
                        Color bg;
                        if (conf == 'confirmado') { bg = ThemeCleanPremium.success; }
                        else if (conf == 'indisponivel') { bg = ThemeCleanPremium.error; }
                        else if (conf == 'falta_nao_justificada') { bg = const Color(0xFFB91C1C); }
                        else { bg = Colors.grey.shade400; }
                        return Tooltip(
                          message: '$n (${conf.isEmpty ? 'pendente' : conf})',
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: bg.withOpacity(0.2),
                            child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: bg)),
                          ),
                        );
                      }),
                    ),
                  ],
                  if (isFuture && cpfDigits.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Confirmar',
                          icon: Icons.check_circle_rounded,
                          color: ThemeCleanPremium.success,
                          active: myStatus == 'confirmado',
                          onTap: () async {
                            await onConfirm(doc, myStatus == 'confirmado' ? '' : 'confirmado');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Indisponível',
                          icon: Icons.cancel_rounded,
                          color: ThemeCleanPremium.error,
                          active: myStatus == 'indisponivel',
                          onTap: () async {
                            if (myStatus == 'indisponivel') {
                              await onConfirm(doc, '');
                              return;
                            }
                            final reason = await showDialog<String>(
                              context: context,
                              builder: (ctx) {
                                final ctrl = TextEditingController();
                                return AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.cancel_rounded, color: ThemeCleanPremium.error),
                                      SizedBox(width: 10),
                                      Text('Indisponível', style: TextStyle(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Informe o motivo (o gestor verá esta justificativa):', style: TextStyle(fontSize: 14)),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: ctrl,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: viagem, saúde, compromisso...',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                          filled: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                                      style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
                                      child: const Text('Enviar'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (reason != null) await onConfirm(doc, 'indisponivel', reason.isNotEmpty ? reason : null);
                          },
                        ),
                      ),
                    ]),
                    if (onRequestSwap != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onRequestSwap,
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Solicitar troca'),
                        ),
                      ),
                    ],
                  ] else if (myStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (myStatus == 'confirmado' ? ThemeCleanPremium.success : ThemeCleanPremium.error).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            myStatus == 'confirmado' ? 'Você confirmou presença' : 'Você marcou indisponível',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: myStatus == 'confirmado' ? ThemeCleanPremium.success : ThemeCleanPremium.error),
                          ),
                          if (myStatus == 'indisponivel' && (myReason ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Motivo: ${myReason!.trim()}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Página de lista detalhada: dias e frentes de escala ao clicar em Este mês / Próximas / Confirmadas.
class _MinhaEscalaListaPage extends StatefulWidget {
  final String titulo;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final DateTime now;
  final String cpfDigits;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm;
  final VoidCallback onPop;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? onRequestSwap;

  const _MinhaEscalaListaPage({
    required this.titulo,
    required this.docs,
    required this.now,
    required this.cpfDigits,
    required this.onConfirm,
    required this.onPop,
    this.onRequestSwap,
  });

  @override
  State<_MinhaEscalaListaPage> createState() => _MinhaEscalaListaPageState();
}

class _MinhaEscalaListaPageState extends State<_MinhaEscalaListaPage> {
  static const _deptColors = [
    Color(0xFF3B82F6), Color(0xFF16A34A), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF8B5CF6), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF059669),
  ];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _sortedDocs {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(widget.docs);
    list.sort((a, b) {
      DateTime? da;
      DateTime? db;
      try { da = (a.data()['date'] as Timestamp).toDate(); } catch (_) {}
      try { db = (b.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (da == null || db == null) return 0;
      int c = da.compareTo(db);
      if (c != 0) return c;
      final ta = (a.data()['time'] ?? '').toString();
      final tb = (b.data()['time'] ?? '').toString();
      return ta.compareTo(tb);
    });
    return list;
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> get _byDay {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in _sortedDocs) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(d);
    }
    return map;
  }

  Future<void> _confirm(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) async {
    await widget.onConfirm(doc, status, motivo);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    final days = byDay.keys.toList()..sort();

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            widget.onPop();
            Navigator.pop(context);
          },
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: Text(widget.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: widget.docs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_available_rounded, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('Nenhuma escala nesta lista.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                ],
              ),
            )
          : ListView.builder(
              padding: ThemeCleanPremium.pagePadding(context),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final key = days[i];
                final parts = key.split('-');
                final year = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
                final month = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;
                final day = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
                final date = DateTime(year, month, day);
                final labelRaw = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(date);
                final label = labelRaw.isNotEmpty ? '${labelRaw[0].toUpperCase()}${labelRaw.substring(1)}' : labelRaw;
                final events = byDay[key]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: i == 0 ? 8 : 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        border: Border.all(color: ThemeCleanPremium.primary.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 20, color: ThemeCleanPremium.primary),
                          const SizedBox(width: 10),
                          Text(
                            label,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${events.length} frente(s)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ThemeCleanPremium.primary)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...events.map((doc) => _ScaleEventCard(
                      doc: doc,
                      now: widget.now,
                      cpfDigits: widget.cpfDigits,
                      deptColors: _deptColors,
                      onConfirm: _confirm,
                      onRequestSwap: widget.onRequestSwap != null
                          ? () => widget.onRequestSwap!(doc)
                          : null,
                    )),
                  ],
                );
              },
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
      ]),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: child,
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ConfirmButton({required this.label, required this.icon, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : color.withOpacity(0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: active ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : color)),
          ]),
        ),
      ),
    );
  }
}
