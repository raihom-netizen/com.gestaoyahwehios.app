import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:gestao_yahweh/services/member_schedule_availability_service.dart';
import 'package:gestao_yahweh/services/schedule_intel_validators.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/department_member_integration_service.dart';
import 'package:gestao_yahweh/services/church_departments_bootstrap.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart' show StableChurchLogo;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, churchTenantLogoUrl, imageUrlFromMap, isValidImageUrl, memCacheExtentForLogicalSize;
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show
        churchDepartmentNameFromDoc,
        dedupeChurchDepartmentDocuments,
        prettifyChurchDepartmentDisplayName;
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Map<String, dynamic> _remapScheduleCpfKeyedMap(
  Map<String, dynamic> old,
  List<String> newCpfs,
) {
  String norm(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  final out = <String, dynamic>{};
  for (final newCpf in newCpfs) {
    for (final e in old.entries) {
      if (norm(e.key.toString()) == norm(newCpf)) {
        out[newCpf] = e.value;
        break;
      }
    }
  }
  return out;
}

class SchedulesPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cpf;
  const SchedulesPage({super.key, required this.tenantId, required this.role, required this.cpf});

  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<SchedulesPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  /// ID real da igreja (resolve slug/alias) — alinhado a Membros/claims para escrita no Firestore.
  late final Future<String> _effectiveTidFuture;
  late Future<List<_DeptItem>> _deptsFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _templatesFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _instancesFuture;
  late Future<DocumentSnapshot<Map<String, dynamic>>> _tenantFuture;
  String _filterDeptId = '';
  String _reportDeptId = ''; // filtro de departamento no relatório
  String _periodFilter = 'mes_atual'; // diario, semanal, mes_anterior, mes_atual, anual, periodo
  DateTime? _periodStart;
  DateTime? _periodEnd;
  /// Lista (0) ou calendário interativo (1) na aba “Escalas Geradas”.
  int _instancesViewSegment = 0;
  DateTime _schedCalFocused = DateTime.now();
  DateTime? _schedCalSelected;

  /// Pastoral / gestão / papel global com escala geral.
  bool get _canWriteFull => AppPermissions.canEditSchedules(widget.role);

  /// Inclui líder ou vice-líder de departamento (CPF no doc do grupo), mesmo com papel [membro].
  bool get _canWrite => _canWriteFull || _managedDeptIds.isNotEmpty;

  /// Só pode agir nos departamentos em [_managedDeptIds].
  bool get _scopedDeptLeader => !_canWriteFull && _managedDeptIds.isNotEmpty;

  final Set<String> _managedDeptIds = {};

  DocumentReference<Map<String, dynamic>> _churchDoc(String tid) => FirebaseFirestore.instance.collection('igrejas').doc(tid);
  CollectionReference<Map<String, dynamic>> _templatesCol(String tid) => _churchDoc(tid).collection('escala_templates');
  CollectionReference<Map<String, dynamic>> _instancesCol(String tid) => _churchDoc(tid).collection('escalas');
  CollectionReference<Map<String, dynamic>> _departmentsCol(String tid) => _churchDoc(tid).collection('departamentos');
  CollectionReference<Map<String, dynamic>> _membersCol(String tid) => _churchDoc(tid).collection('membros');

  static const _deptColors = [
    Color(0xFF3B82F6), Color(0xFF16A34A), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF8B5CF6), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF059669),
  ];

  Color _colorForDept(int index) => _deptColors[index % _deptColors.length];

  Future<String> _resolveTenantAndSeedPresets() async {
    final tid = await TenantResolverService.resolveEffectiveTenantId(
        widget.tenantId);
    if (AppPermissions.canEditDepartments(widget.role)) {
      await ChurchDepartmentsBootstrap.ensureMissingPresetDocuments(
        _departmentsCol(tid),
        refreshToken: true,
      );
    }
    return tid;
  }

  Future<List<_DeptItem>> _loadDepartmentsForTenant(String tid) async {
    // Sem orderBy('name') no Firestore: docs sem campo [name] ficam de fora da query e a lista “some”.
    final snap = await _departmentsCol(tid).get();
    final deduped = dedupeChurchDepartmentDocuments(snap.docs);
    final list = deduped
        .map(
          (d) => _DeptItem(
            id: d.id,
            name: prettifyChurchDepartmentDisplayName(
              churchDepartmentNameFromDoc(d),
            ),
            leaderCpf: (d.data()['leaderCpf'] ?? '').toString(),
          ),
        )
        .where((d) => d.name.isNotEmpty)
        .toList();
    list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchInstancesForEffectiveTenant() =>
      _effectiveTidFuture.then((tid) => _instancesCol(tid).orderBy('date', descending: true).limit(500).get());

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  static DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0, 23, 59, 59);
  static DateTime _startOfYear(DateTime d) => DateTime(d.year, 1, 1);
  static DateTime _endOfYear(DateTime d) => DateTime(d.year, 12, 31, 23, 59, 59);

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterInstancesByPeriod(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();
    bool inRange(DateTime? dt) {
      if (dt == null) return false;
      switch (_periodFilter) {
        case 'diario':
          final today = _startOfDay(now);
          return !dt.isBefore(today) && !dt.isAfter(_endOfDay(now));
        case 'semanal':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return !dt.isBefore(_startOfDay(weekStart)) && !dt.isAfter(_endOfDay(now));
        case 'mes_anterior':
          final prev = DateTime(now.year, now.month - 1);
          return !dt.isBefore(_startOfMonth(prev)) && !dt.isAfter(_endOfMonth(prev));
        case 'mes_atual':
          return !dt.isBefore(_startOfMonth(now)) && !dt.isAfter(_endOfMonth(now));
        case 'anual':
          return !dt.isBefore(_startOfYear(now)) && !dt.isAfter(_endOfYear(now));
        case 'periodo':
          if (_periodStart != null && _periodEnd != null) {
            return !dt.isBefore(_startOfDay(_periodStart!)) && !dt.isAfter(_endOfDay(_periodEnd!));
          }
          return true;
        default:
          return true;
      }
    }
    return docs.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp?)?.toDate(); } catch (_) {}
      return inRange(dt);
    }).toList();
  }

  void _refreshTemplates() {
    setState(() {
      _templatesFuture = _effectiveTidFuture.then((tid) => _templatesCol(tid).orderBy('title').get());
    });
  }

  void _refreshInstances() {
    setState(() {
      _instancesFuture = _fetchInstancesForEffectiveTenant();
    });
  }

  Future<void> _notifySchedulePublished(String scheduleId) async {
    try {
      final tid = await _effectiveTidFuture;
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('notifySchedulePublished');
      final res = await fn.call(<String, dynamic>{
        'tenantId': tid,
        'scheduleId': scheduleId,
      });
      final n = (res.data is Map && (res.data as Map)['count'] != null)
          ? (res.data as Map)['count']
          : 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Notificações enviadas ($n envio(s) FCM).',
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao notificar: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao notificar: $e')),
        );
      }
    }
  }

  Future<void> _resolverTrocaEscala({
    required bool aprovar,
    required QueryDocumentSnapshot<Map<String, dynamic>> troca,
  }) async {
    final pathParts = troca.reference.path.split('/');
    if (pathParts.length < 4 || pathParts[0] != 'igrejas') return;
    final tid = pathParts[1];
    final td = troca.data();
    final escalaId = (td['escalaId'] ?? '').toString();
    final sol = (td['solicitanteCpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final alvo = (td['alvoCpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (escalaId.isEmpty || sol.length != 11 || alvo.length != 11) return;

    if (!aprovar) {
      try {
        await troca.reference.update({
          'status': 'recusada',
          'resolvedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Pedido de troca recusado.'),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
        }
      }
      return;
    }

    try {
      final escRef =
          FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('escalas').doc(escalaId);
      final escSnap = await escRef.get();
      if (!escSnap.exists) return;
      final ed = escSnap.data() ?? {};
      final cpfs = ((ed['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
      final names = ((ed['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
      int idx = -1;
      for (var i = 0; i < cpfs.length; i++) {
        if (cpfs[i].replaceAll(RegExp(r'\D'), '') == sol) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Solicitante não está mais nesta escala.')),
          );
        }
        return;
      }

      String alvoNome = alvo;
      try {
        final mSnap = await _membersCol(tid).doc(alvo).get();
        if (mSnap.exists) {
          final md = mSnap.data() ?? {};
          alvoNome = (md['NOME_COMPLETO'] ?? md['nome'] ?? alvo).toString().trim();
        } else {
          final q = await _membersCol(tid).where('CPF', isEqualTo: alvo).limit(1).get();
          if (q.docs.isNotEmpty) {
            final md = q.docs.first.data();
            alvoNome = (md['NOME_COMPLETO'] ?? md['nome'] ?? alvo).toString().trim();
          }
        }
      } catch (_) {}

      final newCpfs = List<String>.from(cpfs);
      final newNames = List<String>.from(names);
      newCpfs[idx] = alvo;
      if (idx < newNames.length) {
        newNames[idx] = alvoNome;
      } else {
        while (newNames.length < newCpfs.length) {
          newNames.add('');
        }
        newNames[idx] = alvoNome;
      }

      final oldConf = Map<String, dynamic>.from((ed['confirmations'] as Map?) ?? {});
      final oldUnav = Map<String, dynamic>.from((ed['unavailabilityReasons'] as Map?) ?? {});
      oldConf.remove(cpfs[idx]);
      oldUnav.remove(cpfs[idx]);
      final remappedConf = _remapScheduleCpfKeyedMap(oldConf, newCpfs);
      final remappedUnav = _remapScheduleCpfKeyedMap(oldUnav, newCpfs);

      await escRef.update({
        'memberCpfs': newCpfs,
        'memberNames': newNames,
        'confirmations': remappedConf,
        'unavailabilityReasons': remappedUnav,
        'updatedAt': Timestamp.now(),
      });
      await troca.reference.update({
        'status': 'aprovada',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _refreshInstances();
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Troca aprovada. Escala atualizada.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _tab = TabController(length: 3, vsync: this);
    _effectiveTidFuture = _resolveTenantAndSeedPresets();
    _deptsFuture = _effectiveTidFuture.then(_loadDepartmentsForTenant);
    _templatesFuture = _effectiveTidFuture.then((tid) => _templatesCol(tid).orderBy('title').get());
    _instancesFuture = _fetchInstancesForEffectiveTenant();
    _tenantFuture = _effectiveTidFuture.then((tid) => _churchDoc(tid).get());
    _effectiveTidFuture.then((tid) async {
      try {
        final s = await DepartmentMemberIntegrationService.managedDepartmentIdsForCpf(
          tenantId: tid,
          cpfDigits: widget.cpf.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (mounted) setState(() => _managedDeptIds
          ..clear()
          ..addAll(s));
      } catch (_) {}
    });
  }

  String get _periodLabelUppercase {
    switch (_periodFilter) {
      case 'diario': return 'DIÁRIO';
      case 'semanal': return 'SEMANAL';
      case 'mes_anterior': return 'MÊS ANTERIOR';
      case 'mes_atual': return 'MÊS ATUAL';
      case 'anual': return 'ANUAL';
      case 'periodo': return 'PERÍODO';
      default: return 'PERÍODO';
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Criar/Editar modelo de escala ──────────────────────────────────────────
  Future<void> _editTemplate({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    final tid = await _effectiveTidFuture;
    final depts = await _deptsFuture;
    final data = doc?.data() ?? {};
    final deptsForForm = _canWriteFull
        ? depts
        : depts.where((d) => _managedDeptIds.contains(d.id)).toList();
    if (!_canWriteFull && deptsForForm.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Seu CPF não está como líder/vice em nenhum departamento.'),
        );
      }
      return;
    }
    final tplDept = (data['departmentId'] ?? '').toString();
    if (!_canWriteFull &&
        doc != null &&
        tplDept.isNotEmpty &&
        !_managedDeptIds.contains(tplDept)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Você só pode editar modelos do seu departamento.'),
        );
      }
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _TemplateFormPage(
          tenantId: tid,
          doc: doc,
          data: data,
          depts: deptsForForm,
          templatesCol: _templatesCol(tid),
          membersCol: _membersCol(tid),
          membersColIgrejas: _membersCol(tid),
          instancesCol: _instancesCol(tid),
        ),
      ),
    );
    if (result == true && mounted) {
      _refreshTemplates();
      _refreshInstances();
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Escala salva.'));
    }
  }

  // ── Gerar escalas futuras com rodízio inteligente ──────────────────────────
  Future<void> _generate(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final tplDept = (doc.data()?['departmentId'] ?? '').toString();
    if (!_canWriteFull &&
        tplDept.isNotEmpty &&
        !_managedDeptIds.contains(tplDept)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Apenas líderes do departamento podem gerar esta escala.'),
        );
      }
      return;
    }
    final daysCtrl = TextEditingController(text: '30');
    final membersPerDay = TextEditingController(text: '5');
    var replicateMonth = false;
    var monthOffset = 0; // 0 = mês atual, 1 = próximo mês
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: const Text('Gerar escalas futuras', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir no mês inteiro'),
                  subtitle: const Text('Gera todas as ocorrências do mesmo dia da semana (ex.: todos os domingos). Exige dia da semana no modelo.'),
                  value: replicateMonth,
                  onChanged: (v) => setD(() => replicateMonth = v),
                ),
                if (replicateMonth) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: monthOffset,
                    decoration: const InputDecoration(
                      labelText: 'Mês alvo',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Mês atual')),
                      DropdownMenuItem(value: 1, child: Text('Próximo mês')),
                    ],
                    onChanged: (v) => setD(() => monthOffset = v ?? 0),
                  ),
                ] else ...[
                  TextField(
                      controller: daysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Próximos X dias',
                          prefixIcon: Icon(Icons.date_range_rounded))),
                ],
                const SizedBox(height: 12),
                TextField(
                    controller: membersPerDay,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Membros por escala',
                        prefixIcon: Icon(Icons.people_rounded))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade200)),
                  child: Row(children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.amber.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Rodízio: quem serviu menos vezes entra primeiro. Periodicidade do modelo: diária, semanal ou mensal.',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900))),
                  ]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gerar')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final tid = await _effectiveTidFuture;
    final instances = _instancesCol(tid);

    final tplData = doc.data() ?? {};
    final title = (tplData['title'] ?? '').toString();
    final rec = (tplData['recurrence'] ?? 'weekly').toString();
    final day = (tplData['day'] ?? '').toString();
    final time = (tplData['time'] ?? '19:00').toString();
    final deptId = (tplData['departmentId'] ?? '').toString();
    final deptName = (tplData['departmentName'] ?? '').toString();
    final allCpfs = ((tplData['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final allNames = ((tplData['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    final perDay = int.tryParse(membersPerDay.text.trim()) ?? allCpfs.length;

    final daysAhead = int.tryParse(daysCtrl.text.trim()) ?? 30;
    final now = DateTime.now();
    final until = now.add(Duration(days: daysAhead));
    final tp = time.split(':');
    final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
    final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 0;

    int? weekday;
    final dlow = day.toLowerCase();
    if (dlow.contains('seg')) weekday = 1;
    if (dlow.contains('ter')) weekday = 2;
    if (dlow.contains('qua')) weekday = 3;
    if (dlow.contains('qui')) weekday = 4;
    if (dlow.contains('sex')) weekday = 5;
    if (dlow.contains('sáb') || dlow.contains('sab')) weekday = 6;
    if (dlow.contains('dom')) weekday = 7;

    DateTime cursor = DateTime(now.year, now.month, now.day);
    if (weekday != null) {
      while (cursor.weekday != weekday) cursor = cursor.add(const Duration(days: 1));
    }

    // Rodízio: busca frequência recente por CPF (filtro por departamento em memória para evitar índice composto)
    final recentSnap = await instances.orderBy('date', descending: true).limit(300).get();
    final freq = <String, int>{};
    for (final esc in recentSnap.docs) {
      if ((esc.data()['departmentId'] ?? '').toString() != deptId) continue;
      final cpfs = ((esc.data()['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
      for (final c in cpfs) freq[c] = (freq[c] ?? 0) + 1;
    }

    final dates = <DateTime>[];
    if (replicateMonth) {
      if (weekday == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Defina o dia da semana no modelo (ex.: Domingo) para repetir no mês.'),
            ),
          );
        }
        return;
      }
      final targetMonth = DateTime(now.year, now.month + monthOffset, 1);
      final monthEnd = DateTime(targetMonth.year, targetMonth.month + 1, 0);
      var c = DateTime(targetMonth.year, targetMonth.month, 1);
      while (c.weekday != weekday && c.month == targetMonth.month) {
        c = c.add(const Duration(days: 1));
      }
      if (c.month != targetMonth.month) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível localizar o dia da semana no mês escolhido.')),
          );
        }
        return;
      }
      while (!c.isAfter(monthEnd)) {
        dates.add(DateTime(c.year, c.month, c.day, hh, mm));
        c = c.add(const Duration(days: 7));
      }
    } else {
      while (cursor.isBefore(until) || cursor.isAtSameMomentAs(until)) {
        dates.add(DateTime(cursor.year, cursor.month, cursor.day, hh, mm));
        if (rec == 'daily') {
          cursor = cursor.add(const Duration(days: 1));
        } else if (rec == 'monthly') {
          cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
        } else if (rec == 'yearly') {
          cursor = DateTime(cursor.year + 1, cursor.month, cursor.day);
        } else {
          cursor = cursor.add(const Duration(days: 7));
        }
      }
    }

    final membersForYmds = await _membersCol(tid).get();
    final unavailableByCpfNorm = <String, List<String>>{};
    for (final md in membersForYmds.docs) {
      final d = md.data();
      final c =
          (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (c.length != 11) continue;
      unavailableByCpfNorm[c] = MemberScheduleAvailability.parseYmdList(
        d[MemberScheduleAvailability.fieldYmds],
      );
    }

    final uniqueDays = <DateTime>{};
    for (final dt in dates) {
      uniqueDays.add(DateTime(dt.year, dt.month, dt.day));
    }
    final busyOtherByDayKey = <String, Set<String>>{};
    for (final day in uniqueDays) {
      final k = ScheduleIntelValidators.ymdKey(day);
      busyOtherByDayKey[k] = await ScheduleIntelValidators.otherDeptBusyNormCpfs(
        instancesCol: instances,
        calendarDay: day,
        slotTime: time,
        currentDepartmentId: deptId,
      );
    }

    final batch = FirebaseFirestore.instance.batch();
    final tsNow = Timestamp.now();
    var skippedNoEligible = 0;
    for (final dt in dates) {
      final dayKey = ScheduleIntelValidators.ymdKey(DateTime(dt.year, dt.month, dt.day));
      final busyOther = busyOtherByDayKey[dayKey] ?? {};
      int genScore(int idx) {
        final c = allCpfs[idx];
        final norm = c.replaceAll(RegExp(r'[^0-9]'), '');
        final dayOnly = DateTime(dt.year, dt.month, dt.day);
        final ymds = unavailableByCpfNorm[norm] ?? const <String>[];
        final blocked =
            MemberScheduleAvailability.isUnavailableOn(ymds, dayOnly);
        final f = freq[c] ?? 0;
        var s = (blocked ? 1000000 : 0) + f;
        if (busyOther.contains(norm)) {
          s += 2000000;
        }
        return s;
      }

      // Rodízio: menor frequência primeiro; indisponível ou conflito com outro dept no mesmo horário ficam de fora.
      final sorted = List<int>.generate(allCpfs.length, (i) => i)
        ..sort((a, b) => genScore(a).compareTo(genScore(b)));
      final cap = perDay.clamp(1, allCpfs.length);
      final eligible = sorted.where((i) => genScore(i) < 1000000).take(cap).toList();
      if (eligible.isEmpty) {
        skippedNoEligible++;
        continue;
      }
      final selCpfs = eligible.map((i) => allCpfs[i]).toList();
      final selNames = eligible.map((i) => i < allNames.length ? allNames[i] : '').toList();

      for (final c in selCpfs) freq[c] = (freq[c] ?? 0) + 1;

      final ref = instances.doc();
      batch.set(ref, {
        'title': title,
        'date': Timestamp.fromDate(dt),
        'time': time,
        'departmentId': deptId,
        'departmentName': deptName,
        'memberCpfs': selCpfs,
        'memberNames': selNames,
        'confirmations': {},
        'templateId': doc.id,
        'observations': '',
        'createdAt': tsNow,
        'updatedAt': tsNow,
        'active': true,
      });
    }
    await batch.commit();
    if (mounted) {
      _refreshInstances();
      final genCount = dates.length - skippedNoEligible;
      var msg = '$genCount escala(s) gerada(s) com rodízio e checagem de conflito/ausência.';
      if (skippedNoEligible > 0) {
        msg += ' $skippedNoEligible data(s) ignorada(s): nenhum voluntário elegível (ausência ou outro ministério no mesmo horário).';
      }
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar(msg));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        title: const Text('Escalas'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: ThemeCleanPremium.navSidebarAccent,
          tabs: const [Tab(text: 'Modelos'), Tab(text: 'Escalas Geradas'), Tab(text: 'Relatórios')],
        ),
        actions: [
          if (_canWrite)
            IconButton(
              tooltip: 'Nova escala',
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add_circle_outline),
              style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
            ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nova Escala'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Material(
                color: ThemeCleanPremium.primary,
                child: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: ThemeCleanPremium.navSidebarAccent,
                  tabs: const [Tab(text: 'Modelos'), Tab(text: 'Escalas Geradas'), Tab(text: 'Relatórios')],
                ),
              ),
            Expanded(
        child: TabBarView(
        controller: _tab,
        children: [
                  _buildTemplatesTab(),
                  _buildInstancesTab(),
                  _buildReportsTab(),
        ],
      ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab: Modelos ───────────────────────────────────────────────────────────
  Widget _buildTemplatesTab() {
    return FutureBuilder<List<_DeptItem>>(
      future: _deptsFuture,
      builder: (context, deptSnap) {
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _templatesFuture,
                builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChurchPanelErrorBody(
                      title: 'Não foi possível carregar os modelos de escala',
                      error: snap.error,
                      onRetry: _refreshTemplates,
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
                  return const ChurchPanelLoadingBody();
                }
                var docs = snap.data?.docs ?? [];
                if (_canWriteFull) {
                  // todos os modelos
                } else if (_scopedDeptLeader) {
                  docs = docs
                      .where((d) => _managedDeptIds
                          .contains((d.data()['departmentId'] ?? '').toString()))
                      .toList();
                } else {
                  docs = [];
                }
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.event_note_rounded, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Nenhum modelo de escala.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                      if (_canWrite) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: () => _editTemplate(), icon: const Icon(Icons.add_rounded), label: const Text('Criar modelo')),
                      ],
                    ]),
                  );
                }
                final allDepts = deptSnap.data ?? [];
                  return RefreshIndicator(
                  onRefresh: () async => _refreshTemplates(),
                  child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final tplDeptId =
                        (docs[i].data()['departmentId'] ?? '').toString();
                    final canTpl = _canWriteFull ||
                        _managedDeptIds.contains(tplDeptId);
                    return _TemplateCard(
                    doc: docs[i],
                    deptColor: _colorForDept(allDepts.indexWhere((d) => d.id == (docs[i].data()['departmentId'] ?? '')).clamp(0, 99)),
                    canWrite: canTpl,
                    onEdit: () => _editTemplate(doc: docs[i]),
                    onGenerate: () => _generate(docs[i]),
                    onDelete: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Excluir modelo?'),
                          content: const Text('Escalas já geradas não serão afetadas.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error), child: const Text('Excluir')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await docs[i].reference.delete();
                        if (mounted) _refreshTemplates();
                      }
                    },
                  );
                  },
                ),
              );
            },
          );
        },
    );
  }

  // ── Tab: Escalas Geradas ───────────────────────────────────────────────────
  Widget _buildInstancesTab() {
    return FutureBuilder<List<_DeptItem>>(
      future: _deptsFuture,
      builder: (context, deptSnap) {
        final allDepts = deptSnap.data ?? [];
        return Column(
          children: [
            if (allDepts.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _FilterChipDept(label: 'Todos', selected: _filterDeptId.isEmpty, onTap: () => setState(() { _filterDeptId = ''; _instancesFuture = _fetchInstancesForEffectiveTenant(); })),
                  for (var i = 0; i < allDepts.length; i++) ...[
                    const SizedBox(width: 8),
                    _FilterChipDept(
                      label: allDepts[i].name,
                      selected: _filterDeptId == allDepts[i].id,
                      color: _colorForDept(i),
                      onTap: () => setState(() { _filterDeptId = _filterDeptId == allDepts[i].id ? '' : allDepts[i].id; _instancesFuture = _fetchInstancesForEffectiveTenant(); }),
                    ),
                  ],
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text('Período:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChipDept(label: 'Diário', selected: _periodFilter == 'diario', onTap: () => setState(() => _periodFilter = 'diario')),
                          const SizedBox(width: 6),
                          _FilterChipDept(label: 'Semanal', selected: _periodFilter == 'semanal', onTap: () => setState(() => _periodFilter = 'semanal')),
                          const SizedBox(width: 6),
                          _FilterChipDept(label: 'Mês ant.', selected: _periodFilter == 'mes_anterior', onTap: () => setState(() => _periodFilter = 'mes_anterior')),
                          const SizedBox(width: 6),
                          _FilterChipDept(label: 'Mês atual', selected: _periodFilter == 'mes_atual', onTap: () => setState(() => _periodFilter = 'mes_atual')),
                          const SizedBox(width: 6),
                          _FilterChipDept(label: 'Anual', selected: _periodFilter == 'anual', onTap: () => setState(() => _periodFilter = 'anual')),
                          const SizedBox(width: 6),
                          _FilterChipDept(label: 'Período', selected: _periodFilter == 'periodo', onTap: () async {
                            final start = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (start == null || !mounted) return;
                            final end = await showDatePicker(context: context, initialDate: start, firstDate: start, lastDate: DateTime(2030));
                            if (mounted && end != null) setState(() { _periodFilter = 'periodo'; _periodStart = start; _periodEnd = end; });
                          }),
                        ],
                      ),
                    ),
                  ),
                  if (_canWrite) ...[
                    IconButton(
                      tooltip: 'PDF período atual',
                      onPressed: () => _exportEscalasPdf(allDepts),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'PDF semanal geral (todos os deptos)',
                      onPressed: () => _exportWeeklyChurchPdf(allDepts),
                      icon: const Icon(Icons.calendar_view_week_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_periodFilter == 'periodo' && (_periodStart != null || _periodEnd != null))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _periodStart != null && _periodEnd != null
                      ? '${_periodStart!.day}/${_periodStart!.month}/${_periodStart!.year} a ${_periodEnd!.day}/${_periodEnd!.month}/${_periodEnd!.year}'
                      : 'Selecione início e fim',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Lista'), icon: Icon(Icons.view_list_rounded, size: 18)),
                    ButtonSegment(value: 1, label: Text('Calendário'), icon: Icon(Icons.calendar_month_rounded, size: 18)),
                  ],
                  selected: {_instancesViewSegment},
                  onSelectionChanged: (s) => setState(() {
                    _instancesViewSegment = s.first;
                    if (_schedCalSelected == null) _schedCalSelected = DateTime.now();
                  }),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _instancesFuture,
            builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: ChurchPanelErrorBody(
                        title: 'Não foi possível carregar as escalas',
                        error: snap.error,
                        onRetry: _refreshInstances,
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
                    return const ChurchPanelLoadingBody();
                  }
                  final allDocs = snap.data?.docs ?? [];
                  var deptFiltered = _filterDeptId.isEmpty
                      ? allDocs
                      : allDocs.where((d) => (d.data()['departmentId'] ?? '').toString() == _filterDeptId).toList();
                  if (_scopedDeptLeader) {
                    deptFiltered = deptFiltered
                        .where((d) => _managedDeptIds
                            .contains((d.data()['departmentId'] ?? '').toString()))
                        .toList();
                  }
                  final docs = _filterInstancesByPeriod(deptFiltered);
                  if (docs.isEmpty) {
                    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.calendar_today_rounded, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Nenhuma escala no período.', style: TextStyle(color: Colors.grey.shade600)),
                    ]));
                  }
                  if (_instancesViewSegment == 1) {
                    return RefreshIndicator(
                      onRefresh: () async => _refreshInstances(),
                      child: _SchedulesCalendarPanel(
                        docs: docs,
                        allDepts: allDepts,
                        focusedDay: _schedCalFocused,
                        selectedDay: _schedCalSelected ?? _schedCalFocused,
                        colorForDept: _colorForDept,
                        currentCpf: widget.cpf.replaceAll(RegExp(r'[^0-9]'), ''),
                        canWriteFull: _canWriteFull,
                        managedDeptIds: _managedDeptIds,
                        onDaySelected: (d, f) => setState(() {
                          _schedCalSelected = d;
                          _schedCalFocused = f;
                        }),
                        onCalendarPageChanged: (f) =>
                            setState(() => _schedCalFocused = f),
                        onOpenDetail: (d, color) => _showInstanceDetail(d, color),
                        onEdit: _editInstance,
                        onDelete: _deleteInstance,
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refreshInstances(),
                    child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                      final deptIdx = allDepts.indexWhere((d) => d.id == (docs[i].data()['departmentId'] ?? ''));
                      final deptIdInst =
                          (docs[i].data()['departmentId'] ?? '').toString();
                      final canMutate =
                          _canWriteFull || _managedDeptIds.contains(deptIdInst);
                      return _InstanceCard(
                        doc: docs[i],
                        deptColor: _colorForDept(deptIdx.clamp(0, 99)),
                        currentCpf: widget.cpf.replaceAll(RegExp(r'[^0-9]'), ''),
                        canWrite: canMutate,
                        onTap: () => _showInstanceDetail(docs[i], _colorForDept(deptIdx.clamp(0, 99))),
                        onEdit: canMutate ? () => _editInstance(docs[i]) : null,
                        onDelete: canMutate ? () => _deleteInstance(docs[i]) : null,
                      );
                    },
                  ),
                );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab: Relatórios super premium (igreja, título CAIXA ALTA, gráficos, drill-down) ──
  Widget _buildReportsTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_instancesFuture, _tenantFuture, _deptsFuture]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allDocs = (snap.data![0] as QuerySnapshot<Map<String, dynamic>>).docs;
        var docs = _filterInstancesByPeriod(allDocs);
        final tenantSnap = snap.data![1] as DocumentSnapshot<Map<String, dynamic>>;
        final tenantData = tenantSnap.data();
        final depts = snap.data![2] as List<_DeptItem>;
        if (_reportDeptId.isNotEmpty) {
          docs = docs.where((d) => (d.data()['departmentId'] ?? '').toString() == _reportDeptId).toList();
        }
        final deptMatch = depts.where((e) => e.id == _reportDeptId);
        final deptName = _reportDeptId.isEmpty ? 'TODOS' : (deptMatch.isEmpty ? _reportDeptId : deptMatch.first.name.toUpperCase());

        int totalPresencas = 0, totalFaltas = 0, escalasRealizadas = 0;
        final memberStats = <String, _MemberScaleStats>{};
        final whoMissed = <String, int>{}; // nome -> qtd faltas
        final whoAttended = <String, int>{}; // nome -> qtd presenças
        for (final d in docs) {
          final m = d.data();
          final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
          final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
          final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};
          bool allConfirmed = cpfs.isNotEmpty;
          for (var i = 0; i < cpfs.length; i++) {
            final cpf = cpfs[i];
            final name = i < names.length ? names[i] : cpf;
            memberStats.putIfAbsent(cpf, () => _MemberScaleStats(name: name, cpf: cpf));
            final st = memberStats[cpf]!;
            st.escalas++;
            final status = (confirmations[cpf] ?? '').toString();
            if (status == 'confirmado') {
              st.presencas++;
              totalPresencas++;
              whoAttended[name] = (whoAttended[name] ?? 0) + 1;
            } else {
              allConfirmed = false;
              if (status == 'indisponivel' || status == 'falta_nao_justificada') {
                st.faltas++;
                totalFaltas++;
                whoMissed[name] = (whoMissed[name] ?? 0) + 1;
              }
            }
          }
          if (allConfirmed && cpfs.isNotEmpty) escalasRealizadas++;
        }
        final escalasGeradas = docs.length;
        final escalasPendentes = escalasGeradas - escalasRealizadas;
        final list = memberStats.values.toList()..sort((a, b) => b.escalas.compareTo(a.escalas));

        final nomeIgreja = (tenantData?['name'] ?? tenantData?['nome'] ?? 'Igreja').toString();
        final endereco = (tenantData?['address'] ?? tenantData?['endereco'] ?? '').toString();
        final logoBox = 56.0;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final logoMem = memCacheExtentForLogicalSize(logoBox, dpr, maxPx: 512);

        return RefreshIndicator(
          onRefresh: () async => setState(() {
            _instancesFuture = _fetchInstancesForEffectiveTenant();
            _tenantFuture = _effectiveTidFuture.then((tid) => _churchDoc(tid).get());
          }),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceMd, ThemeCleanPremium.spaceMd, ThemeCleanPremium.spaceMd, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header igreja (premium) ──
                Container(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: const Color(0xFFF7F8FA),
                          child: SizedBox(
                            width: logoBox,
                            height: logoBox,
                            child: StableChurchLogo(
                              imageUrl: tenantData != null ? churchTenantLogoUrl(tenantData) : null,
                              storagePath: tenantData != null ? ChurchImageFields.logoStoragePath(tenantData) : null,
                              tenantId: tenantSnap.id,
                              tenantData: tenantData,
                              width: logoBox,
                              height: logoBox,
                              fit: BoxFit.contain,
                              memCacheWidth: logoMem,
                              memCacheHeight: logoMem,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nomeIgreja, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
                            if (endereco.isNotEmpty) ...[const SizedBox(height: 4), Text(endereco, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // ── Título relatório em CAIXA ALTA ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [ThemeCleanPremium.primary, ThemeCleanPremium.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: [BoxShadow(color: ThemeCleanPremium.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Text(
                    'ESCALA — DEPARTAMENTO $deptName — $_periodLabelUppercase',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                // ── Filtros ──
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text('Período:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                    _FilterChipDept(label: 'Diário', selected: _periodFilter == 'diario', onTap: () => setState(() => _periodFilter = 'diario')),
                    _FilterChipDept(label: 'Semanal', selected: _periodFilter == 'semanal', onTap: () => setState(() => _periodFilter = 'semanal')),
                    _FilterChipDept(label: 'Mês ant.', selected: _periodFilter == 'mes_anterior', onTap: () => setState(() => _periodFilter = 'mes_anterior')),
                    _FilterChipDept(label: 'Mês atual', selected: _periodFilter == 'mes_atual', onTap: () => setState(() => _periodFilter = 'mes_atual')),
                    _FilterChipDept(label: 'Anual', selected: _periodFilter == 'anual', onTap: () => setState(() => _periodFilter = 'anual')),
                    const SizedBox(width: 16),
                    Text('Depto:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                    _FilterChipDept(label: 'Todos', selected: _reportDeptId.isEmpty, onTap: () => setState(() => _reportDeptId = '')),
                    ...depts.map((e) => _FilterChipDept(label: e.name, selected: _reportDeptId == e.id, onTap: () => setState(() => _reportDeptId = e.id))),
                  ],
                ),
                const SizedBox(height: 24),
                // ── Gráfico de barras: métricas ──
                _ReportChartCard(
                  title: 'Visão geral',
                  child: SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: (([escalasGeradas, escalasRealizadas, escalasPendentes, totalPresencas, totalFaltas].reduce((a, b) => a > b ? a : b)).toDouble() * 1.2).clamp(4.0, double.infinity),
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) => Text(_barLabel(v.toInt()), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700)))),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, meta) => Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)))),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          _barGroup(0, escalasGeradas.toDouble(), ThemeCleanPremium.primary),
                          _barGroup(1, escalasRealizadas.toDouble(), ThemeCleanPremium.success),
                          _barGroup(2, escalasPendentes.toDouble(), Colors.amber.shade700),
                          _barGroup(3, totalPresencas.toDouble(), ThemeCleanPremium.success),
                          _barGroup(4, totalFaltas.toDouble(), ThemeCleanPremium.error),
                        ],
                      ),
                      swapAnimationDuration: const Duration(milliseconds: 250),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Cards clicáveis: drill-down ──
                Row(
                  children: [
                    Expanded(child: _ReportMetricCard(label: 'Escalas geradas', value: '$escalasGeradas', icon: Icons.calendar_month_rounded, color: ThemeCleanPremium.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _ReportMetricCard(label: 'Realizadas', value: '$escalasRealizadas', icon: Icons.check_circle_rounded, color: ThemeCleanPremium.success)),
                    const SizedBox(width: 10),
                    Expanded(child: _ReportMetricCard(label: 'Pendentes', value: '$escalasPendentes', icon: Icons.schedule_rounded, color: Colors.amber.shade700)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Presenças',
                        value: '$totalPresencas',
                        icon: Icons.person_rounded,
                        color: ThemeCleanPremium.success,
                        onTap: () => _showDrillDown(context, 'Quem cumpriu escala (presenças)', whoAttended.entries.map((e) => '${e.key}: ${e.value}').toList(), ThemeCleanPremium.success),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Faltas',
                        value: '$totalFaltas',
                        icon: Icons.cancel_rounded,
                        color: ThemeCleanPremium.error,
                        onTap: () => _showDrillDown(context, 'Quem faltou', whoMissed.entries.map((e) => '${e.key}: ${e.value}').toList(), ThemeCleanPremium.error),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // ── Por membro ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.people_rounded, size: 20, color: ThemeCleanPremium.primary),
                      const SizedBox(width: 8),
                      Text('Por membro', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd), boxShadow: ThemeCleanPremium.softUiCardShadow),
                    child: Column(children: [
                      Icon(Icons.assignment_rounded, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Nenhum dado no período.', style: TextStyle(color: Colors.grey.shade600)),
                    ]),
                  )
                else
                  ...list.map((st) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      shadowColor: Colors.black12,
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        onTap: () => _showDrillDown(context, st.name.isNotEmpty ? st.name : st.cpf, [
                          'Escalas: ${st.escalas}',
                          'Presenças: ${st.presencas}',
                          'Faltas: ${st.faltas}',
                        ], ThemeCleanPremium.primary),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(radius: 22, backgroundColor: ThemeCleanPremium.primary.withOpacity(0.1), child: Text((st.name.isNotEmpty ? st.name[0] : '?').toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: ThemeCleanPremium.primary, fontSize: 16))),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(st.name.isNotEmpty ? st.name : st.cpf, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _ReportChip(label: 'Escalas', value: st.escalas, color: ThemeCleanPremium.primary),
                                        const SizedBox(width: 8),
                                        _ReportChip(label: 'Presenças', value: st.presencas, color: ThemeCleanPremium.success),
                                        const SizedBox(width: 8),
                                        _ReportChip(label: 'Faltas', value: st.faltas, color: ThemeCleanPremium.error),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              ],
            ),
          ),
        );
      },
    );
  }

  String _barLabel(int i) {
    const l = ['Geradas', 'Realizadas', 'Pendentes', 'Presenças', 'Faltas'];
    return i >= 0 && i < l.length ? l[i] : '';
  }

  BarChartGroupData _barGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [BarChartRodData(toY: y.clamp(0.0, double.infinity), color: color, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))],
      showingTooltipIndicators: [],
    );
  }

  void _showDrillDown(BuildContext context, String title, List<String> lines, Color accent) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 16),
            if (lines.isEmpty) Text('Nenhum registro.', style: TextStyle(color: Colors.grey.shade600)) else ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line, style: const TextStyle(fontSize: 14)))),
          ],
        ),
      ),
    );
  }

  Future<void> _exportEscalasPdf(List<_DeptItem> allDepts) async {
    try {
      final snap = await _instancesFuture;
      final tenantSnap = await _tenantFuture;
      final docs = _filterInstancesByPeriod(snap.docs);
      if (docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma escala no período para exportar.')));
        return;
      }
      final tenantData = tenantSnap.data();
      final nomeIgreja = (tenantData?['name'] ?? tenantData?['nome'] ?? 'Igreja').toString();
      final endereco = (tenantData?['address'] ?? tenantData?['endereco'] ?? '').toString();
      final periodLabel = _periodLabelUppercase;

      final pdf = pw.Document();
      final rows = docs.map((d) {
        final m = d.data();
        DateTime? dt;
        try { dt = (m['date'] as Timestamp?)?.toDate(); } catch (_) {}
        final dateStr = dt != null ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}' : '';
        final names = ((m['memberNames'] as List?) ?? []).take(5).join(', ');
        return [dateStr, (m['title'] ?? '').toString(), (m['time'] ?? '').toString(), (m['departmentName'] ?? '').toString(), names];
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Center(child: pw.Text(nomeIgreja.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
            if (endereco.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Center(child: pw.Text(endereco, style: const pw.TextStyle(fontSize: 9)))),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('RELATÓRIO DE ESCALAS — $periodLabel', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: ['Data', 'Título', 'Horário', 'Departamento', 'Membros'].map((h) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList(),
                ),
                for (final row in rows)
                  pw.TableRow(
                    children: (row as List<dynamic>).map<pw.Widget>((c) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((c ?? '').toString(), style: const pw.TextStyle(fontSize: 9)))).toList(),
                  ),
              ],
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) await showPdfActions(context, bytes: bytes, filename: 'escalas_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar PDF: $e')));
    }
  }

  /// Segunda a domingo da semana corrente, agrupado por departamento.
  Future<void> _exportWeeklyChurchPdf(List<_DeptItem> allDepts) async {
    try {
      final snap = await _instancesFuture;
      final tenantSnap = await _tenantFuture;
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = DateTime(start.year, start.month, start.day + 6, 23, 59, 59);
      final docs = snap.docs.where((d) {
        DateTime? dt;
        try {
          dt = (d.data()['date'] as Timestamp?)?.toDate();
        } catch (_) {}
        if (dt == null) return false;
        return !dt.isBefore(start) && !dt.isAfter(end);
      }).toList()
        ..sort((a, b) {
          final da = (a.data()['departmentName'] ?? '').toString();
          final db = (b.data()['departmentName'] ?? '').toString();
          final c = da.compareTo(db);
          if (c != 0) return c;
          DateTime? ta, tb;
          try {
            ta = (a.data()['date'] as Timestamp?)?.toDate();
            tb = (b.data()['date'] as Timestamp?)?.toDate();
          } catch (_) {}
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhuma escala nesta semana para exportar.')));
        }
        return;
      }
      final tenantData = tenantSnap.data();
      final nomeIgreja =
          (tenantData?['name'] ?? tenantData?['nome'] ?? 'Igreja').toString();
      final endereco =
          (tenantData?['address'] ?? tenantData?['endereco'] ?? '').toString();
      final pdf = pw.Document();
      String deptKey(Map<String, dynamic> m) =>
          (m['departmentName'] ?? m['departmentId'] ?? '').toString();
      final byDept = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final d in docs) {
        final k = deptKey(d.data());
        byDept.putIfAbsent(k.isEmpty ? '—' : k, () => []).add(d);
      }
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Center(
                child: pw.Text(nomeIgreja.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold))),
            if (endereco.isNotEmpty)
              pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Center(
                      child: pw.Text(endereco,
                          style: const pw.TextStyle(fontSize: 9)))),
            pw.SizedBox(height: 10),
            pw.Center(
                child: pw.Text(
                    'ESCALA GERAL SEMANAL (${start.day}/${start.month} – ${end.day}/${end.month}/${end.year})',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 16),
            for (final entry in byDept.entries) ...[
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                color: PdfColors.grey300,
                child: pw.Text(entry.key,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 11)),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(width: 0.4),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: ['Data', 'Título', 'Horário', 'Membros']
                        .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(h,
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 9))))
                        .toList(),
                  ),
                  for (final d in entry.value)
                    pw.TableRow(
                      children: () {
                        final m = d.data();
                        DateTime? dt;
                        try {
                          dt = (m['date'] as Timestamp?)?.toDate();
                        } catch (_) {}
                        final dateStr = dt != null
                            ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                            : '';
                        final names =
                            ((m['memberNames'] as List?) ?? []).join(', ');
                        return [
                          dateStr,
                          (m['title'] ?? '').toString(),
                          (m['time'] ?? '').toString(),
                          names,
                        ]
                            .map((c) => pw.Padding(
                                padding: const pw.EdgeInsets.all(5),
                                child: pw.Text(c,
                                    style: const pw.TextStyle(fontSize: 8))))
                            .toList();
                      }(),
                    ),
                ],
              ),
              pw.SizedBox(height: 14),
            ],
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) {
        await showPdfActions(context,
            bytes: bytes,
            filename:
                'escala_geral_semanal_${DateTime.now().millisecondsSinceEpoch}.pdf');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao exportar PDF semanal: $e')));
      }
    }
  }

  Future<void> _editInstance(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final tid = await _effectiveTidFuture;
    final depts = await _deptsFuture;
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      ThemeCleanPremium.fadeSlideRoute(
        _GeneratedInstanceEditPage(
          doc: doc,
          depts: depts,
          membersCol: _membersCol(tid),
          membersColIgrejas: _membersCol(tid),
          instancesCol: _instancesCol(tid),
        ),
      ),
    );
    if (saved == true && mounted) {
      _refreshInstances();
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Escala atualizada com sucesso.'));
    }
  }

  Future<void> _deleteInstance(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir escala?'),
        content: const Text('Esta escala gerada será removida. Os modelos não são afetados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await doc.reference.delete();
      if (mounted) {
        _refreshInstances();
        ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Escala excluída.'));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  static String? _reasonForCpf(Map<String, dynamic> unavailabilityReasons, String cpf) {
    final v = unavailabilityReasons[cpf];
    if (v is Map && v['reason'] != null) return v['reason'].toString().trim();
    for (final k in unavailabilityReasons.keys) {
      if ((k ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '') == cpf.replaceAll(RegExp(r'[^0-9]'), '')) {
        final val = unavailabilityReasons[k];
        if (val is Map && val['reason'] != null) return val['reason'].toString().trim();
        break;
      }
    }
    return null;
  }

  Future<void> _substituirMembro(BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc, int index) async {
    final data = doc.data() ?? {};
    final deptId = (data['departmentId'] ?? '').toString();
    if (deptId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Departamento não identificado.')));
      return;
    }
    final cpfs = ((data['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names = ((data['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    if (index < 0 || index >= cpfs.length) return;
    final tid = await _effectiveTidFuture;
    final membersSnap = await _membersCol(tid).get();
    DateTime? escDt;
    try {
      escDt = (data['date'] as Timestamp?)?.toDate();
    } catch (_) {}
    final escTime = (data['time'] ?? '').toString();
    final crossHints = await MemberScheduleAvailability.crossDeptConflictHintsByNormCpf(
      instancesCol: _instancesCol(tid),
      excludeEscalaDocId: doc.id,
      calendarDay: escDt ?? DateTime.now(),
      slotTime: escTime,
      currentDepartmentId: deptId,
    );
    final deptMembers = <Map<String, String>>[];
    for (final m in membersSnap.docs) {
      final d = m.data();
      final depts = (d['DEPARTAMENTOS'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (!depts.contains(deptId)) continue;
      final cpf = (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      final name = (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString();
      if (cpf.isEmpty && name.isEmpty) continue;
      final norm = cpf.replaceAll(RegExp(r'[^0-9]'), '');
      final ymds = MemberScheduleAvailability.parseYmdList(
        d[MemberScheduleAvailability.fieldYmds],
      );
      final subLines = <String>[cpf];
      if (escDt != null &&
          MemberScheduleAvailability.isUnavailableOn(ymds, escDt)) {
        subLines.add('Indisponível nesta data');
      }
      final ch = crossHints[norm];
      if (ch != null) subLines.add(ch);
      deptMembers.add({'cpf': cpf, 'name': name, 'subtitle': subLines.join('\n')});
    }
    final currentCpf = cpfs[index];
    if (!mounted) return;
    final selected = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Substituir membro'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: deptMembers.length,
            itemBuilder: (_, i) {
              final m = deptMembers[i];
              final cpf = m['cpf'] ?? '';
              final name = m['name'] ?? '';
              final subtitle = m['subtitle'] ?? cpf;
              if (cpf == currentCpf) return ListTile(title: Text('$name (atual)', style: TextStyle(color: Colors.grey.shade600)));
              return ListTile(
                title: Text(name),
                subtitle: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: subtitle.contains('Indisponível') || subtitle.contains('Já escalado')
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, m),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final newCpf = selected['cpf'] ?? '';
    final newName = selected['name'] ?? '';
    if (newCpf.isEmpty) return;
    final newCpfs = List<String>.from(cpfs);
    final newNames = List<String>.from(names);
    newCpfs[index] = newCpf;
    newNames[index] = newName;
    final updates = <String, dynamic>{
      'memberCpfs': newCpfs,
      'memberNames': newNames,
      'confirmations.$currentCpf': FieldValue.delete(),
      'unavailabilityReasons.$currentCpf': FieldValue.delete(),
    };
    try {
      await doc.reference.update(updates);
      if (mounted) {
        _refreshInstances();
        ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Substituído por $newName. O novo membro verá a escala em "Minha Escala".'));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _excluirMembroDaEscala(BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc, int index) async {
    final data = doc.data() ?? {};
    final cpfs = ((data['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names = ((data['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    final confirmations = Map<String, dynamic>.from((data['confirmations'] as Map<String, dynamic>?) ?? {});
    final unavailabilityReasons = Map<String, dynamic>.from((data['unavailabilityReasons'] as Map<String, dynamic>?) ?? {});
    if (index < 0 || index >= cpfs.length) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover membro da escala?'),
        content: Text('${index < names.length ? names[index] : cpfs[index]} será removido desta escala.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    final cpf = cpfs[index];
    final newCpfs = List<String>.from(cpfs)..removeAt(index);
    final newNames = List<String>.from(names);
    if (index < newNames.length) newNames.removeAt(index);
    confirmations.remove(cpf);
    unavailabilityReasons.remove(cpf);
    final updates = <String, dynamic>{
      'memberCpfs': newCpfs,
      'memberNames': newNames,
      'confirmations': confirmations,
      'unavailabilityReasons': unavailabilityReasons,
    };
    try {
      await doc.reference.update(updates);
      if (mounted) {
        _refreshInstances();
        ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Membro removido da escala.'));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  // ── Detalhes da escala gerada ──────────────────────────────────────────────
  void _showInstanceDetail(DocumentSnapshot<Map<String, dynamic>> doc, Color deptColor) {
    final dataHolder = ValueNotifier<Map<String, dynamic>>(Map<String, dynamic>.from(doc.data() ?? {}));
    final docRef = doc.reference;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: dataHolder,
          builder: (context, data, _) {
            final title = (data['title'] ?? '').toString();
            final dept = (data['departmentName'] ?? '').toString();
            final time = (data['time'] ?? '').toString();
            final cpfs = ((data['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
            final names = ((data['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
            final confirmations = (data['confirmations'] as Map<String, dynamic>?) ?? {};
            final unavailabilityReasons = (data['unavailabilityReasons'] as Map<String, dynamic>?) ?? {};
            DateTime? dt;
            try { dt = (data['date'] as Timestamp).toDate(); } catch (_) {}
            final dateTxt = dt == null ? '' : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
            final obs = (data['observations'] ?? '').toString().trim();

            final bottomInset = MediaQuery.paddingOf(context).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
              child: ListView(
                controller: scroll,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(width: 4, height: 28, decoration: BoxDecoration(color: deptColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (dateTxt.isNotEmpty) ...[
                      Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(dateTxt, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(width: 14),
                    ],
                    if (time.isNotEmpty) ...[
                      Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(time, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(width: 14),
                    ],
                    if (dept.isNotEmpty) ...[
                      Icon(Icons.groups_rounded, size: 14, color: deptColor),
                      const SizedBox(width: 4),
                      Flexible(child: Text(dept, style: TextStyle(fontSize: 13, color: deptColor, fontWeight: FontWeight.w600))),
                    ],
                  ]),
                  if (obs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notes_rounded, size: 18, color: Colors.blueGrey.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              obs,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blueGrey.shade900,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_canWrite) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.start,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _notifySchedulePublished(doc.id);
                          },
                          icon: const Icon(Icons.notifications_active_rounded, size: 20),
                          label: const Text('Notificar membros'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            minimumSize: Size(0, ThemeCleanPremium.minTouchTarget),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _editInstance(doc);
                          },
                          icon: const Icon(Icons.edit_calendar_rounded, size: 20),
                          label: const Text('Editar escala'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            minimumSize: Size(0, ThemeCleanPremium.minTouchTarget),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteInstance(doc);
                          },
                          icon: Icon(Icons.delete_outline_rounded, size: 20, color: ThemeCleanPremium.error),
                          label: Text('Excluir', style: TextStyle(color: ThemeCleanPremium.error)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            minimumSize: Size(0, ThemeCleanPremium.minTouchTarget),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_canWrite) ...[
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: () {
                        final segs = doc.reference.path.split('/');
                        final tid = segs.length >= 2 && segs[0] == 'igrejas'
                            ? segs[1]
                            : '';
                        if (tid.isEmpty) {
                          return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
                        }
                        return FirebaseFirestore.instance
                            .collection('igrejas')
                            .doc(tid)
                            .collection('escala_trocas')
                            .where('escalaId', isEqualTo: doc.id)
                            .snapshots();
                      }(),
                      builder: (context, tSnap) {
                        if (tSnap.hasError || !tSnap.hasData) {
                          return const SizedBox.shrink();
                        }
                        final docs = tSnap.data!.docs;
                        final pendingLeader = docs
                            .where((x) =>
                                (x.data()['status'] ?? '').toString() ==
                                'pendente')
                            .toList();
                        final pendingAlvo = docs
                            .where((x) =>
                                (x.data()['status'] ?? '').toString() ==
                                'pendente_alvo')
                            .toList();
                        if (pendingLeader.isEmpty && pendingAlvo.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (pendingAlvo.isNotEmpty) ...[
                                Text(
                                  'Trocas aguardando o substituto',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.blueGrey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...pendingAlvo.map((t) {
                                  final td = t.data();
                                  final alvo =
                                      (td['alvoCpf'] ?? '').toString();
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: Colors.blueGrey.shade50,
                                    child: ListTile(
                                      leading: Icon(Icons.hourglass_top_rounded,
                                          color: Colors.blueGrey.shade600),
                                      title: const Text(
                                          'Convite enviado ao substituto'),
                                      subtitle: Text(
                                        'Substituto (CPF): $alvo — quando aceitar no app, a escala atualiza e você recebe aviso.',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      isThreeLine: true,
                                    ),
                                  );
                                }),
                                if (pendingLeader.isNotEmpty)
                                  const SizedBox(height: 12),
                              ],
                              if (pendingLeader.isNotEmpty) ...[
                                Text(
                                  'Trocas pendentes (aprovação manual)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.deepPurple.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...pendingLeader.map((t) {
                                  final td = t.data();
                                  final sol =
                                      (td['solicitanteCpf'] ?? '').toString();
                                  final alvo =
                                      (td['alvoCpf'] ?? '').toString();
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Icon(Icons.swap_horiz_rounded,
                                          color: Colors.deepPurple.shade600),
                                      title: const Text(
                                          'Pedido de troca de escala'),
                                      subtitle: Text(
                                        'Solicitante: $sol\nSubstituto: $alvo',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      isThreeLine: true,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Aprovar',
                                            icon: const Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF16A34A)),
                                            onPressed: () =>
                                                _resolverTrocaEscala(
                                                    aprovar: true, troca: t),
                                          ),
                                          IconButton(
                                            tooltip: 'Recusar',
                                            icon: const Icon(Icons.cancel_rounded,
                                                color: Color(0xFFDC2626)),
                                            onPressed: () =>
                                                _resolverTrocaEscala(
                                                    aprovar: false, troca: t),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  _StatusSummary(confirmations: confirmations, total: cpfs.length),
                  const SizedBox(height: 16),
                  Text('Membros escalados', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ThemeCleanPremium.onSurface)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < cpfs.length; i++) Builder(
                    builder: (context) {
                      final memberIndex = i;
                      final cpfKey = cpfs[memberIndex];
                      return _MemberConfirmationTile(
                        cpf: cpfKey,
                        name: memberIndex < names.length ? names[memberIndex] : '',
                        status: (confirmations[cpfKey] ?? '').toString(),
                        unavailabilityReason: _reasonForCpf(unavailabilityReasons, cpfKey),
                        canWrite: _canWrite,
                        onChangeStatus: (newStatus) async {
                          try {
                            if (newStatus.isEmpty) {
                              await docRef.update({
                                'confirmations.$cpfKey': FieldValue.delete(),
                                'unavailabilityReasons.$cpfKey': FieldValue.delete(),
                              });
                            } else {
                              await docRef.update({'confirmations.$cpfKey': newStatus});
                              if (newStatus != 'indisponivel') await docRef.update({'unavailabilityReasons.$cpfKey': FieldValue.delete()});
                            }
                            final snap = await docRef.get();
                            if (snap.exists) dataHolder.value = Map<String, dynamic>.from(snap.data() ?? {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Status gravado com sucesso.'));
                              _refreshInstances();
                            }
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gravar: $e'), backgroundColor: ThemeCleanPremium.error));
                          }
                        },
                        onSubstituir: _canWrite ? () { Navigator.pop(ctx); _substituirMembro(context, doc, memberIndex); } : null,
                        onExcluirMembro: _canWrite ? () { Navigator.pop(ctx); _excluirMembroDaEscala(context, doc, memberIndex); } : null,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Calendário (table_calendar) — aba Escalas Geradas
// ═══════════════════════════════════════════════════════════════════════════════

class _SchedulesCalendarPanel extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final List<_DeptItem> allDepts;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final Color Function(int index) colorForDept;
  final String currentCpf;
  final bool canWriteFull;
  final Set<String> managedDeptIds;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onCalendarPageChanged;
  final void Function(DocumentSnapshot<Map<String, dynamic>> doc, Color color)
      onOpenDetail;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc)
      onEdit;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc)
      onDelete;

  const _SchedulesCalendarPanel({
    required this.docs,
    required this.allDepts,
    required this.focusedDay,
    required this.selectedDay,
    required this.colorForDept,
    required this.currentCpf,
    required this.canWriteFull,
    required this.managedDeptIds,
    required this.onDaySelected,
    required this.onCalendarPageChanged,
    required this.onOpenDetail,
    required this.onEdit,
    required this.onDelete,
  });

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _eventsForDay(DateTime day) {
    return docs.where((d) {
      DateTime? dt;
      try {
        dt = (d.data()['date'] as Timestamp?)?.toDate();
      } catch (_) {}
      if (dt == null) return false;
      return isSameDay(dt, day);
    }).toList();
  }

  List<Color> _markerColorsForDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> events,
    int max,
  ) {
    final out = <Color>[];
    for (final e in events) {
      final deptIdx = allDepts.indexWhere(
        (x) => x.id == (e.data()['departmentId'] ?? '').toString(),
      );
      final c = colorForDept(deptIdx.clamp(0, 99));
      if (!out.contains(c)) out.add(c);
      if (out.length >= max) break;
    }
    if (out.isEmpty) return [ThemeCleanPremium.primary];
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsForDay(selectedDay);
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final cellFs = isMobile ? 15.0 : 14.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: TableCalendar<QueryDocumentSnapshot<Map<String, dynamic>>>(
              locale: 'pt_BR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: focusedDay,
              selectedDayPredicate: (d) => isSameDay(d, selectedDay),
              eventLoader: _eventsForDay,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              rowHeight: isMobile ? 56.0 : 50.0,
              daysOfWeekHeight: isMobile ? 30.0 : 26.0,
              calendarStyle: ControleTotalCalendarTheme.calendarStyle(
                cellFs: cellFs,
                primary: ThemeCleanPremium.primary,
                onSurface: ThemeCleanPremium.onSurface,
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 12.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
                weekendStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 12.5 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: GoogleFonts.poppins(
                  fontSize: isMobile ? 17 : 16,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final squares = _markerColorsForDay(events, 3);
                  final more = events.length > 3 ? events.length - 3 : 0;
                  return Positioned(
                    bottom: 5,
                    left: 1,
                    right: 1,
                    child: ControleTotalCalendarTheme.markerRow(
                      colors: squares,
                      moreCount: more,
                      isMobile: isMobile,
                    ),
                  );
                },
              ),
              onDaySelected: onDaySelected,
              onPageChanged: onCalendarPageChanged,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Agenda ministerial — dia selecionado',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 10),
        if (dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Nenhuma escala neste dia no período filtrado.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          ...dayEvents.map((esc) {
            final deptIdx = allDepts.indexWhere(
                (x) => x.id == (esc.data()['departmentId'] ?? '').toString());
            final deptIdInst =
                (esc.data()['departmentId'] ?? '').toString();
            final canMutate =
                canWriteFull || managedDeptIds.contains(deptIdInst);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InstanceCard(
                doc: esc,
                deptColor: colorForDept(deptIdx.clamp(0, 99)),
                currentCpf: currentCpf,
                canWrite: canMutate,
                onTap: () =>
                    onOpenDetail(esc, colorForDept(deptIdx.clamp(0, 99))),
                onEdit: canMutate ? () => onEdit(esc) : null,
                onDelete: canMutate ? () => onDelete(esc) : null,
              ),
            );
          }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Template Card Premium
// ═══════════════════════════════════════════════════════════════════════════════

class _TemplateCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final Color deptColor;
  final bool canWrite;
  final VoidCallback onEdit;
  final VoidCallback onGenerate;
  final VoidCallback onDelete;
  const _TemplateCard({required this.doc, required this.deptColor, required this.canWrite, required this.onEdit, required this.onGenerate, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final title = (m['title'] ?? '').toString();
    final deptName = (m['departmentName'] ?? '').toString();
    final rec = (m['recurrence'] ?? '').toString();
    final day = (m['day'] ?? '').toString();
    final time = (m['time'] ?? '').toString();
    final cpfs = ((m['memberCpfs'] as List?) ?? []);
    final names = ((m['memberNames'] as List?) ?? []);
    final recLabel = {'daily': 'Diário', 'weekly': 'Semanal', 'monthly': 'Mensal', 'yearly': 'Anual'}[rec] ?? rec;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 130,
            decoration: BoxDecoration(
              color: deptColor,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    if (canWrite)
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') onEdit();
                          if (v == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Editar')),
                          const PopupMenuItem(value: 'delete', child: Text('Excluir')),
                        ],
                        child: const Icon(Icons.more_vert_rounded, size: 20),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _InfoChip(icon: Icons.repeat_rounded, text: recLabel),
                    if (day.isNotEmpty) _InfoChip(icon: Icons.today_rounded, text: day),
                    if (time.isNotEmpty) _InfoChip(icon: Icons.access_time_rounded, text: time),
                    if (deptName.isNotEmpty) _InfoChip(icon: Icons.groups_rounded, text: deptName, color: deptColor),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.people_rounded, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        names.isNotEmpty ? names.take(4).join(', ') + (names.length > 4 ? ' +${names.length - 4}' : '') : '${cpfs.length} membro(s)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (canWrite)
                      FilledButton.tonalIcon(
                        onPressed: onGenerate,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('Gerar', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 36)),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Instance Card Premium
// ═══════════════════════════════════════════════════════════════════════════════

class _InstanceCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final Color deptColor;
  final String currentCpf;
  final bool canWrite;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _InstanceCard({required this.doc, required this.deptColor, required this.currentCpf, required this.canWrite, required this.onTap, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final title = (m['title'] ?? '').toString();
    final dept = (m['departmentName'] ?? '').toString();
    final time = (m['time'] ?? '').toString();
    final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};
    DateTime? dt;
    try { dt = (m['date'] as Timestamp).toDate(); } catch (_) {}
    final dateTxt = dt == null ? '' : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    final isPast = dt != null && dt.isBefore(DateTime.now());

    int confirmed = 0, unavailable = 0, faltaNj = 0;
    for (final v in confirmations.values) {
      if (v == 'confirmado') {
        confirmed++;
      } else if (v == 'indisponivel') {
        unavailable++;
      } else if (v == 'falta_nao_justificada') {
        faltaNj++;
      }
    }
    final pending = cpfs.length - confirmed - unavailable - faltaNj;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: isPast ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 90,
                decoration: BoxDecoration(
                  color: deptColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isPast ? Colors.grey.shade500 : ThemeCleanPremium.onSurface))),
                        if (canWrite && (onEdit != null || onDelete != null))
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') onEdit?.call();
                              if (v == 'delete') onDelete?.call();
                            },
                            itemBuilder: (_) => [
                              if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Editar escala')),
                              if (onDelete != null) PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: ThemeCleanPremium.error))),
                            ],
                            child: Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey.shade600),
                          ),
                        if (dateTxt.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: deptColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(dateTxt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: deptColor)),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (time.isNotEmpty) ...[Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)), const SizedBox(width: 10)],
                        if (dept.isNotEmpty) Text(dept, style: TextStyle(fontSize: 12, color: deptColor, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        _MiniStatusDots(
                            confirmed: confirmed,
                            pending: pending,
                            unavailable: unavailable,
                            faltaNj: faltaNj),
                      ]),
                      if (names.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: names.length > 8 ? 8 : names.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, ai) {
                              final nm = names[ai];
                              return Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                                ),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: deptColor.withOpacity(0.18),
                                  child: Text(
                                    nm.isNotEmpty ? nm[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: deptColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (names.length > 8)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+${names.length - 8} membro(s)',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Form Page — Criar/Editar modelo de escala
// ═══════════════════════════════════════════════════════════════════════════════

class _TemplateFormPage extends StatefulWidget {
  final String tenantId;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final Map<String, dynamic> data;
  final List<_DeptItem> depts;
  final CollectionReference<Map<String, dynamic>> templatesCol;
  final CollectionReference<Map<String, dynamic>> membersCol;
  final CollectionReference<Map<String, dynamic>> membersColIgrejas;
  final CollectionReference<Map<String, dynamic>> instancesCol;
  const _TemplateFormPage({required this.tenantId, this.doc, required this.data, required this.depts, required this.templatesCol, required this.membersCol, required this.membersColIgrejas, required this.instancesCol});

  @override
  State<_TemplateFormPage> createState() => _TemplateFormPageState();
}

class _TemplateFormPageState extends State<_TemplateFormPage> {
  late final TextEditingController _titleCtrl;
  late String _recurrence;
  late final TextEditingController _dayCtrl;
  late final TextEditingController _timeCtrl;
  String _departmentId = '';
  String _departmentName = '';
  List<_MemberSelect> _deptMembers = [];
  final Set<String> _selectedCpfs = {};
  bool _loadingMembers = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _titleCtrl = TextEditingController(text: (d['title'] ?? 'Escala de Obreiros').toString());
    _recurrence = (d['recurrence'] ?? 'weekly').toString();
    _dayCtrl = TextEditingController(text: (d['day'] ?? 'Domingo').toString());
    _timeCtrl = TextEditingController(text: (d['time'] ?? '19:00').toString());
    _departmentId = (d['departmentId'] ?? '').toString();
    _departmentName = (d['departmentName'] ?? '').toString();
    final existingCpfs = ((d['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    _selectedCpfs.addAll(existingCpfs);
    _dayCtrl.addListener(_onTemplateDayTimeChanged);
    _timeCtrl.addListener(_onTemplateDayTimeChanged);
    if (_departmentId.isNotEmpty) _loadDeptMembers();
  }

  void _onTemplateDayTimeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dayCtrl.removeListener(_onTemplateDayTimeChanged);
    _timeCtrl.removeListener(_onTemplateDayTimeChanged);
    _titleCtrl.dispose();
    _dayCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeptMembers() async {
    if (_departmentId.isEmpty) return;
    setState(() => _loadingMembers = true);
    try {
      QuerySnapshot<Map<String, dynamic>> snap = await widget.membersCol.get().timeout(const Duration(seconds: 15));
      List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = snap.docs;

      if (allDocs.isEmpty) {
        try {
          final snapIgrejas = await widget.membersColIgrejas.get().timeout(const Duration(seconds: 10));
          allDocs = snapIgrejas.docs;
        } catch (_) {}
      }

      final freq = <String, int>{};
      try {
        final escSnap = await widget.instancesCol
            .orderBy('date', descending: true)
            .limit(200)
            .get()
            .timeout(const Duration(seconds: 10));
        for (final esc in escSnap.docs) {
          if ((esc.data()['departmentId'] ?? '').toString() != _departmentId) continue;
          final d = esc.data();
          final cpfs = ((d['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
          for (final c in cpfs) freq[c] = (freq[c] ?? 0) + 1;
        }
      } catch (_) {}

      final deptMembers = <_MemberSelect>[];
      for (final m in allDocs) {
        final data = m.data();
        final depts = (data['DEPARTAMENTOS'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (!depts.contains(_departmentId)) continue;
        final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final name = (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? '').toString();
        final photoUrl = imageUrlFromMap(data);
        if (cpf.isEmpty && name.isEmpty) continue;
        final ymds = MemberScheduleAvailability.parseYmdList(
          data[MemberScheduleAvailability.fieldYmds],
        );
        deptMembers.add(_MemberSelect(
          cpf: cpf,
          name: name,
          photoUrl: isValidImageUrl(photoUrl) ? photoUrl : '',
          frequency: freq[cpf] ?? 0,
          memberDocId: m.id,
          unavailableYmds: ymds,
        ));
      }
      deptMembers.sort((a, b) => b.frequency.compareTo(a.frequency));

      if (mounted) setState(() {
        _deptMembers = deptMembers;
        _loadingMembers = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar membros: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  static int? _weekdayFromDayLabel(String day) {
    final d = day.toLowerCase().trim();
    if (d.contains('dom')) return DateTime.sunday;
    if (d.contains('seg')) return DateTime.monday;
    if (d.contains('ter') && !d.contains('ça')) return DateTime.tuesday;
    if (d.contains('qua')) return DateTime.wednesday;
    if (d.contains('qui')) return DateTime.thursday;
    if (d.contains('sex')) return DateTime.friday;
    if (d.contains('sáb') || d.contains('sab')) return DateTime.saturday;
    return null;
  }

  static String _normCpfConflict(String s) =>
      s.replaceAll(RegExp(r'[^0-9]'), '');

  String _displayNameForCpf(String c) {
    final n = _normCpfConflict(c);
    for (final m in _deptMembers) {
      if (_normCpfConflict(m.cpf) == n) return m.name.isNotEmpty ? m.name : c;
    }
    return c;
  }

  DateTime? _nextOccurrenceForTemplateWeekday() {
    final w = _weekdayFromDayLabel(_dayCtrl.text);
    if (w == null) return null;
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 400; i++) {
      if (d.weekday == w) return d;
      d = d.add(const Duration(days: 1));
    }
    return null;
  }

  List<String> _templateWarningLines(_MemberSelect m) {
    final lines = <String>[];
    final next = _nextOccurrenceForTemplateWeekday();
    if (next != null &&
        MemberScheduleAvailability.isUnavailableOn(m.unavailableYmds, next)) {
      lines.add(
        'Indisponível na próxima ocorrência (${next.day.toString().padLeft(2, '0')}/${next.month.toString().padLeft(2, '0')})',
      );
    }
    return lines;
  }

  Future<void> _checkConflicts() async {
    if (_selectedCpfs.isEmpty) return;
    final tplWeekday = _weekdayFromDayLabel(_dayCtrl.text);
    final tStr = _timeCtrl.text.trim();
    final conflicts = <String, Set<String>>{};
    final cpfsList = _selectedCpfs.toList();
    for (var i = 0; i < cpfsList.length; i += 10) {
      final chunk = cpfsList.skip(i).take(10).toList();
      QuerySnapshot<Map<String, dynamic>> existing;
      try {
        existing = await widget.instancesCol
            .where('memberCpfs', arrayContainsAny: chunk)
            .limit(100)
            .get();
      } catch (_) {
        continue;
      }
      for (final esc in existing.docs) {
        final otherDept = (esc.data()['departmentId'] ?? '').toString();
        if (otherDept == _departmentId) continue;
        DateTime? escDt;
        try {
          escDt = (esc.data()['date'] as Timestamp?)?.toDate();
        } catch (_) {}
        if (escDt == null) continue;
        if (tplWeekday != null && escDt.weekday != tplWeekday) continue;
        final escTime = (esc.data()['time'] ?? '').toString().trim();
        if (!MemberScheduleAvailability.timesOverlapRough(tStr, escTime)) {
          continue;
        }
        final mems = ((esc.data()['memberCpfs'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        final otherDeptName =
            (esc.data()['departmentName'] ?? otherDept).toString();
        final escTimeShort = escTime.isNotEmpty ? escTime : '?';
        for (final c in chunk) {
          if (mems.any((m) => _normCpfConflict(m) == _normCpfConflict(c))) {
            conflicts.putIfAbsent(c, () => <String>{}).add(
                  '$otherDeptName ($escTimeShort)',
                );
          }
        }
      }
    }
    final nextOcc = _nextOccurrenceForTemplateWeekday();
    if (nextOcc != null) {
      for (final cpf in cpfsList) {
        _MemberSelect? match;
        for (final mm in _deptMembers) {
          if (_normCpfConflict(mm.cpf) == _normCpfConflict(cpf)) {
            match = mm;
            break;
          }
        }
        if (match != null &&
            MemberScheduleAvailability.isUnavailableOn(
                match.unavailableYmds, nextOcc)) {
          conflicts.putIfAbsent(cpf, () => <String>{}).add(
                'calendário: indisponível na próx. data (${nextOcc.day}/${nextOcc.month})',
              );
        }
      }
    }
    if (!mounted) return;
    if (conflicts.isNotEmpty) {
      final buf = StringBuffer();
      for (final e in conflicts.entries) {
        buf.writeln(
            '• ${_displayNameForCpf(e.key)} → ${e.value.join("; ")}');
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('Conflito de escala')),
          ]),
          content: SingleChildScrollView(
              child: Text(buf.toString(), style: const TextStyle(fontSize: 14))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Nenhum conflito no mesmo dia da semana com horário sobreposto em outro departamento.'),
      );
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final selectedNames = <String>[];
    for (final cpf in _selectedCpfs) {
      final match = _deptMembers.where((m) => m.cpf == cpf);
      selectedNames.add(match.isNotEmpty ? match.first.name : cpf);
    }

    final payload = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'recurrence': _recurrence,
      'day': _dayCtrl.text.trim(),
      'time': _timeCtrl.text.trim(),
      'departmentId': _departmentId,
      'departmentName': _departmentName,
      'memberCpfs': _selectedCpfs.toList(),
      'memberNames': selectedNames,
      'active': true,
      'updatedAt': Timestamp.now(),
    };
    if (widget.doc == null) {
      final u = FirebaseAuth.instance.currentUser;
      payload['createdAt'] = Timestamp.now();
      payload['createdByUid'] = u?.uid ?? '';
      payload['createdByName'] = u?.displayName ?? '';
      await widget.templatesCol.add(payload);
    } else {
      await widget.doc!.reference.update(payload);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: Text(widget.doc == null ? 'Nova Escala' : 'Editar Escala'),
        actions: [
          if (!_saving)
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
              child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: _saving
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: ThemeCleanPremium.pagePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      title: 'Informações',
                      icon: Icons.info_outline_rounded,
                      children: [
                        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Título da escala', prefixIcon: Icon(Icons.title_rounded))),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _recurrence,
                          decoration: const InputDecoration(labelText: 'Recorrência', prefixIcon: Icon(Icons.repeat_rounded)),
                          items: const [
                            DropdownMenuItem(value: 'daily', child: Text('Diário')),
                            DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                            DropdownMenuItem(value: 'monthly', child: Text('Mensal')),
                            DropdownMenuItem(value: 'yearly', child: Text('Anual')),
                          ],
                          onChanged: (v) => setState(() => _recurrence = v ?? 'weekly'),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: TextField(controller: _dayCtrl, decoration: const InputDecoration(labelText: 'Dia (ex: Domingo)', prefixIcon: Icon(Icons.today_rounded)))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _timeCtrl, decoration: const InputDecoration(labelText: 'Horário', prefixIcon: Icon(Icons.access_time_rounded)))),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Departamento',
                      icon: Icons.groups_rounded,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _departmentId.isEmpty ? null : _departmentId,
                          decoration: const InputDecoration(labelText: 'Vincular ao departamento', prefixIcon: Icon(Icons.groups_rounded)),
                          items: widget.depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                          onChanged: (v) {
                            final sel = widget.depts.firstWhere((d) => d.id == v, orElse: () => const _DeptItem(id: '', name: ''));
                            setState(() {
                              _departmentId = v ?? '';
                              _departmentName = sel.name;
                              _selectedCpfs.clear();
                            });
                            if (_departmentId.isNotEmpty) _loadDeptMembers();
            },
          ),
        ],
                    ),
                    if (_departmentId.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Membros do Departamento',
                        icon: Icons.people_rounded,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(onPressed: () => setState(() { for (final m in _deptMembers) _selectedCpfs.add(m.cpf); }), child: const Text('Todos', style: TextStyle(fontSize: 12))),
                          TextButton(onPressed: () => setState(() => _selectedCpfs.clear()), child: const Text('Nenhum', style: TextStyle(fontSize: 12))),
                        ]),
                        children: [
                          if (_loadingMembers) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                          else if (_deptMembers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Nenhum membro vinculado a este departamento.', style: TextStyle(color: Colors.grey.shade600)),
                            )
                          else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: ThemeCleanPremium.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                              child: Row(children: [
                                Icon(Icons.check_circle_rounded, size: 16, color: ThemeCleanPremium.primary),
                                const SizedBox(width: 8),
                                Text('${_selectedCpfs.length} de ${_deptMembers.length} selecionados', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primary)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                            for (final m in _deptMembers)
                              _MemberCheckTile(
                                member: m,
                                selected: _selectedCpfs.contains(m.cpf),
                                warningLines: _templateWarningLines(m),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) { _selectedCpfs.add(m.cpf); }
                                    else { _selectedCpfs.remove(m.cpf); }
                                  });
                                },
                              ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _checkConflicts,
                                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                                label: const Text('Verificar conflitos'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edição completa — escala gerada (instância)
// ═══════════════════════════════════════════════════════════════════════════════

class _GeneratedInstanceEditPage extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final List<_DeptItem> depts;
  final CollectionReference<Map<String, dynamic>> membersCol;
  final CollectionReference<Map<String, dynamic>> membersColIgrejas;
  final CollectionReference<Map<String, dynamic>> instancesCol;

  const _GeneratedInstanceEditPage({
    required this.doc,
    required this.depts,
    required this.membersCol,
    required this.membersColIgrejas,
    required this.instancesCol,
  });

  @override
  State<_GeneratedInstanceEditPage> createState() => _GeneratedInstanceEditPageState();
}

class _GeneratedInstanceEditPageState extends State<_GeneratedInstanceEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _observationsCtrl;
  late DateTime _selectedDate;
  String _departmentId = '';
  String _departmentName = '';
  List<_MemberSelect> _deptMembers = [];
  final Set<String> _selectedCpfs = {};
  late List<String> _initialCpfsOrder;
  late List<String> _initialNames;
  /// Ordem exibida na escala (arrastar e soltar).
  final List<String> _memberOrder = [];
  bool _loadingMembers = false;
  bool _saving = false;
  Map<String, String> _crossDeptHintByNormCpf = {};
  Timer? _crossHintDebounce;

  static String _normCpf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static TimeOfDay? _parseTime(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!) ?? 0;
    final min = int.tryParse(m.group(2)!) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: min.clamp(0, 59));
  }

  @override
  void initState() {
    super.initState();
    final d = widget.doc.data() ?? {};
    _titleCtrl = TextEditingController(text: (d['title'] ?? '').toString());
    _timeCtrl = TextEditingController(text: (d['time'] ?? '19:00').toString());
    _observationsCtrl =
        TextEditingController(text: (d['observations'] ?? '').toString());
    DateTime? dt;
    try {
      dt = (d['date'] as Timestamp?)?.toDate();
    } catch (_) {}
    _selectedDate = dt ?? DateTime.now();
    _departmentId = (d['departmentId'] ?? '').toString();
    _departmentName = (d['departmentName'] ?? '').toString();
    _initialCpfsOrder = ((d['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    _initialNames = ((d['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    _selectedCpfs.addAll(_initialCpfsOrder);
    _syncMemberOrderFromSelection();
    if (_departmentId.isNotEmpty) _loadDeptMembers();
    _timeCtrl.addListener(_scheduleCrossHintReload);
  }

  void _scheduleCrossHintReload() {
    _crossHintDebounce?.cancel();
    _crossHintDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _reloadCrossDeptHints();
    });
  }

  Future<void> _reloadCrossDeptHints() async {
    if (_departmentId.isEmpty) return;
    final hints = await MemberScheduleAvailability.crossDeptConflictHintsByNormCpf(
      instancesCol: widget.instancesCol,
      excludeEscalaDocId: widget.doc.id,
      calendarDay: _selectedDate,
      slotTime: _timeCtrl.text.trim(),
      currentDepartmentId: _departmentId,
    );
    if (mounted) setState(() => _crossDeptHintByNormCpf = hints);
  }

  void _syncMemberOrderFromSelection() {
    _memberOrder.removeWhere((c) => !_selectedCpfs.contains(c));
    for (final c in _selectedCpfs) {
      if (!_memberOrder.contains(c)) _memberOrder.add(c);
    }
  }

  String _displayNameForOrderedCpf(String c) {
    final fromDept = _deptMembers.where((m) => m.cpf == c);
    if (fromDept.isNotEmpty && fromDept.first.name.trim().isNotEmpty) {
      return fromDept.first.name;
    }
    final fb = _fallbackNameForCpf(c);
    return fb.isNotEmpty ? fb : c;
  }

  @override
  void dispose() {
    _timeCtrl.removeListener(_scheduleCrossHintReload);
    _crossHintDebounce?.cancel();
    _titleCtrl.dispose();
    _timeCtrl.dispose();
    _observationsCtrl.dispose();
    super.dispose();
  }

  String _fallbackNameForCpf(String cpf) {
    final n = _normCpf(cpf);
    for (var i = 0; i < _initialCpfsOrder.length; i++) {
      if (_normCpf(_initialCpfsOrder[i]) == n && i < _initialNames.length && _initialNames[i].trim().isNotEmpty) {
        return _initialNames[i];
      }
    }
    return '';
  }

  List<_MemberSelect> get _displayMembers {
    final seen = <String>{};
    final out = <_MemberSelect>[];
    for (final m in _deptMembers) {
      seen.add(_normCpf(m.cpf));
      out.add(m);
    }
    for (final c in _selectedCpfs) {
      if (seen.contains(_normCpf(c))) continue;
      seen.add(_normCpf(c));
      final name = _fallbackNameForCpf(c);
      out.add(_MemberSelect(
        cpf: c,
        name: name.isNotEmpty ? name : c,
        photoUrl: '',
        frequency: -1,
        memberDocId: '',
        unavailableYmds: const [],
      ));
    }
    return out;
  }

  List<String> _instanceMemberWarningLines(_MemberSelect m) {
    final lines = <String>[];
    if (MemberScheduleAvailability.isUnavailableOn(
        m.unavailableYmds, _selectedDate)) {
      lines.add('Indisponível nesta data');
    }
    final hint = _crossDeptHintByNormCpf[_normCpf(m.cpf)];
    if (hint != null) lines.add(hint);
    return lines;
  }

  bool _instanceSelectionBlocked(_MemberSelect m) {
    return _instanceMemberWarningLines(m).isNotEmpty;
  }

  _MemberSelect? _lookupDisplayMember(String cpf) {
    final n = _normCpf(cpf);
    for (final m in _displayMembers) {
      if (_normCpf(m.cpf) == n) return m;
    }
    return null;
  }

  List<String> _namesForOrderedCpfs(List<String> orderedCpfs) {
    final names = <String>[];
    for (final cpf in orderedCpfs) {
      final fromDept = _deptMembers.where((m) => m.cpf == cpf);
      if (fromDept.isNotEmpty && fromDept.first.name.trim().isNotEmpty) {
        names.add(fromDept.first.name);
        continue;
      }
      final fb = _fallbackNameForCpf(cpf);
      if (fb.isNotEmpty) {
        names.add(fb);
      } else {
        names.add(cpf);
      }
    }
    return names;
  }

  static Map<String, dynamic> _remapCpfKeyedMap(Map<String, dynamic> old, List<String> newCpfs) {
    final out = <String, dynamic>{};
    for (final newCpf in newCpfs) {
      for (final e in old.entries) {
        if (_normCpf(e.key.toString()) == _normCpf(newCpf)) {
          out[newCpf] = e.value;
          break;
        }
      }
    }
    return out;
  }

  Future<void> _loadDeptMembers() async {
    if (_departmentId.isEmpty) return;
    setState(() => _loadingMembers = true);
    try {
      QuerySnapshot<Map<String, dynamic>> snap = await widget.membersCol.get().timeout(const Duration(seconds: 15));
      var allDocs = snap.docs;
      if (allDocs.isEmpty) {
        try {
          final snapIgrejas = await widget.membersColIgrejas.get().timeout(const Duration(seconds: 10));
          allDocs = snapIgrejas.docs;
        } catch (_) {}
      }

      final freq = <String, int>{};
      try {
        final escSnap = await widget.instancesCol.orderBy('date', descending: true).limit(200).get().timeout(const Duration(seconds: 10));
        for (final esc in escSnap.docs) {
          if ((esc.data()['departmentId'] ?? '').toString() != _departmentId) continue;
          final ed = esc.data();
          final cpfs = ((ed['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
          for (final c in cpfs) {
            freq[c] = (freq[c] ?? 0) + 1;
          }
        }
      } catch (_) {}

      final deptMembers = <_MemberSelect>[];
      for (final m in allDocs) {
        final data = m.data();
        final depts = (data['DEPARTAMENTOS'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (!depts.contains(_departmentId)) continue;
        final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        final name = (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? '').toString();
        final photoUrl = imageUrlFromMap(data);
        if (cpf.isEmpty && name.isEmpty) continue;
        final ymds = MemberScheduleAvailability.parseYmdList(
          data[MemberScheduleAvailability.fieldYmds],
        );
        deptMembers.add(_MemberSelect(
          cpf: cpf,
          name: name,
          photoUrl: isValidImageUrl(photoUrl) ? photoUrl : '',
          frequency: freq[cpf] ?? 0,
          memberDocId: m.id,
          unavailableYmds: ymds,
        ));
      }
      deptMembers.sort((a, b) => b.frequency.compareTo(a.frequency));

      if (mounted) {
        setState(() {
          _deptMembers = deptMembers;
          _loadingMembers = false;
        });
        await _reloadCrossDeptHints();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar membros: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      await _reloadCrossDeptHints();
    }
  }

  Future<void> _pickTime() async {
    final initial = _parseTime(_timeCtrl.text) ?? TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() => _timeCtrl.text = '$h:$m');
      await _reloadCrossDeptHints();
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o título da escala.')));
      return;
    }
    if (_departmentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione o departamento.')));
      return;
    }
    if (_selectedCpfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ao menos um membro.')));
      return;
    }

    await _reloadCrossDeptHints();
    if (!mounted) return;
    final orderedPreview = List<String>.from(_memberOrder);
    final blockers = <String>[];
    for (final cpf in orderedPreview) {
      final m = _lookupDisplayMember(cpf);
      if (m == null) continue;
      if (_instanceSelectionBlocked(m)) {
        final name = m.name.isNotEmpty ? m.name : cpf;
        blockers.add('• $name: ${_instanceMemberWarningLines(m).join('; ')}');
      }
    }
    if (blockers.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: Row(
            children: [
              Icon(Icons.block_rounded, color: ThemeCleanPremium.error),
              const SizedBox(width: 10),
              const Expanded(child: Text('Não é possível salvar')),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Ajuste a escala antes de salvar:\n\n${blockers.join('\n')}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
          ],
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final orderedCpfs = List<String>.from(_memberOrder);
      final memberNames = _namesForOrderedCpfs(orderedCpfs);
      final data = widget.doc.data() ?? {};
      final oldConf = Map<String, dynamic>.from((data['confirmations'] as Map?) ?? {});
      final oldUnav = Map<String, dynamic>.from((data['unavailabilityReasons'] as Map?) ?? {});

      final t = _parseTime(_timeCtrl.text.trim()) ?? const TimeOfDay(hour: 19, minute: 0);
      final combined = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        t.hour,
        t.minute,
      );

      await widget.doc.reference.update({
        'title': _titleCtrl.text.trim(),
        'time': _timeCtrl.text.trim(),
        'date': Timestamp.fromDate(combined),
        'departmentId': _departmentId,
        'departmentName': _departmentName,
        'memberCpfs': orderedCpfs,
        'memberNames': memberNames,
        'observations': _observationsCtrl.text.trim(),
        'confirmations': _remapCpfKeyedMap(oldConf, orderedCpfs),
        'unavailabilityReasons': _remapCpfKeyedMap(oldUnav, orderedCpfs),
        'updatedAt': Timestamp.now(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Editar escala gerada'),
        actions: [
          if (!_saving)
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
              child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: _saving
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: ThemeCleanPremium.pagePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      title: 'Informações',
                      icon: Icons.info_outline_rounded,
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(labelText: 'Título da escala', prefixIcon: Icon(Icons.title_rounded)),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _observationsCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Observações (ex.: Escala de Verão, culto especial)',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (isMobile) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.calendar_today_rounded, color: ThemeCleanPremium.primary),
                            title: const Text('Data'),
                            subtitle: Text(
                              '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _pickDate,
                            minVerticalPadding: ThemeCleanPremium.minTouchTarget / 2 - 8,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.access_time_rounded, color: ThemeCleanPremium.primary),
                            title: const Text('Horário'),
                            subtitle: Text(_timeCtrl.text.isEmpty ? 'Definir' : _timeCtrl.text),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              await _pickTime();
                            },
                            minVerticalPadding: ThemeCleanPremium.minTouchTarget / 2 - 8,
                          ),
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.calendar_today_rounded, color: ThemeCleanPremium.primary),
                                  title: const Text('Data'),
                                  subtitle: Text(
                                    '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                                  ),
                                  onTap: _pickDate,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _timeCtrl,
                                  decoration: const InputDecoration(labelText: 'Horário (HH:mm)', prefixIcon: Icon(Icons.access_time_rounded)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (!isMobile) const SizedBox(height: 8),
                        if (!isMobile)
                          OutlinedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.schedule_rounded, size: 20),
                            label: const Text('Ajustar horário com relógio'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Departamento',
                      icon: Icons.groups_rounded,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _departmentId.isEmpty ? null : _departmentId,
                          decoration: const InputDecoration(labelText: 'Departamento', prefixIcon: Icon(Icons.groups_rounded)),
                          items: widget.depts.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                          onChanged: (v) {
                            final sel = widget.depts.firstWhere((d) => d.id == v, orElse: () => const _DeptItem(id: '', name: ''));
                            setState(() {
                              _departmentId = v ?? '';
                              _departmentName = sel.name;
                            });
                            if (_departmentId.isNotEmpty) _loadDeptMembers();
                          },
                        ),
                      ],
                    ),
                    if (_departmentId.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Membros',
                        icon: Icons.people_rounded,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                for (final m in _displayMembers) {
                                  if (!_instanceSelectionBlocked(m)) {
                                    _selectedCpfs.add(m.cpf);
                                  }
                                }
                              }),
                              child: const Text('Todos', style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _selectedCpfs.clear()),
                              child: const Text('Nenhum', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        children: [
                          if (_loadingMembers)
                            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                          else if (_deptMembers.isEmpty && _displayMembers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Nenhum membro vinculado a este departamento.', style: TextStyle(color: Colors.grey.shade600)),
                            )
                          else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 16, color: ThemeCleanPremium.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_selectedCpfs.length} selecionado(s)',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final m in _displayMembers)
                              _MemberCheckTile(
                                member: m,
                                selected: _selectedCpfs.contains(m.cpf),
                                warningLines: _instanceMemberWarningLines(m),
                                dimmedWhenUnselected: _instanceSelectionBlocked(m),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedCpfs.add(m.cpf);
                                    } else {
                                      _selectedCpfs.remove(m.cpf);
                                    }
                                    _syncMemberOrderFromSelection();
                                  });
                                },
                              ),
                            if (_memberOrder.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Ordem na escala (arraste para reordenar)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ReorderableListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                onReorder: (oldIndex, newIndex) {
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex--;
                                    final item = _memberOrder.removeAt(oldIndex);
                                    _memberOrder.insert(newIndex, item);
                                  });
                                },
                                children: [
                                  for (var i = 0; i < _memberOrder.length; i++)
                                    ListTile(
                                      key: ValueKey(_memberOrder[i]),
                                      leading:
                                          const Icon(Icons.drag_handle_rounded),
                                      title: Text(
                                        _displayNameForOrderedCpf(
                                            _memberOrder[i]),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        _memberOrder[i],
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                    ],
                    SizedBox(height: MediaQuery.paddingOf(context).bottom + 48),
                  ],
                ),
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets Auxiliares
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.icon, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: ThemeCleanPremium.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _MemberSelect {
  final String cpf;
  final String name;
  final String photoUrl;
  final int frequency;
  final String memberDocId;
  final List<String> unavailableYmds;
  const _MemberSelect({
    required this.cpf,
    required this.name,
    required this.photoUrl,
    required this.frequency,
    this.memberDocId = '',
    this.unavailableYmds = const [],
  });
}

class _MemberCheckTile extends StatelessWidget {
  final _MemberSelect member;
  final bool selected;
  final ValueChanged<bool?> onChanged;
  final List<String> warningLines;
  /// Membro não deve ser incluído (ausência / conflito): linha esmaecida e não marca checkbox ao tocar.
  final bool dimmedWhenUnselected;
  const _MemberCheckTile({
    required this.member,
    required this.selected,
    required this.onChanged,
    this.warningLines = const [],
    this.dimmedWhenUnselected = false,
  });

  @override
  Widget build(BuildContext context) {
    final dim = dimmedWhenUnselected && !selected;
    void toggle() {
      if (!selected && dim) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este nome não pode ser incluído: indisponível nesta data ou conflito de horário em outro ministério.',
            ),
          ),
        );
        return;
      }
      onChanged(!selected);
    }

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? ThemeCleanPremium.primary.withOpacity(0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: toggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) {
                      if (v == true && dim) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Indisponível ou conflito de horário: não é possível incluir nesta escala.',
                            ),
                          ),
                        );
                        return;
                      }
                      onChanged(v);
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(width: 12),
                SafeCircleAvatarImage(
                  imageUrl: isValidImageUrl(member.photoUrl) ? member.photoUrl : null,
                  radius: 18,
                  fallbackIcon: Icons.person_rounded,
                  fallbackColor: Colors.blue.shade800,
                  backgroundColor: Colors.blue.shade100,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name.isNotEmpty ? member.name : member.cpf, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (member.frequency > 0) Text('${member.frequency}x escalado(a)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      for (final line in warningLines)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                line.contains('Já escalado')
                                    ? Icons.warning_rounded
                                    : Icons.event_busy_rounded,
                                size: 13,
                                color: line.contains('Já escalado')
                                    ? Colors.red.shade700
                                    : Colors.orange.shade800,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: line.contains('Já escalado')
                                        ? Colors.red.shade800
                                        : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (member.frequency == 0 && warningLines.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Disponível', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (dim) {
      return Opacity(opacity: 0.48, child: row);
    }
    return row;
  }
}

class _MemberConfirmationTile extends StatelessWidget {
  final String cpf;
  final String name;
  final String status;
  final String? unavailabilityReason;
  final bool canWrite;
  final ValueChanged<String> onChangeStatus;
  final VoidCallback? onSubstituir;
  final VoidCallback? onExcluirMembro;

  const _MemberConfirmationTile({
    required this.cpf,
    required this.name,
    required this.status,
    required this.canWrite,
    required this.onChangeStatus,
    this.unavailabilityReason,
    this.onSubstituir,
    this.onExcluirMembro,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (status) {
      case 'confirmado':
        statusColor = ThemeCleanPremium.success;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Confirmado';
        break;
      case 'indisponivel':
        statusColor = ThemeCleanPremium.error;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Indisponível';
        break;
      case 'falta_nao_justificada':
        statusColor = const Color(0xFFB91C1C);
        statusIcon = Icons.person_off_rounded;
        statusLabel = 'Falta não justificada';
        break;
      default:
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.schedule_rounded;
        statusLabel = 'Pendente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: statusColor.withOpacity(0.15),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontWeight: FontWeight.w700, color: statusColor, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isNotEmpty ? name : cpf,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    if (name.isNotEmpty && cpf.replaceAll(RegExp(r'[^0-9]'), '').length >= 9)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          cpf,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 4),
              Text(statusLabel, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
              if (canWrite) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'substituir' && onSubstituir != null) onSubstituir!();
                    else if (v == 'excluir_membro' && onExcluirMembro != null) onExcluirMembro!();
                    else if (v == 'confirmar_falta') { /* mantém indisponível */ }
                    else onChangeStatus(v);
                  },
                  child: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey.shade500),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'confirmado', child: Text('Marcar confirmado')),
                    const PopupMenuItem(value: 'indisponivel', child: Text('Marcar indisponível')),
                    const PopupMenuItem(
                        value: 'falta_nao_justificada',
                        child: Text('Falta não justificada (assiduidade)')),
                    const PopupMenuItem(value: '', child: Text('Pendente')),
                    if (status == 'indisponivel' && (onSubstituir != null || onExcluirMembro != null)) ...[
                      const PopupMenuDivider(),
                      if (onSubstituir != null) const PopupMenuItem(value: 'substituir', child: Text('Substituir por outro membro')),
                      const PopupMenuItem(value: 'confirmar_falta', child: Text('Confirmar falta (manter)')),
                      if (onExcluirMembro != null) const PopupMenuItem(value: 'excluir_membro', child: Text('Excluir da escala', style: TextStyle(color: ThemeCleanPremium.error))),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (status == 'indisponivel' && (unavailabilityReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ThemeCleanPremium.error.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: ThemeCleanPremium.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Motivo: ${unavailabilityReason!.trim()}', style: TextStyle(fontSize: 12, color: ThemeCleanPremium.error.withOpacity(0.9)))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  final Map<String, dynamic> confirmations;
  final int total;
  const _StatusSummary({required this.confirmations, required this.total});

  @override
  Widget build(BuildContext context) {
    int confirmed = 0, unavailable = 0, faltaNj = 0;
    for (final v in confirmations.values) {
      if (v == 'confirmado') {
        confirmed++;
      } else if (v == 'indisponivel') {
        unavailable++;
      } else if (v == 'falta_nao_justificada') {
        faltaNj++;
      }
    }
    final pending = total - confirmed - unavailable - faltaNj;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusBadge(label: 'Confirmados', count: confirmed, color: ThemeCleanPremium.success),
        _StatusBadge(label: 'Pendentes', count: pending, color: Colors.amber.shade700),
        _StatusBadge(label: 'Indisponíveis', count: unavailable, color: ThemeCleanPremium.error),
        _StatusBadge(label: 'Falta NJ', count: faltaNj, color: const Color(0xFFB91C1C)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MemberScaleStats {
  final String name;
  final String cpf;
  int escalas = 0;
  int presencas = 0;
  int faltas = 0;
  _MemberScaleStats({required this.name, required this.cpf});
}

class _ReportSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _ReportSummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _ReportChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ReportChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ReportMetricCard({required this.label, required this.value, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          if (onTap != null) ...[const SizedBox(height: 4), Icon(Icons.touch_app_rounded, size: 14, color: color.withOpacity(0.7))],
        ],
      ),
    );
    if (onTap != null) {
      return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd), onTap: onTap, child: content));
    }
    return content;
  }
}

class _ReportChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _ReportChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MiniStatusDots extends StatelessWidget {
  final int confirmed;
  final int pending;
  final int unavailable;
  final int faltaNj;
  const _MiniStatusDots({
    required this.confirmed,
    required this.pending,
    required this.unavailable,
    this.faltaNj = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (confirmed > 0) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: ThemeCleanPremium.success, shape: BoxShape.circle)), const SizedBox(width: 2), Text('$confirmed', style: TextStyle(fontSize: 10, color: ThemeCleanPremium.success, fontWeight: FontWeight.w700))],
      if (pending > 0) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.amber.shade600, shape: BoxShape.circle)), const SizedBox(width: 2), Text('$pending', style: TextStyle(fontSize: 10, color: Colors.amber.shade600, fontWeight: FontWeight.w700))],
      if (unavailable > 0) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: BoxDecoration(color: ThemeCleanPremium.error, shape: BoxShape.circle)), const SizedBox(width: 2), Text('$unavailable', style: TextStyle(fontSize: 10, color: ThemeCleanPremium.error, fontWeight: FontWeight.w700))],
      if (faltaNj > 0) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFB91C1C), shape: BoxShape.circle)), const SizedBox(width: 2), Text('$faltaNj', style: const TextStyle(fontSize: 10, color: Color(0xFFB91C1C), fontWeight: FontWeight.w700))],
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _InfoChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _FilterChipDept extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChipDept({required this.label, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeCleanPremium.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? c : Colors.grey.shade300),
            boxShadow: selected ? [BoxShadow(color: c.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : [],
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey.shade700)),
        ),
        ),
    );
  }
}

class _DeptItem {
  final String id;
  final String name;
  final String leaderCpf;
  const _DeptItem({required this.id, required this.name, this.leaderCpf = ''});
}
