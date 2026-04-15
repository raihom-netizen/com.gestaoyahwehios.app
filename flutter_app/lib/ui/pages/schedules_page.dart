import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/schedule_escala_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const bool kScheduleAutoGenerationEnabled = false;

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

/// Data `dd/MM/aaaa` no diálogo «Gerar escalas».
DateTime? _parseBrDateDdMmYyyy(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  try {
    final d = DateFormat('dd/MM/yyyy').parseStrict(s);
    return DateTime(d.year, d.month, d.day);
  } catch (_) {
    return null;
  }
}

int _scheduleLastDayOfMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

DateTime _scheduleAddMonthsClamped(DateTime dt, int monthsToAdd) {
  var y = dt.year;
  var m = dt.month + monthsToAdd;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  final last = _scheduleLastDayOfMonth(y, m);
  final d = math.min(dt.day, last);
  return DateTime(y, m, d);
}

/// Ocorrências do modelo entre [rangeStart] e [rangeEnd] (inclusive, só calendário).
List<DateTime> scheduleTemplateOccurrencesInRange({
  required String recurrence,
  required int? weekday,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required int hour,
  required int minute,
  int maxOccurrences = 400,
}) {
  final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  if (end.isBefore(start)) return [];
  final rec = recurrence.toLowerCase().trim();
  final out = <DateTime>[];
  void push(DateTime dayOnly) {
    if (out.length >= maxOccurrences) return;
    out.add(DateTime(dayOnly.year, dayOnly.month, dayOnly.day, hour, minute));
  }

  if (rec == 'daily') {
    var c = start;
    while (!c.isAfter(end)) {
      push(c);
      c = c.add(const Duration(days: 1));
    }
    return out;
  }

  if (rec == 'monthly') {
    var c = DateTime(
      start.year,
      start.month,
      math.min(start.day, _scheduleLastDayOfMonth(start.year, start.month)),
    );
    while (c.isBefore(start)) {
      c = _scheduleAddMonthsClamped(c, 1);
    }
    while (!c.isAfter(end)) {
      if (!c.isBefore(start)) push(c);
      if (out.length >= maxOccurrences) break;
      c = _scheduleAddMonthsClamped(c, 1);
    }
    return out;
  }

  if (rec == 'yearly') {
    var c = DateTime(
      start.year,
      start.month,
      math.min(start.day, _scheduleLastDayOfMonth(start.year, start.month)),
    );
    while (c.isBefore(start)) {
      final ny = c.year + 1;
      c = DateTime(
        ny,
        c.month,
        math.min(c.day, _scheduleLastDayOfMonth(ny, c.month)),
      );
    }
    while (!c.isAfter(end)) {
      if (!c.isBefore(start)) push(c);
      if (out.length >= maxOccurrences) break;
      final ny = c.year + 1;
      c = DateTime(
        ny,
        c.month,
        math.min(c.day, _scheduleLastDayOfMonth(ny, c.month)),
      );
    }
    return out;
  }

  // weekly (default)
  var w = start;
  if (weekday != null) {
    while (w.weekday != weekday && !w.isAfter(end)) {
      w = w.add(const Duration(days: 1));
    }
    while (!w.isAfter(end)) {
      push(w);
      if (out.length >= maxOccurrences) break;
      w = w.add(const Duration(days: 7));
    }
  } else {
    while (!w.isAfter(end)) {
      push(w);
      if (out.length >= maxOccurrences) break;
      w = w.add(const Duration(days: 7));
    }
  }
  return out;
}

class SchedulesPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cpf;
  /// Dentro de [IgrejaCleanShell]: abas “pill” coladas ao cartão do módulo + [SafeArea] ajustado.
  final bool embeddedInShell;
  const SchedulesPage({
    super.key,
    required this.tenantId,
    required this.role,
    required this.cpf,
    this.embeddedInShell = false,
  });

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
  /// `todos` = sem filtro de data nas escalas já carregadas (até 500) — padrão para não “sumir” escalas geradas noutro mês.
  String _periodFilter = 'todos'; // todos, diario, semanal, mes_anterior, mes_atual, anual, periodo
  DateTime? _periodStart;
  DateTime? _periodEnd;
  /// Lista (0) ou calendário interativo (1) na aba “Escalas Geradas”.
  int _instancesViewSegment = 0;
  DateTime _schedCalFocused = DateTime.now();
  DateTime? _schedCalSelected;

  /// Seleção na lista para exclusão em lote.
  bool _escalaSelectionMode = false;
  final Set<String> _selectedEscalaIds = {};

  /// Filtros da aba Escalas geradas — recolhido por defeito para ganhar área útil.
  bool _escalaFiltersExpanded = false;

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
        case 'todos':
          return true;
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

  /// Pool só com filtro de departamento (ignora chips de período) — exclusão por mês/ano.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _deptOnlyPool(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    var deptFiltered = _filterDeptId.isEmpty
        ? allDocs
        : allDocs
            .where((d) =>
                (d.data()['departmentId'] ?? '').toString() == _filterDeptId)
            .toList();
    if (_scopedDeptLeader) {
      deptFiltered = deptFiltered
          .where((d) => _managedDeptIds
              .contains((d.data()['departmentId'] ?? '').toString()))
          .toList();
    }
    return deptFiltered;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleInstancesFromAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    var deptFiltered = _filterDeptId.isEmpty
        ? allDocs
        : allDocs
            .where((d) =>
                (d.data()['departmentId'] ?? '').toString() == _filterDeptId)
            .toList();
    if (_scopedDeptLeader) {
      deptFiltered = deptFiltered
          .where((d) => _managedDeptIds
              .contains((d.data()['departmentId'] ?? '').toString()))
          .toList();
    }
    return _filterInstancesByPeriod(deptFiltered);
  }

  bool _canDeleteInstance(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final deptIdInst = (doc.data()['departmentId'] ?? '').toString();
    return _canWriteFull || _managedDeptIds.contains(deptIdInst);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsForMonthYear(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pool,
    int year,
    int month,
  ) {
    return pool.where((d) {
      DateTime? dt;
      try {
        dt = (d.data()['date'] as Timestamp?)?.toDate();
      } catch (_) {}
      return dt != null && dt.year == year && dt.month == month;
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsForYear(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pool,
    int year,
  ) {
    return pool.where((d) {
      DateTime? dt;
      try {
        dt = (d.data()['date'] as Timestamp?)?.toDate();
      } catch (_) {}
      return dt != null && dt.year == year;
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

  Future<void> _exportEscalaInstancePdf(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final path = doc.reference.path.split('/');
    if (path.length < 2 || path[0] != 'igrejas') return;
    final tid = path[1];
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gerando PDF…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      final branding = await loadReportPdfBranding(tid);
      final tenantSnap =
          await FirebaseFirestore.instance.collection('igrejas').doc(tid).get();
      final t = tenantSnap.data() ?? {};
      final address = (t['address'] ?? t['endereco'] ?? '').toString().trim();
      final phone =
          (t['phone'] ?? t['telefone'] ?? t['whatsapp'] ?? '').toString().trim();
      final bytes = await buildScheduleEscalaPdf(
        escalaData: doc.data() ?? {},
        branding: branding,
        churchAddress: address,
        churchPhone: phone,
      );
      if (!mounted) return;
      await showPdfActions(
        context,
        bytes: bytes,
        filename: 'escala_${doc.id}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gerar o PDF: $e')),
        );
      }
    }
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
      final map = res.data is Map ? (res.data as Map) : <String, dynamic>{};
      final n = map['count'] ?? 0;
      final emails = map['emailsSent'];
      if (mounted) {
        final extra = emails is int && emails > 0 ? ' + $emails e-mail(s).' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Notificações enviadas ($n envio(s) FCM$extra',
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
      case 'todos': return 'TODAS (CARREGADAS)';
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

  /// Diálogo premium: período explícito (início/fim) — evita “próximos 30 dias” ou mês inteiro sem controlo.
  Future<({DateTime start, DateTime end, int members})?> _showPremiumGenerateScheduleDialog() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var rangeStart = today;
    var rangeEnd = today.add(const Duration(days: 13));
    final membersCtrl = TextEditingController(text: '5');
    final startCtrl = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(rangeStart),
    );
    final endCtrl = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(rangeEnd),
    );
    String? errText;

    final result = await showDialog<({DateTime start, DateTime end, int members})?>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> pickStart() async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: rangeStart,
                firstDate: DateTime(today.year - 1, 1, 1),
                lastDate: DateTime(today.year + 2, 12, 31),
                locale: const Locale('pt', 'BR'),
                helpText: 'Data inicial',
                cancelText: 'Cancelar',
                confirmText: 'Definir',
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: Theme.of(c).colorScheme.copyWith(
                          primary: ThemeCleanPremium.primary,
                        ),
                  ),
                  child: child!,
                ),
              );
              if (d != null) {
                setS(() {
                  rangeStart = DateTime(d.year, d.month, d.day);
                  startCtrl.text = DateFormat('dd/MM/yyyy').format(rangeStart);
                  errText = null;
                });
              }
            }

            Future<void> pickEnd() async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: rangeEnd,
                firstDate: DateTime(today.year - 1, 1, 1),
                lastDate: DateTime(today.year + 2, 12, 31),
                locale: const Locale('pt', 'BR'),
                helpText: 'Data final',
                cancelText: 'Cancelar',
                confirmText: 'Definir',
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: Theme.of(c).colorScheme.copyWith(
                          primary: ThemeCleanPremium.primary,
                        ),
                  ),
                  child: child!,
                ),
              );
              if (d != null) {
                setS(() {
                  rangeEnd = DateTime(d.year, d.month, d.day);
                  endCtrl.text = DateFormat('dd/MM/yyyy').format(rangeEnd);
                  errText = null;
                });
              }
            }

            final parsedStart = _parseBrDateDdMmYyyy(startCtrl.text);
            final parsedEnd = _parseBrDateDdMmYyyy(endCtrl.text);
            final span = (parsedStart != null &&
                    parsedEnd != null &&
                    !parsedEnd.isBefore(parsedStart))
                ? parsedEnd.difference(parsedStart).inDays + 1
                : 0;
            final border = OutlineInputBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              borderSide: BorderSide(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.15),
              ),
            );
            final focusedBorder = OutlineInputBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              borderSide: BorderSide(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.55),
                width: 1.5,
              ),
            );

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
              ),
              backgroundColor: ThemeCleanPremium.cardBackground,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed: () => Navigator.pop(ctx, null),
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: ThemeCleanPremium.onSurface,
                                size: 20,
                              ),
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(40, 40),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    ThemeCleanPremium.primary.withValues(alpha: 0.14),
                                    ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.22),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: ThemeCleanPremium.softUiCardShadow,
                              ),
                              child: Icon(Icons.event_available_rounded,
                                  color: ThemeCleanPremium.primary, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gerar escalas',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Escolha só o intervalo desejado. Nada é criado fora dessas datas.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Período (inicial e final)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: startCtrl,
                          keyboardType: TextInputType.text,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Data inicial',
                            hintText: 'dd/MM/aaaa',
                            suffixIcon: IconButton(
                              tooltip: 'Calendário',
                              icon: Icon(Icons.calendar_month_rounded,
                                  color: ThemeCleanPremium.primary),
                              onPressed: pickStart,
                            ),
                            filled: true,
                            fillColor: ThemeCleanPremium.surface.withValues(alpha: 0.65),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: focusedBorder,
                          ),
                          onChanged: (_) => setS(() => errText = null),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: endCtrl,
                          keyboardType: TextInputType.text,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Data final',
                            hintText: 'dd/MM/aaaa',
                            suffixIcon: IconButton(
                              tooltip: 'Calendário',
                              icon: Icon(Icons.calendar_month_rounded,
                                  color: ThemeCleanPremium.primary),
                              onPressed: pickEnd,
                            ),
                            filled: true,
                            fillColor: ThemeCleanPremium.surface.withValues(alpha: 0.65),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: focusedBorder,
                          ),
                          onChanged: (_) => setS(() => errText = null),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          parsedStart != null &&
                                  parsedEnd != null &&
                                  parsedEnd.isBefore(parsedStart)
                              ? 'A data final não pode ser anterior à inicial.'
                              : span >= 1
                                  ? '$span dia(s) no período'
                                  : 'Informe datas válidas (dd/MM/aaaa)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: parsedStart != null &&
                                    parsedEnd != null &&
                                    parsedEnd.isBefore(parsedStart)
                                ? ThemeCleanPremium.error
                                : ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: membersCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ThemeCleanPremium.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Membros por escala',
                            prefixIcon:
                                Icon(Icons.groups_rounded, color: ThemeCleanPremium.primary),
                            filled: true,
                            fillColor: ThemeCleanPremium.surface.withValues(alpha: 0.65),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: focusedBorder,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            gradient: LinearGradient(
                              colors: [
                                ThemeCleanPremium.primary.withValues(alpha: 0.08),
                                ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.12),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  color: ThemeCleanPremium.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Rodízio: quem serviu menos entra primeiro. '
                                  'A periodicidade do modelo (diária, semanal, mensal ou anual) aplica-se apenas dentro do período escolhido.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (errText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errText!,
                            style: TextStyle(
                              color: ThemeCleanPremium.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, null),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  foregroundColor: ThemeCleanPremium.onSurface,
                                  side: BorderSide(
                                    color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: () {
                                  final n = int.tryParse(membersCtrl.text.trim()) ?? 5;
                                  final pS = _parseBrDateDdMmYyyy(startCtrl.text);
                                  final pE = _parseBrDateDdMmYyyy(endCtrl.text);
                                  if (pS == null) {
                                    setS(() => errText =
                                        'Data inicial inválida. Use dd/MM/aaaa.');
                                    return;
                                  }
                                  if (pE == null) {
                                    setS(() => errText =
                                        'Data final inválida. Use dd/MM/aaaa.');
                                    return;
                                  }
                                  if (pE.isBefore(pS)) {
                                    setS(() => errText =
                                        'A data final não pode ser anterior à inicial.');
                                    return;
                                  }
                                  final spanDays = pE.difference(pS).inDays + 1;
                                  if (spanDays > 731) {
                                    setS(() => errText =
                                        'Período máximo: 731 dias (2 anos). Reduza o intervalo.');
                                    return;
                                  }
                                  if (n < 1) {
                                    setS(() =>
                                        errText = 'Informe ao menos 1 membro por escala.');
                                    return;
                                  }
                                  Navigator.pop(
                                    ctx,
                                    (
                                      start: pS,
                                      end: pE,
                                      members: n.clamp(1, 999),
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Gerar neste período'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    membersCtrl.dispose();
    startCtrl.dispose();
    endCtrl.dispose();
    return result;
  }

  // ── Gerar escalas no período escolhido (rodízio + conflitos) ───────────────
  Future<void> _generate(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!kScheduleAutoGenerationEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'A geração automática de escala está desativada no momento.',
          ),
        );
      }
      return;
    }
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

    final pick = await _showPremiumGenerateScheduleDialog();
    if (pick == null) return;

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

    if (allCpfs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Modelo sem membros — edite o modelo antes de gerar.',
          ),
        );
      }
      return;
    }

    final perDay = pick.members.clamp(1, allCpfs.length);

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

    const kMaxOcc = 400;
    final dates = scheduleTemplateOccurrencesInRange(
      recurrence: rec,
      weekday: weekday,
      rangeStart: pick.start,
      rangeEnd: pick.end,
      hour: hh,
      minute: mm,
      maxOccurrences: kMaxOcc,
    );

    if (dates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Nenhuma ocorrência no período para esta periodicidade. '
            'Verifique o intervalo ou o dia da semana no modelo (ex.: Domingo).',
          ),
        );
      }
      return;
    }

    // Rodízio: busca frequência recente por CPF (filtro por departamento em memória para evitar índice composto)
    final recentSnap = await instances.orderBy('date', descending: true).limit(300).get();
    final freq = <String, int>{};
    for (final esc in recentSnap.docs) {
      if ((esc.data()['departmentId'] ?? '').toString() != deptId) continue;
      final cpfs = ((esc.data()['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
      for (final c in cpfs) freq[c] = (freq[c] ?? 0) + 1;
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
      setState(() => _periodFilter = 'todos');
      _refreshInstances();
      final genCount = dates.length - skippedNoEligible;
      var msg = '$genCount escala(s) gerada(s) com rodízio e checagem de conflito/ausência.';
      if (skippedNoEligible > 0) {
        msg += ' $skippedNoEligible data(s) ignorada(s): nenhum voluntário elegível (ausência ou outro ministério no mesmo horário).';
      }
      if (dates.length >= kMaxOcc) {
        msg += ' Limite de $kMaxOcc ocorrências por geração — reduza o período ou gere em etapas se precisar de mais.';
      }
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar(msg));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final narrowTabs = MediaQuery.sizeOf(context).width < 420;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Escalas',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: ThemeCleanPremium.navSidebarAccent,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Modelos'),
            Tab(text: 'Escalas geradas'),
            Tab(text: 'Relatórios'),
          ],
        ),
        actions: [
          if (_canWrite)
            IconButton(
              tooltip: 'Nova escala',
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add_circle_outline_rounded),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(
                  ThemeCleanPremium.minTouchTarget,
                  ThemeCleanPremium.minTouchTarget,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd),
              ),
              onPressed: () => _editTemplate(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nova Escala',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          children: [
            if (isMobile)
              Container(
                color: ThemeCleanPremium.primary,
                child: ChurchPanelPillTabBar(
                  controller: _tab,
                  tabs: [
                    const Tab(text: 'Modelos'),
                    Tab(text: narrowTabs ? 'Geradas' : 'Escalas geradas'),
                    const Tab(text: 'Relatórios'),
                  ],
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
                    canGenerate: kScheduleAutoGenerationEnabled,
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

  String _instancesFilterSummaryLine(List<_DeptItem> allDepts) {
    String period;
    switch (_periodFilter) {
      case 'todos':
        period = 'Todas as datas';
        break;
      case 'diario':
        period = 'Diário';
        break;
      case 'semanal':
        period = 'Semanal';
        break;
      case 'mes_anterior':
        period = 'Mês anterior';
        break;
      case 'mes_atual':
        period = 'Mês atual';
        break;
      case 'anual':
        period = 'Anual';
        break;
      case 'periodo':
        if (_periodStart != null && _periodEnd != null) {
          period =
              '${_periodStart!.day}/${_periodStart!.month}–${_periodEnd!.day}/${_periodEnd!.month}/${_periodEnd!.year}';
        } else {
          period = 'Período custom.';
        }
        break;
      default:
        period = '';
    }
    var dept = 'Todos os deptos';
    if (_filterDeptId.isNotEmpty) {
      final m =
          allDepts.where((d) => d.id == _filterDeptId).toList();
      if (m.isNotEmpty) {
        dept = m.first.name;
      }
    }
    return '$period · $dept';
  }

  /// Colunas da grelha de filtros (relatórios / escalas geradas) — menos altura que Wrap.
  int _escalaFilterCrossAxisCount(double w) {
    if (w >= 1200) return 6;
    if (w >= 900) return 5;
    if (w >= 640) return 4;
    if (w >= 420) return 3;
    return 2;
  }

  Widget _buildEscalaFilterGrid({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = _escalaFilterCrossAxisCount(c.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 44,
          ),
          itemCount: children.length,
          itemBuilder: (_, i) => children[i],
        );
      },
    );
  }

  Widget _buildEscalaFilterSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.primary.withOpacity(0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ThemeCleanPremium.primary.withOpacity(0.12)),
          ),
          child: Icon(icon, size: 18, color: ThemeCleanPremium.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  /// Cartão único “Ultra Premium” para filtros (depto + período + ações PDF).
  Widget _buildEscalaInstancesFilterCard(List<_DeptItem> allDepts) {
    final periodChips = <Widget>[
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Todas',
          selected: _periodFilter == 'todos',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'todos'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Diário',
          selected: _periodFilter == 'diario',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'diario'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Semanal',
          selected: _periodFilter == 'semanal',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'semanal'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Mês ant.',
          selected: _periodFilter == 'mes_anterior',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'mes_anterior'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Mês atual',
          selected: _periodFilter == 'mes_atual',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'mes_atual'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Anual',
          selected: _periodFilter == 'anual',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'anual'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Período',
          selected: _periodFilter == 'periodo',
          compact: true,
          onTap: () async {
            final start = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (start == null || !mounted) return;
            final end = await showDatePicker(
              context: context,
              initialDate: start,
              firstDate: start,
              lastDate: DateTime(2030),
            );
            if (mounted && end != null) {
              setState(() {
                _periodFilter = 'periodo';
                _periodStart = start;
                _periodEnd = end;
              });
            }
          },
        ),
      ),
    ];

    final deptChips = <Widget>[
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Todos',
          selected: _filterDeptId.isEmpty,
          compact: true,
          onTap: () => setState(() {
            _filterDeptId = '';
            _instancesFuture = _fetchInstancesForEffectiveTenant();
          }),
        ),
      ),
      for (var i = 0; i < allDepts.length; i++)
        SizedBox(
          width: double.infinity,
          child: _FilterChipDept(
            label: allDepts[i].name,
            selected: _filterDeptId == allDepts[i].id,
            color: _colorForDept(i),
            compact: true,
            onTap: () => setState(() {
              _filterDeptId =
                  _filterDeptId == allDepts[i].id ? '' : allDepts[i].id;
              _instancesFuture = _fetchInstancesForEffectiveTenant();
            }),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withOpacity(0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            ...ThemeCleanPremium.softUiCardShadow,
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(
                  () => _escalaFiltersExpanded = !_escalaFiltersExpanded,
                ),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tune_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Filtros',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _escalaFiltersExpanded
                                      ? 'Toque para recolher'
                                      : 'Toque para expandir',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (!_escalaFiltersExpanded) ...[
                              const SizedBox(height: 6),
                              Text(
                                _instancesFilterSummaryLine(allDepts),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.25,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        _escalaFiltersExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: ThemeCleanPremium.primary,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_escalaFiltersExpanded) ...[
              const SizedBox(height: 12),
              if (allDepts.isNotEmpty) ...[
                _buildEscalaFilterSectionHeader(
                    icon: Icons.groups_rounded, title: 'Departamento'),
                const SizedBox(height: 10),
                _buildEscalaFilterGrid(children: deptChips),
                const SizedBox(height: 18),
              ],
              _buildEscalaFilterSectionHeader(
                  icon: Icons.event_repeat_rounded, title: 'Período'),
              const SizedBox(height: 10),
              _buildEscalaFilterGrid(children: periodChips),
              if (_canWrite) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
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
                        tooltip:
                            'PDF semanal geral (todos os deptos)',
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
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Filtros do relatório (grelha — menos altura que Wrap).
  Widget _buildReportsFiltersCard(List<_DeptItem> depts) {
    final periodChips = <Widget>[
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Todas',
          selected: _periodFilter == 'todos',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'todos'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Diário',
          selected: _periodFilter == 'diario',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'diario'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Semanal',
          selected: _periodFilter == 'semanal',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'semanal'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Mês ant.',
          selected: _periodFilter == 'mes_anterior',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'mes_anterior'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Mês atual',
          selected: _periodFilter == 'mes_atual',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'mes_atual'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Anual',
          selected: _periodFilter == 'anual',
          compact: true,
          onTap: () => setState(() => _periodFilter = 'anual'),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Período',
          selected: _periodFilter == 'periodo',
          compact: true,
          onTap: () async {
            final start = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (start == null || !mounted) return;
            final end = await showDatePicker(
              context: context,
              initialDate: start,
              firstDate: start,
              lastDate: DateTime(2030),
            );
            if (mounted && end != null) {
              setState(() {
                _periodFilter = 'periodo';
                _periodStart = start;
                _periodEnd = end;
              });
            }
          },
        ),
      ),
    ];
    final deptChips = <Widget>[
      SizedBox(
        width: double.infinity,
        child: _FilterChipDept(
          label: 'Todos',
          selected: _reportDeptId.isEmpty,
          compact: true,
          onTap: () => setState(() => _reportDeptId = ''),
        ),
      ),
      ...depts.map(
        (e) => SizedBox(
          width: double.infinity,
          child: _FilterChipDept(
            label: e.name,
            selected: _reportDeptId == e.id,
            compact: true,
            onTap: () => setState(() => _reportDeptId = e.id),
          ),
        ),
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          ...ThemeCleanPremium.softUiCardShadow,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Filtros do relatório',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildEscalaFilterSectionHeader(icon: Icons.event_repeat_rounded, title: 'Período'),
          const SizedBox(height: 10),
          _buildEscalaFilterGrid(children: periodChips),
          const SizedBox(height: 18),
          _buildEscalaFilterSectionHeader(icon: Icons.groups_rounded, title: 'Departamento'),
          const SizedBox(height: 10),
          _buildEscalaFilterGrid(children: deptChips),
        ],
      ),
    );
  }

  /// Cabeçalho da aba Escalas geradas (hero + filtros + ações + segmento) — entra no scroll único.
  Widget _buildInstancesTabHeader(List<_DeptItem> allDepts) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _tenantFuture,
          builder: (context, tenSnap) {
            final td = tenSnap.data?.data();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withOpacity(0.08),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withOpacity(0.16),
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Row(
                  children: [
                    StableChurchLogo(
                      tenantId: widget.tenantId,
                      tenantData: td,
                      width: 50,
                      height: 50,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Escala geral',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.primary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Gere escalas, acompanhe confirmações e relatórios',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        _buildEscalaInstancesFilterCard(allDepts),
        if (_canWrite)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final snap = await _instancesFuture;
                      if (!mounted) return;
                      await _showExclusaoPeriodoDialog(snap.docs);
                    },
                    icon: Icon(Icons.delete_sweep_rounded,
                        color: ThemeCleanPremium.error),
                    label: const Text('Excluir por período'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.error,
                      side: BorderSide(
                        color: ThemeCleanPremium.error.withOpacity(0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => setState(() {
                      _escalaSelectionMode = !_escalaSelectionMode;
                      if (!_escalaSelectionMode) {
                        _selectedEscalaIds.clear();
                      }
                    }),
                    icon: Icon(
                      _escalaSelectionMode
                          ? Icons.close_rounded
                          : Icons.checklist_rounded,
                    ),
                    label: Text(
                      _escalaSelectionMode
                          ? 'Cancelar seleção'
                          : 'Selecionar escalas',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: _escalaSelectionMode
                          ? ThemeCleanPremium.error.withOpacity(0.12)
                          : ThemeCleanPremium.primary.withOpacity(0.12),
                      foregroundColor: ThemeCleanPremium.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_periodFilter == 'periodo' &&
            (_periodStart != null || _periodEnd != null))
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
                ButtonSegment(
                    value: 0,
                    label: Text('Lista'),
                    icon: Icon(Icons.view_list_rounded, size: 18)),
                ButtonSegment(
                    value: 1,
                    label: Text('Calendário'),
                    icon: Icon(Icons.calendar_month_rounded, size: 18)),
              ],
              selected: {_instancesViewSegment},
              onSelectionChanged: (s) => setState(() {
                _instancesViewSegment = s.first;
                if (_instancesViewSegment == 1) {
                  _escalaSelectionMode = false;
                  _selectedEscalaIds.clear();
                }
                if (_schedCalSelected == null) {
                  _schedCalSelected = DateTime.now();
                }
              }),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab: Escalas Geradas ───────────────────────────────────────────────────
  Widget _buildInstancesTab() {
    return FutureBuilder<List<_DeptItem>>(
      future: _deptsFuture,
      builder: (context, deptSnap) {
        final allDepts = deptSnap.data ?? [];
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            if (snap.connectionState == ConnectionState.waiting ||
                !snap.hasData) {
              return RefreshIndicator(
                onRefresh: () async => _refreshInstances(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildInstancesTabHeader(allDepts)),
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: ChurchPanelLoadingBody()),
                    ),
                  ],
                ),
              );
            }
            final allDocs = snap.data?.docs ?? [];
            var deptFiltered = _filterDeptId.isEmpty
                ? allDocs
                : allDocs
                    .where((d) =>
                        (d.data()['departmentId'] ?? '').toString() ==
                        _filterDeptId)
                    .toList();
            if (_scopedDeptLeader) {
              deptFiltered = deptFiltered
                  .where((d) => _managedDeptIds
                      .contains((d.data()['departmentId'] ?? '').toString()))
                  .toList();
            }
            final docs = _filterInstancesByPeriod(deptFiltered);
            final showSelBar = _escalaSelectionMode &&
                _canWrite &&
                docs.isNotEmpty &&
                _instancesViewSegment == 0;
            final bottomPad = showSelBar ? 88.0 : 80.0;

            if (docs.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _refreshInstances(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildInstancesTabHeader(allDepts)),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma escala no período.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toque em «Todas» no filtro de período para ver todas as escalas carregadas, ou escolha «Mês atual» / «Anual» conforme as datas geradas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (_instancesViewSegment == 1) {
              return RefreshIndicator(
                onRefresh: () async => _refreshInstances(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildInstancesTabHeader(allDepts)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottomPad),
                        child: _SchedulesCalendarPanel(
                          docs: docs,
                          allDepts: allDepts,
                          focusedDay: _schedCalFocused,
                          selectedDay: _schedCalSelected ?? _schedCalFocused,
                          colorForDept: _colorForDept,
                          currentCpf:
                              widget.cpf.replaceAll(RegExp(r'[^0-9]'), ''),
                          canWriteFull: _canWriteFull,
                          managedDeptIds: _managedDeptIds,
                          onDaySelected: (d, f) => setState(() {
                            _schedCalSelected = d;
                            _schedCalFocused = f;
                          }),
                          onCalendarPageChanged: (f) =>
                              setState(() => _schedCalFocused = f),
                          onOpenDetail: (d, color) =>
                              _showInstanceDetail(d, color),
                          onEdit: _editInstance,
                          onDelete: _deleteInstance,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                RefreshIndicator(
                  onRefresh: () async => _refreshInstances(),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                          child: _buildInstancesTabHeader(allDepts)),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final deptIdx = allDepts.indexWhere((d) =>
                                  d.id ==
                                  (docs[i].data()['departmentId'] ?? ''));
                              final deptIdInst =
                                  (docs[i].data()['departmentId'] ?? '')
                                      .toString();
                              final canMutate = _canWriteFull ||
                                  _managedDeptIds.contains(deptIdInst);
                              final selMode = _escalaSelectionMode &&
                                  _instancesViewSegment == 0;
                              final id = docs[i].id;
                              return Padding(
                                padding: EdgeInsets.only(
                                    bottom: i < docs.length - 1 ? 10 : 0),
                                child: _InstanceCard(
                                  doc: docs[i],
                                  deptColor:
                                      _colorForDept(deptIdx.clamp(0, 99)),
                                  currentCpf: widget.cpf
                                      .replaceAll(RegExp(r'[^0-9]'), ''),
                                  canWrite: canMutate,
                                  selectionMode: selMode,
                                  selected: _selectedEscalaIds.contains(id),
                                  onSelectionChanged: selMode && canMutate
                                      ? (v) => setState(() {
                                            if (v) {
                                              _selectedEscalaIds.add(id);
                                            } else {
                                              _selectedEscalaIds.remove(id);
                                            }
                                          })
                                      : null,
                                  onTap: () => _showInstanceDetail(
                                    docs[i],
                                    _colorForDept(deptIdx.clamp(0, 99)),
                                  ),
                                  onEdit: canMutate
                                      ? () => _editInstance(docs[i])
                                      : null,
                                  onDelete: canMutate
                                      ? () => _deleteInstance(docs[i])
                                      : null,
                                ),
                              );
                            },
                            childCount: docs.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSelBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Material(
                      elevation: 14,
                      color: Colors.white,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade200),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 16,
                                offset: const Offset(0, -4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: () => setState(
                                  () => _selectedEscalaIds.clear(),
                                ),
                                child: const Text('Limpar'),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _selectedEscalaIds
                                    ..clear()
                                    ..addAll(
                                      docs
                                          .where(_canDeleteInstance)
                                          .map((d) => d.id),
                                    );
                                }),
                                child: const Text('Todas elegíveis'),
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _selectedEscalaIds.isEmpty
                                    ? null
                                    : () async {
                                        final sel = docs
                                            .where((d) =>
                                                _selectedEscalaIds
                                                    .contains(d.id))
                                            .toList();
                                        await _deleteManyInstances(sel);
                                      },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                ),
                                label: Text(
                                  'Excluir (${_selectedEscalaIds.length})',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
        final realizadasDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final pendentesDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
          if (allConfirmed && cpfs.isNotEmpty) {
            escalasRealizadas++;
            realizadasDocs.add(d);
          } else {
            pendentesDocs.add(d);
          }
        }
        final escalasGeradas = docs.length;
        final escalasPendentes = escalasGeradas - escalasRealizadas;
        final list = memberStats.values.toList()..sort((a, b) => b.escalas.compareTo(a.escalas));

        final chartMetrics = [escalasGeradas, escalasRealizadas, escalasPendentes, totalPresencas, totalFaltas];
        final chartRawMax = chartMetrics.reduce((a, b) => a > b ? a : b);
        final chartMaxY = chartRawMax > 0 ? math.max(4.0, (chartRawMax * 1.22).ceilToDouble()) : 4.0;
        final chartGridInterval = chartMaxY <= 6 ? 1.0 : (chartMaxY / 6).ceilToDouble();

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
                // ── Filtros (grelha ultra premium) ──
                _buildReportsFiltersCard(depts),
                if (_periodFilter == 'periodo' && (_periodStart != null || _periodEnd != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _periodStart != null && _periodEnd != null
                            ? 'Intervalo: ${_periodStart!.day}/${_periodStart!.month}/${_periodStart!.year} a ${_periodEnd!.day}/${_periodEnd!.month}/${_periodEnd!.year}'
                            : 'Selecione início e fim',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                      ),
                    ),
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
                        minY: 0,
                        maxY: chartMaxY,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: Colors.white,
                            tooltipRoundedRadius: 12,
                            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            tooltipMargin: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final i = group.x.toInt();
                              final label = _barLabel(i);
                              final c = rod.gradient?.colors.first ?? rod.color ?? ThemeCleanPremium.primary;
                              return BarTooltipItem(
                                '$label\n',
                                TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 11, height: 1.35),
                                children: [
                                  TextSpan(
                                    text: '${rod.toY.round()}',
                                    style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (v, meta) => Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _barLabel(v.toInt()),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                ),
                              ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: chartGridInterval,
                              getTitlesWidget: (v, meta) {
                                if (v < 0 || v > meta.max + 0.001) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1),
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: chartGridInterval,
                          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                        ),
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
                // ── Cards clicáveis: lista detalhada ──
                Row(
                  children: [
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Escalas geradas',
                        value: '$escalasGeradas',
                        icon: Icons.calendar_month_rounded,
                        color: ThemeCleanPremium.primary,
                        onTap: () => _showDrillDown(
                          context,
                          'Todas as escalas (${docs.length})',
                          ThemeCleanPremium.primary,
                          escalaDocs: docs,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Realizadas',
                        value: '$escalasRealizadas',
                        icon: Icons.check_circle_rounded,
                        color: ThemeCleanPremium.success,
                        onTap: () => _showDrillDown(
                          context,
                          'Escalas com todos confirmados (${realizadasDocs.length})',
                          ThemeCleanPremium.success,
                          escalaDocs: realizadasDocs,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Pendentes',
                        value: '$escalasPendentes',
                        icon: Icons.schedule_rounded,
                        color: Colors.amber.shade700,
                        onTap: () => _showDrillDown(
                          context,
                          'Escalas pendentes de confirmação (${pendentesDocs.length})',
                          Colors.amber.shade800,
                          escalaDocs: pendentesDocs,
                        ),
                      ),
                    ),
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
                        onTap: () => _showDrillDown(
                          context,
                          'Presenças (${whoAttended.length} pessoas)',
                          ThemeCleanPremium.success,
                          lines: whoAttended.entries.map((e) => '${e.key} — ${e.value} confirmação(ões)').toList()..sort(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ReportMetricCard(
                        label: 'Faltas',
                        value: '$totalFaltas',
                        icon: Icons.cancel_rounded,
                        color: ThemeCleanPremium.error,
                        onTap: () => _showDrillDown(
                          context,
                          'Faltas / indisponível (${whoMissed.length} pessoas)',
                          ThemeCleanPremium.error,
                          lines: whoMissed.entries.map((e) => '${e.key} — ${e.value} ocorrência(s)').toList()..sort(),
                        ),
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
                        onTap: () => _showDrillDown(
                          context,
                          st.name.isNotEmpty ? st.name : st.cpf,
                          ThemeCleanPremium.primary,
                          lines: [
                            'Escalas: ${st.escalas}',
                            'Presenças: ${st.presencas}',
                            'Faltas: ${st.faltas}',
                          ],
                        ),
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

  void _showDrillDown(
    BuildContext context,
    String title,
    Color accent, {
    List<String>? lines,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? escalaDocs,
  }) {
    assert(lines != null || escalaDocs != null, 'Informe lines ou escalaDocs');
    assert(lines == null || escalaDocs == null, 'Use apenas lines ou escalaDocs');
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final useEscalas = escalaDocs != null;
    final listLines = lines ?? const <String>[];
    final docs = escalaDocs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxH + 56),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, -8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, Color.lerp(accent, Colors.white, 0.22) ?? accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                      boxShadow: [
                        BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            useEscalas ? Icons.event_note_rounded : Icons.insights_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.25,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (useEscalas && docs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                      child: Column(
                        children: [
                          Icon(Icons.inbox_rounded, size: 52, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum registro no período.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  else if (!useEscalas && listLines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
                      child: Column(
                        children: [
                          Icon(Icons.inbox_rounded, size: 52, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum registro no período.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: useEscalas ? docs.length : listLines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          if (useEscalas) {
                            return _EscalaDrillCard(doc: docs[i], accent: accent);
                          }
                          return _PremiumDrillLineTile(line: listLines[i], accent: accent);
                        },
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

      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
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
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
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

  Future<void> _deleteManyInstances(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final toDelete = docs.where(_canDeleteInstance).toList();
    if (toDelete.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhuma escala elegível para exclusão neste conjunto.',
            ),
          ),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Confirmar exclusão em lote'),
        content: Text(
          'Serão excluídas ${toDelete.length} escala(s) gerada(s). '
          'Os modelos de escala não são afetados.',
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
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      for (final d in toDelete) {
        batch.delete(d.reference);
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      if (mounted) {
        _refreshInstances();
        setState(() {
          _escalaSelectionMode = false;
          _selectedEscalaIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            '${toDelete.length} escala(s) excluída(s).',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir em lote: $e')),
        );
      }
    }
  }

  Future<void> _showExclusaoPeriodoDialog(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocsRaw,
  ) async {
    final visivel = _visibleInstancesFromAll(allDocsRaw);
    final poolDept = _deptOnlyPool(allDocsRaw);
    final elegiveisVisivel = visivel.where(_canDeleteInstance).length;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Excluir por período',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Só entram escalas que você pode gerir. '
                  'A lista carrega até 500 escalas recentes.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.filter_alt_rounded,
                      color: ThemeCleanPremium.primary),
                  title: const Text('Todas do filtro atual na lista'),
                  subtitle: Text(
                    '$elegiveisVisivel escala(s) elegível(is) no período/departamento selecionados',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _deleteManyInstances(visivel);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_month_rounded,
                      color: ThemeCleanPremium.primary),
                  title: const Text('Por mês (calendário)…'),
                  subtitle: const Text(
                    'Escolha um dia do mês desejado; todas as escalas daquele mês no departamento filtrado',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: 'Escolha um dia do mês',
                    );
                    if (picked == null || !mounted) return;
                    final monthDocs = _docsForMonthYear(
                      poolDept,
                      picked.year,
                      picked.month,
                    );
                    await _deleteManyInstances(monthDocs);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.date_range_rounded,
                      color: ThemeCleanPremium.primary),
                  title: const Text('Por ano…'),
                  subtitle: const Text(
                    'Todas as escalas daquele ano (departamento filtrado)',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    var sel = DateTime.now().year;
                    final y = await showDialog<int>(
                      context: context,
                      builder: (dctx) {
                        return StatefulBuilder(
                          builder: (context, setSt) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusLg),
                              ),
                              title: const Text('Excluir escalas do ano'),
                              content: DropdownButtonFormField<int>(
                                value: sel,
                                decoration: const InputDecoration(
                                  labelText: 'Ano',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (var i = 2020; i <= 2035; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text('$i'),
                                    ),
                                ],
                                onChanged: (v) => setSt(() => sel = v ?? sel),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dctx),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dctx, sel),
                                  child: const Text('Continuar'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                    if (y == null || !mounted) return;
                    final yearDocs = _docsForYear(poolDept, y);
                    await _deleteManyInstances(yearDocs);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await _exportEscalaInstancePdf(doc);
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                        label: const Text('Imprimir PDF'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          minimumSize: Size(0, ThemeCleanPremium.minTouchTarget),
                        ),
                      ),
                      if (_canWrite) ...[
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
                    ],
                  ),
                  const SizedBox(height: 16),
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

  void _onCalendarDayPicked(BuildContext context, DateTime selected, DateTime focused) {
    onDaySelected(selected, focused);
    final ev = _eventsForDay(selected);
    if (ev.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (ev.length == 1) {
        final esc = ev.first;
        final deptIdx = allDepts.indexWhere(
          (x) => x.id == (esc.data()['departmentId'] ?? '').toString(),
        );
        onOpenDetail(esc, colorForDept(deptIdx.clamp(0, 99)));
        return;
      }
      _showMultiEscalaDaySheet(context, selected, ev);
    });
  }

  void _showMultiEscalaDaySheet(
    BuildContext context,
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> events,
  ) {
    final title = toBeginningOfSentenceCase(
      DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR').format(day),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
        return SizedBox(
          height: maxH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              Text(
                '${events.length} escalas neste dia',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: events.length,
                  itemBuilder: (_, i) {
                    final esc = events[i];
                    final deptIdx = allDepts.indexWhere(
                      (x) => x.id == (esc.data()['departmentId'] ?? '').toString(),
                    );
                    final deptIdInst =
                        (esc.data()['departmentId'] ?? '').toString();
                    final canMutate =
                        canWriteFull || managedDeptIds.contains(deptIdInst);
                    final col = colorForDept(deptIdx.clamp(0, 99));
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _InstanceCard(
                        doc: esc,
                        deptColor: col,
                        currentCpf: currentCpf,
                        canWrite: canMutate,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          onOpenDetail(esc, col);
                        },
                        onEdit: canMutate
                            ? () async {
                                Navigator.of(ctx).pop();
                                await onEdit(esc);
                              }
                            : null,
                        onDelete: canMutate
                            ? () async {
                                Navigator.of(ctx).pop();
                                await onDelete(esc);
                              }
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsForDay(selectedDay);
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final cellFs = isMobile ? 15.0 : 14.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              onDaySelected: (selected, focused) =>
                  _onCalendarDayPicked(context, selected, focused),
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
      ),
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
  final bool canGenerate;
  final VoidCallback onEdit;
  final VoidCallback onGenerate;
  final VoidCallback onDelete;
  const _TemplateCard({required this.doc, required this.deptColor, required this.canWrite, required this.canGenerate, required this.onEdit, required this.onGenerate, required this.onDelete});

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
        gradient: LinearGradient(
          colors: [Colors.white, deptColor.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE8EEF5)),
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
                    if (canWrite && canGenerate)
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
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  const _InstanceCard({
    required this.doc,
    required this.deptColor,
    required this.currentCpf,
    required this.canWrite,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

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
        onTap: () {
          if (selectionMode && canWrite && onSelectionChanged != null) {
            onSelectionChanged!(!selected);
          } else {
            onTap();
          }
        },
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            gradient: selectionMode && selected
                ? LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withOpacity(0.07),
                      Colors.white,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : (!isPast
                    ? LinearGradient(
                        colors: [
                          Colors.white,
                          deptColor.withOpacity(0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null),
            color: selectionMode && selected
                ? null
                : (isPast ? Colors.grey.shade50 : null),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: [
              BoxShadow(
                color: deptColor.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              ...ThemeCleanPremium.softUiCardShadow,
            ],
            border: selectionMode && selected
                ? Border.all(
                    color: ThemeCleanPremium.primary.withOpacity(0.4),
                    width: 1.5,
                  )
                : Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 92,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [deptColor, deptColor.withOpacity(0.75)],
                  ),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(ThemeCleanPremium.radiusLg)),
                  boxShadow: [
                    BoxShadow(color: deptColor.withOpacity(0.35), blurRadius: 8, offset: const Offset(2, 0)),
                  ],
                ),
              ),
              if (selectionMode && canWrite)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => onSelectionChanged?.call(v ?? false),
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
                        if (canWrite && !selectionMode && (onEdit != null || onDelete != null))
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

/// Card premium para detalhe de uma escala no drill-down de relatórios.
class _EscalaDrillCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color accent;

  const _EscalaDrillCard({required this.doc, required this.accent});

  static String _statusLabel(String s) {
    switch (s) {
      case 'confirmado':
        return 'Confirmado';
      case 'indisponivel':
        return 'Indisponível';
      case 'falta_nao_justificada':
        return 'Falta';
      default:
        return 'Pendente';
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'confirmado':
        return ThemeCleanPremium.success;
      case 'indisponivel':
      case 'falta_nao_justificada':
        return ThemeCleanPremium.error;
      default:
        return Colors.amber.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    DateTime? dt;
    try {
      dt = (m['date'] as Timestamp?)?.toDate();
    } catch (_) {}
    final title = (m['title'] ?? 'Escala').toString().trim();
    final dept = (m['departmentName'] ?? '').toString().trim();
    final timeStr = (m['time'] ?? '').toString().trim();
    final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString().trim()).toList();
    final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};

    var nConf = 0;
    var nNeg = 0;
    var nPend = 0;
    for (final cpf in cpfs) {
      final s = (confirmations[cpf] ?? '').toString();
      if (s == 'confirmado') {
        nConf++;
      } else if (s == 'indisponivel' || s == 'falta_nao_justificada') {
        nNeg++;
      } else {
        nPend++;
      }
    }
    final total = cpfs.length;
    final ratio = total > 0 ? nConf / total : 0.0;

    final dayStr = dt != null ? DateFormat('dd').format(dt) : '—';
    final monStr = dt != null ? DateFormat('MMM', 'pt_BR').format(dt) : '';
    final yearStr = dt != null ? DateFormat('yyyy').format(dt) : '';
    final weekdayStr = dt != null ? DateFormat('EEEE', 'pt_BR').format(dt) : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.11), accent.withValues(alpha: 0.03)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, Color.lerp(accent, Colors.white, 0.15) ?? accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayStr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1),
                        ),
                        if (monStr.isNotEmpty)
                          Text(
                            monStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.92)),
                          ),
                        if (yearStr.isNotEmpty)
                          Text(
                            yearStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (weekdayStr.isNotEmpty)
                          Text(
                            weekdayStr,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent.withValues(alpha: 0.85)),
                          ),
                        if (weekdayStr.isNotEmpty) const SizedBox(height: 4),
                        Text(
                          title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface, height: 1.2),
                        ),
                        if (dept.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Icon(Icons.groups_2_rounded, size: 15, color: Colors.grey.shade600),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(dept, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                              ),
                            ],
                          ),
                        ],
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 15, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(timeStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pie_chart_outline_rounded, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'Confirmações',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                      ),
                      const Spacer(),
                      Text(
                        '$nConf / $total',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total > 0 ? ratio : 0,
                      minHeight: 7,
                      backgroundColor: Colors.grey.shade200,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _miniStatChip('Confirmados', nConf, ThemeCleanPremium.success),
                      _miniStatChip('Pendentes', nPend, Colors.amber.shade800),
                      _miniStatChip('Indisp./falta', nNeg, ThemeCleanPremium.error),
                    ],
                  ),
                ],
              ),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_outline_rounded, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Membros ($total)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(total, (i) {
                      final cpf = i < cpfs.length ? cpfs[i] : '';
                      final name = i < names.length && names[i].isNotEmpty ? names[i] : (cpf.isNotEmpty ? cpf : '—');
                      final st = (confirmations[cpf] ?? '').toString();
                      final col = _statusColor(st);
                      return Padding(
                        padding: EdgeInsets.only(bottom: i == total - 1 ? 0 : 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE8EDF4)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: col.withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: col),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: col.withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  _statusLabel(st),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: col),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _miniStatChip(String label, int v, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$v', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

/// Linha premium para listas de texto (presenças, faltas, resumo por membro).
class _PremiumDrillLineTile extends StatelessWidget {
  final String line;
  final Color accent;

  const _PremiumDrillLineTile({required this.line, required this.accent});

  @override
  Widget build(BuildContext context) {
    final emParts = line.split(' — ');
    if (emParts.length == 2) {
      final left = emParts[0].trim();
      final right = emParts[1].trim();
      final initial = left.isNotEmpty ? left[0].toUpperCase() : '?';
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.14),
              child: Text(initial, style: TextStyle(fontWeight: FontWeight.w900, color: accent, fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(left, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Text(right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade800, height: 1.25)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final colonIdx = line.indexOf(':');
    if (colonIdx > 0 && colonIdx < line.length - 1) {
      final k = line.substring(0, colonIdx).trim();
      final v = line.substring(colonIdx + 1).trim();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: 0.08), accent.withValues(alpha: 0.02)],
          ),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          children: [
            Icon(Icons.analytics_outlined, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(k, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: accent)),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Text(line, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35, color: Colors.grey.shade800)),
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 4),
            Icon(Icons.open_in_new_rounded, size: 12, color: color.withOpacity(0.65)),
          ],
        ],
      ),
    );
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          onTap: onTap,
          child: content,
        ),
      );
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
  final bool compact;
  final VoidCallback onTap;
  const _FilterChipDept({
    required this.label,
    required this.selected,
    this.color,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeCleanPremium.primary;
    final padH = compact ? 8.0 : 14.0;
    final padV = compact ? 7.0 : 9.0;
    final fs = compact ? 11.0 : 12.0;
    final r = compact ? 14.0 : 22.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [c, c.withOpacity(0.88)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: selected ? c : Colors.grey.shade300,
              width: selected ? 0 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fs,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
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
