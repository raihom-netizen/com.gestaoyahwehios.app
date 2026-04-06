import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/holiday_footer.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

class CalendarPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Dentro do [IgrejaCleanShell]: sem barra inferior sobreposta ao calendário; ações compactas na linha do modo de vista.
  final bool embeddedInShell;
  const CalendarPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

enum _AgendaViewKind { month, week, list }

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  late DateTime _focusedMonth;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  _AgendaViewKind _agendaView = _AgendaViewKind.month;
  Map<String, List<_CalendarEvent>> _eventsByDay = {};
  Map<String, List<_CalendarEvent>> _legacyEventsByDay = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _agendaDocs = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _agendaSub;
  /// `null` = todas as categorias.
  String? _filterCategoryKey;
  bool _loading = false;
  String? _loadError;
  late final AnimationController _slideCtrl;
  String _listFilter = 'mes_atual';
  DateTime? _periodStart;
  DateTime? _periodEnd;
  List<String> _customTipos = [];

  /// Chaves persistidas no Firestore (`agenda.category`).
  static const Map<String, String> _categoryLabels = {
    'culto': 'Cultos',
    'evento_social': 'Eventos sociais',
    'lideranca': 'Reuniões de liderança',
    'ensino_ebd': 'Ensino / EBD',
  };

  static const Map<String, Color> _categoryColors = {
    'culto': Color(0xFF2563EB),
    'evento_social': Color(0xFFE11D48),
    'lideranca': Color(0xFF7C3AED),
    'ensino_ebd': Color(0xFF16A34A),
  };

  static const _eventColors = {
    'Culto': Color(0xFF3B82F6),
    'Evento': Color(0xFF8B5CF6),
    'Célula': Color(0xFF16A34A),
    'Reunião': Color(0xFFF59E0B),
  };

  static String _colorToHex(Color c) {
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '$r$g$b';
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final r = int.tryParse(h.substring(0, 2), radix: 16);
    final g = int.tryParse(h.substring(2, 4), radix: 16);
    final b = int.tryParse(h.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return Color(0xFF000000 | (r << 16) | (g << 8) | b);
  }

  bool get _embeddedMobile =>
      widget.embeddedInShell && ThemeCleanPremium.isMobile(context);

  bool get _canWrite {
    final r = widget.role.toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'lider' ||
        r == 'pastor' ||
        r == 'pastora' ||
        r == 'secretario' ||
        r == 'presbitero' ||
        r == 'tesoureiro' ||
        r == 'tesouraria' ||
        r == 'diacono' ||
        r == 'evangelista';
  }

  CollectionReference<Map<String, dynamic>> get _agenda =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('agenda');

  CollectionReference<Map<String, dynamic>> get _noticias =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('noticias');

  CollectionReference<Map<String, dynamic>> get _cultos =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('cultos');

  /// Fallback para igrejas que usam collection igrejas (ex.: O Brasil para Cristo)
  CollectionReference<Map<String, dynamic>> get _noticiasIgrejas =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('noticias');
  CollectionReference<Map<String, dynamic>> get _cultosIgrejas =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('cultos');

  static const _keyCustomTipos = 'agenda_tipos_custom';

  Future<void> _loadCustomTipos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_keyCustomTipos}_${widget.tenantId}') ?? '';
    final list = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    if (mounted) setState(() => _customTipos = list);
  }

  List<String> get _allTipos {
    const base = ['Culto', 'Célula', 'Evento', 'Reunião'];
    final merged = <String>{...base, ..._customTipos};
    return merged.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _loadCustomTipos();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _focusedDay = DateTime(now.year, now.month, now.day);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadEvents();
    _restartAgendaSubscription();
  }

  @override
  void dispose() {
    _agendaSub?.cancel();
    _slideCtrl.dispose();
    super.dispose();
  }

  String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Ano exibido no rodapé de feriados: mês focado na grade ou contexto da lista.
  int get _holidayFooterYear {
    if (_agendaView != _AgendaViewKind.list) return _focusedMonth.year;
    final n = DateTime.now();
    switch (_listFilter) {
      case 'mes_anterior':
        final p = DateTime(n.year, n.month - 1);
        return p.year;
      case 'mes_atual':
        return n.year;
      case 'anual':
        return n.year;
      case 'periodo':
        if (_periodStart != null) return _periodStart!.year;
        return n.year;
      default:
        return n.year;
    }
  }

  (DateTime, DateTime) _computeLoadRange() {
    final now = DateTime.now();
    if (_agendaView == _AgendaViewKind.list) {
      switch (_listFilter) {
        case 'mes_anterior':
          final prev = DateTime(now.year, now.month - 1);
          return (DateTime(prev.year, prev.month, 1), DateTime(prev.year, prev.month + 1, 0, 23, 59, 59));
        case 'mes_atual':
          return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
        case 'semanal':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return (weekStart, DateTime(now.year, now.month, now.day, 23, 59, 59));
        case 'diario':
          return (DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
        case 'anual':
          return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
        case 'periodo':
          if (_periodStart != null && _periodEnd != null) {
            return (_periodStart!, DateTime(_periodEnd!.year, _periodEnd!.month, _periodEnd!.day, 23, 59, 59));
          }
          return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
        default:
          return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      }
    }
    return (
      DateTime(_focusedMonth.year, _focusedMonth.month, 1),
      DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0, 23, 59, 59),
    );
  }

  void _restartAgendaSubscription() {
    final (rangeStart, rangeEnd) = _computeLoadRange();
    _agendaSub?.cancel();
    _agendaSub = _agenda
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _agendaDocs = snap.docs);
      _rebuildMerged();
    });
  }

  String _categoryKeyFromLegacyType(String tipo) {
    final n = _normalizeType(tipo);
    final l = n.toLowerCase();
    if (l.contains('culto')) return 'culto';
    if (l.contains('reunião') || l.contains('reuniao')) return 'lideranca';
    if (l.contains('célula') || l.contains('celula')) return 'ensino_ebd';
    if (l.contains('evento')) return 'evento_social';
    return 'evento_social';
  }

  Map<String, List<_CalendarEvent>> _agendaEventsFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final map = <String, List<_CalendarEvent>>{};
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['startTime'] ?? d['startAt'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final key = _dayKey(dt);
      final endRaw = d['endTime'] ?? d['endAt'];
      DateTime? endDt;
      if (endRaw is Timestamp) endDt = endRaw.toDate();
      var cat = (d['category'] ?? 'culto').toString().trim();
      if (!_categoryColors.containsKey(cat)) cat = 'culto';
      var colorHex = (d['color'] ?? '').toString().trim();
      if (colorHex.isEmpty) {
        colorHex = _colorToHex(_categoryColors[cat]!);
      }
      map.putIfAbsent(key, () => []).add(_CalendarEvent(
            id: doc.id,
            title: (d['title'] ?? '').toString(),
            type: _labelForCategoryKey(cat),
            dateTime: dt,
            description: (d['description'] ?? '').toString(),
            source: 'agenda',
            eventColorHex: colorHex,
            categoryKey: cat,
            endDateTime: endDt,
            location: (d['location'] ?? d['local'] ?? '').toString(),
            responsible: (d['responsible'] ?? d['responsavel'] ?? '').toString(),
            needSound: d['needSound'] == true,
            needDataShow: d['needDataShow'] == true,
            needCantina: d['needCantina'] == true,
          ));
    }
    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return map;
  }

  String _labelForCategoryKey(String cat) {
    switch (cat) {
      case 'culto':
        return 'Culto';
      case 'evento_social':
        return 'Evento Social';
      case 'lideranca':
        return 'Reunião de Liderança';
      case 'ensino_ebd':
        return 'Ensino / EBD';
      default:
        return 'Evento';
    }
  }

  Map<String, List<_CalendarEvent>> _mergeDayMaps(
    Map<String, List<_CalendarEvent>> a,
    Map<String, List<_CalendarEvent>> b,
  ) {
    final out = <String, List<_CalendarEvent>>{};
    for (final e in a.entries) {
      out.putIfAbsent(e.key, () => []).addAll(e.value);
    }
    for (final e in b.entries) {
      out.putIfAbsent(e.key, () => []).addAll(e.value);
    }
    for (final list in out.values) {
      list.sort((x, y) => x.dateTime.compareTo(y.dateTime));
    }
    return out;
  }

  Map<String, List<_CalendarEvent>> _applyCategoryFilter(
      Map<String, List<_CalendarEvent>> input) {
    final key = _filterCategoryKey;
    if (key == null) return input;
    final out = <String, List<_CalendarEvent>>{};
    for (final e in input.entries) {
      final filtered =
          e.value.where((ev) => (ev.categoryKey ?? '') == key).toList();
      if (filtered.isNotEmpty) out[e.key] = filtered;
    }
    return out;
  }

  Map<String, List<_CalendarEvent>> _markConflicts(
      Map<String, List<_CalendarEvent>> input) {
    DateTime endOf(_CalendarEvent ev) =>
        ev.endDateTime ?? ev.dateTime.add(const Duration(hours: 2));
    final out = <String, List<_CalendarEvent>>{};
    for (final e in input.entries) {
      final list = e.value;
      final conflict = List<bool>.filled(list.length, false);
      for (var i = 0; i < list.length; i++) {
        final a = list[i];
        final locA = a.location.trim().toLowerCase();
        if (locA.isEmpty) continue;
        final endA = endOf(a);
        for (var j = i + 1; j < list.length; j++) {
          final b = list[j];
          if (b.location.trim().toLowerCase() != locA) continue;
          final endB = endOf(b);
          if (a.dateTime.isBefore(endB) && b.dateTime.isBefore(endA)) {
            conflict[i] = true;
            conflict[j] = true;
          }
        }
      }
      out[e.key] = List.generate(
        list.length,
        (i) => list[i].copyWith(hasConflict: conflict[i]),
      );
    }
    return out;
  }

  void _rebuildMerged() {
    final merged =
        _mergeDayMaps(_legacyEventsByDay, _agendaEventsFromDocs(_agendaDocs));
    final filtered = _applyCategoryFilter(merged);
    final marked = _markConflicts(filtered);
    if (mounted) {
      setState(() => _eventsByDay = marked);
    }
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() { _loading = true; _loadError = null; });
    final (rangeStart, rangeEnd) = _computeLoadRange();
    final start = Timestamp.fromDate(rangeStart);
    final end = Timestamp.fromDate(rangeEnd);

    final map = <String, List<_CalendarEvent>>{};
    String? err;

    void addNoticias(QuerySnapshot<Map<String, dynamic>> snap) {
      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = (d['dataEvento'] ?? d['data']) as Timestamp?;
        if (ts == null) continue;
        final dt = ts.toDate();
        final key = _dayKey(dt);
        final tipo = (d['tipo'] ?? d['type'] ?? 'Evento').toString();
        final eventColor = (d['eventColor'] ?? d['color'] ?? '').toString().trim();
        final ck = _categoryKeyFromLegacyType(tipo);
        map.putIfAbsent(key, () => []).add(_CalendarEvent(
              id: doc.id,
              title: (d['title'] ?? d['titulo'] ?? '').toString(),
              type: _normalizeType(tipo),
              dateTime: dt,
              description: (d['description'] ?? d['descricao'] ?? '').toString(),
              source: 'noticias',
              eventColorHex: eventColor.isEmpty
                  ? _colorToHex(_categoryColors[ck] ?? ThemeCleanPremium.primary)
                  : eventColor,
              categoryKey: ck,
            ));
      }
    }

    void addCultos(QuerySnapshot<Map<String, dynamic>> snap) {
      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = d['data'] as Timestamp?;
        if (ts == null) continue;
        final dt = ts.toDate();
        final key = _dayKey(dt);
        final tipo = (d['tipo'] ?? 'Culto').toString();
        final eventColor = (d['eventColor'] ?? d['color'] ?? '').toString().trim();
        map.putIfAbsent(key, () => []).add(_CalendarEvent(
              id: doc.id,
              title: (d['titulo'] ?? d['title'] ?? tipo).toString(),
              type: _normalizeType(tipo),
              dateTime: dt,
              description: (d['descricao'] ?? d['description'] ?? '').toString(),
              source: 'cultos',
              eventColorHex: eventColor.isEmpty
                  ? _colorToHex(_categoryColors['culto']!)
                  : eventColor,
              categoryKey: 'culto',
            ));
      }
    }

    const timeoutDuration = Duration(seconds: 12);

    try {
      final noticiasSnap = await _noticias
          .where('dataEvento', isGreaterThanOrEqualTo: start)
          .where('dataEvento', isLessThanOrEqualTo: end)
          .get()
          .timeout(timeoutDuration);
      addNoticias(noticiasSnap);
    } catch (e) {
      err ??= e is TimeoutException ? 'Tempo esgotado ao carregar eventos.' : e.toString();
      try {
        final snap = await _noticiasIgrejas
            .where('dataEvento', isGreaterThanOrEqualTo: start)
            .where('dataEvento', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
        addNoticias(snap);
        err = null;
      } catch (_) {}
    }

    try {
      final cultosSnap = await _cultos
          .where('data', isGreaterThanOrEqualTo: start)
          .where('data', isLessThanOrEqualTo: end)
          .get()
          .timeout(timeoutDuration);
      addCultos(cultosSnap);
    } catch (e) {
      err ??= e is TimeoutException ? 'Tempo esgotado ao carregar eventos.' : e.toString();
      try {
        final snap = await _cultosIgrejas
            .where('data', isGreaterThanOrEqualTo: start)
            .where('data', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
        addCultos(snap);
        err = null;
      } catch (_) {}
    }

    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }

    if (mounted) {
      setState(() {
        _legacyEventsByDay = map;
        _loading = false;
        _loadError = err;
      });
      _rebuildMerged();
    }
  }

  String _normalizeType(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Evento';
    if (_allTipos.contains(t)) return t;
    final l = t.toLowerCase();
    if (l.contains('culto')) return 'Culto';
    if (l.contains('célula') || l.contains('celula')) return 'Célula';
    if (l.contains('reunião') || l.contains('reuniao')) return 'Reunião';
    return t; // preserve custom types
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final showAppBar = !isMobile || Navigator.canPop(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = ThemeCleanPremium.pagePadding(context);
    final useSplitCalendar =
        _agendaView != _AgendaViewKind.list && (isMobile || wide);
    final showBottomBar =
        isMobile && _agendaView != _AgendaViewKind.list && !_embeddedMobile;

    return Scaffold(
      appBar: !showAppBar
          ? null
          : AppBar(
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              title: Text(
                'Agenda inteligente',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              actions: [
                if (_agendaView != _AgendaViewKind.list) ...[
                  IconButton(
                    tooltip: 'Exportar PDF',
                    onPressed: _exportAgendaPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                  ),
                  if (_canWrite)
                    IconButton(
                      tooltip: 'Novo evento',
                      onPressed: () => _showAddEvent(),
                      icon: const Icon(Icons.add_rounded),
                    ),
                ],
              ],
            ),
      floatingActionButton: _canWrite &&
              !showBottomBar &&
              !useSplitCalendar &&
              !_embeddedMobile
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEvent(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo evento'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      bottomNavigationBar: showBottomBar
          ? SafeArea(
              child: Material(
                elevation: 8,
                color: ThemeCleanPremium.cardBackground,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportAgendaPdf,
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                          label: Text('PDF', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                          ),
                        ),
                      ),
                      if (_canWrite) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () => _showAddEvent(),
                            icon: const Icon(Icons.add_rounded, size: 22),
                            label: Text('Novo evento', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: useSplitCalendar
            ? Padding(
                padding: pad,
                child: _buildSplitCalendarBody(wide: wide, isMobile: isMobile),
              )
            : RefreshIndicator(
                onRefresh: _loadEvents,
                child: ListView(
                  padding: pad,
                  children: [
                    if (_embeddedMobile && _agendaView == _AgendaViewKind.list) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: _embeddedAgendaIconActions(),
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (isMobile && !_embeddedMobile) ...[
                      Text(
                        'Agenda inteligente',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                    ],
                    if (_loadError != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                        child: ChurchPanelErrorBody(
                          title: 'Não foi possível carregar alguns eventos',
                          error: _loadError,
                          onRetry: _loadEvents,
                        ),
                      ),
                    ],
                    _buildViewToggleRow(),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    _buildCategoryFilterRow(),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _agendaView == _AgendaViewKind.list
                          ? Column(
                              key: const ValueKey('list'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildListFilters(),
                                const SizedBox(height: ThemeCleanPremium.spaceSm),
                                _buildListView(key: const ValueKey('listcontent')),
                              ],
                            )
                          : _buildCalendarStacked(key: const ValueKey('calendar')),
                    ),
                    SizedBox(
                        height: (isMobile && !_embeddedMobile)
                            ? 88
                            : ThemeCleanPremium.spaceLg),
                    HolidayFooter(year: _holidayFooterYear),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                  ],
                ),
              ),
      ),
    );
  }

  /// Calendário em cima (altura generosa), resumo do dia + mês abaixo — web largo em duas colunas.
  Widget _buildSplitCalendarBody({required bool wide, required bool isMobile}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * 0.55;
        final frac = _embeddedMobile ? 0.48 : 0.36;
        final calendarH = wide
            ? math.min(440.0, math.max(300.0, maxH * 0.36))
            : math.min(460.0, math.max(260.0, maxH * frac));

        Widget calendarBlock() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadError != null)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                    child: ChurchPanelErrorBody(
                      title: 'Não foi possível carregar alguns eventos',
                      error: _loadError,
                      onRetry: _loadEvents,
                    ),
                  ),
                _buildViewToggleRow(),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                _buildCategoryFilterRow(),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                SizedBox(
                  height: calendarH,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: _buildCalendarTopOnly(),
                  ),
                ),
              ],
            );

        final detailsBottomPad =
            isMobile && !_embeddedMobile ? 72.0 : ThemeCleanPremium.spaceMd;

        Widget detailsBlock() => RefreshIndicator(
              onRefresh: _loadEvents,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: ThemeCleanPremium.spaceSm),
                children: [
                  Text(
                    'Resumo do dia',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 17 : 16,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  _buildSelectedDayEvents(),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text(
                    'Resumo do mês',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 17 : 16,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  _buildFocusedMonthSummary(),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  HolidayFooter(year: _holidayFooterYear),
                  SizedBox(height: detailsBottomPad),
                ],
              ),
            );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: SingleChildScrollView(
                  child: calendarBlock(),
                ),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceMd),
              Expanded(flex: 9, child: detailsBlock()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMobile && !_embeddedMobile)
              Padding(
                padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                child: Text(
                  'Agenda inteligente',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            calendarBlock(),
            Expanded(child: detailsBlock()),
          ],
        );
      },
    );
  }

  /// PDF + novo evento compactos (painel igreja no telefone — evita barra inferior sobre o calendário).
  Widget _embeddedAgendaIconActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Exportar PDF',
          onPressed: _exportAgendaPdf,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(ThemeCleanPremium.minTouchTarget, 44),
          ),
        ),
        if (_canWrite)
          IconButton(
            tooltip: 'Novo evento',
            onPressed: () => _showAddEvent(),
            icon: const Icon(Icons.add_circle_outline_rounded),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, 44),
            ),
          ),
      ],
    );
  }

  Widget _buildViewToggleRow() {
    final core = _buildViewToggleCore();
    if (_embeddedMobile && _agendaView != _AgendaViewKind.list) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: core),
          _embeddedAgendaIconActions(),
        ],
      );
    }
    return core;
  }

  Widget _buildViewToggleCore() {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
              child: _toggleBtn(
                  'Mês',
                  Icons.calendar_month_rounded,
                  _agendaView == _AgendaViewKind.month,
                  () => setState(() => _agendaView = _AgendaViewKind.month))),
          Expanded(
              child: _toggleBtn(
                  'Semana',
                  Icons.view_week_rounded,
                  _agendaView == _AgendaViewKind.week,
                  () => setState(() => _agendaView = _AgendaViewKind.week))),
          Expanded(
              child: _toggleBtn(
                  'Agenda',
                  Icons.view_agenda_rounded,
                  _agendaView == _AgendaViewKind.list,
                  () {
                    setState(() => _agendaView = _AgendaViewKind.list);
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _loadEvents());
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _restartAgendaSubscription());
                  })),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('Todas',
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              selected: _filterCategoryKey == null,
              onSelected: (_) {
                _filterCategoryKey = null;
                _rebuildMerged();
              },
              selectedColor: ThemeCleanPremium.primary.withOpacity(0.18),
              checkmarkColor: ThemeCleanPremium.primary,
            ),
          ),
          for (final e in _categoryLabels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(_iconForCategoryKey(e.key),
                    size: 16, color: _categoryColors[e.key]),
                label: Text(e.value,
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                selected: _filterCategoryKey == e.key,
                onSelected: (_) {
                  _filterCategoryKey =
                      _filterCategoryKey == e.key ? null : e.key;
                  _rebuildMerged();
                },
                selectedColor:
                    (_categoryColors[e.key] ?? ThemeCleanPremium.primary)
                        .withOpacity(0.2),
                checkmarkColor: _categoryColors[e.key],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForCategoryKey(String key) {
    switch (key) {
      case 'culto':
        return Icons.church_rounded;
      case 'evento_social':
        return Icons.celebration_rounded;
      case 'lideranca':
        return Icons.groups_rounded;
      case 'ensino_ebd':
        return Icons.menu_book_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Widget _toggleBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        onTap();
        if (_agendaView != _AgendaViewKind.list) {
          _loadEvents();
          _restartAgendaSubscription();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? ThemeCleanPremium.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm - 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : ThemeCleanPremium.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: active ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
            )),
          ],
        ),
      ),
    );
  }

  // ─── Calendário (table_calendar) — mês / semana ────────────────────────────

  /// Só a grade (uso no layout “calendário em cima”).
  Widget _buildCalendarTopOnly({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTableCalendarCard(),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(ThemeCleanPremium.spaceSm),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// Lista vertical única (modo sem split): calendário + dia + resumo mês.
  Widget _buildCalendarStacked({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCalendarTopOnly(),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        Text(
          'Resumo do dia',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        _buildSelectedDayEvents(),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        Text(
          'Resumo do mês',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        _buildFocusedMonthSummary(),
      ],
    );
  }

  Widget _buildTableCalendarCard() {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final calFormat = _agendaView == _AgendaViewKind.week
        ? CalendarFormat.week
        : CalendarFormat.month;
    final rowH = isMobile ? 52.0 : 46.0;
    final dowH = isMobile ? 30.0 : 26.0;
    final cellFs = isMobile ? 15.5 : 14.0;
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: TableCalendar<_CalendarEvent>(
          locale: 'pt_BR',
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2036, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (d) =>
              _selectedDay != null && isSameDay(_selectedDay!, d),
          calendarFormat: calFormat,
          availableGestures: AvailableGestures.all,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          rowHeight: rowH,
          daysOfWeekHeight: dowH,
          eventLoader: (day) => _eventsByDay[_dayKey(day)] ?? const [],
          calendarStyle: CalendarStyle(
            outsideDaysVisible: true,
            cellMargin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            defaultTextStyle: GoogleFonts.poppins(
              fontSize: cellFs,
              fontWeight: FontWeight.w600,
              color: ThemeCleanPremium.onSurface,
            ),
            weekendTextStyle: GoogleFonts.poppins(
              fontSize: cellFs,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
            todayDecoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: ThemeCleanPremium.primary, width: 2),
            ),
            todayTextStyle: GoogleFonts.poppins(
              fontSize: cellFs,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.primary,
            ),
            selectedDecoration: BoxDecoration(
              color: ThemeCleanPremium.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            selectedTextStyle: GoogleFonts.poppins(
              fontSize: cellFs,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            markerSize: isMobile ? 6 : 5,
            markersMaxCount: 4,
            markersAlignment: Alignment.bottomCenter,
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: GoogleFonts.poppins(
              fontSize: isMobile ? 13 : 12,
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
            weekendStyle: GoogleFonts.poppins(
              fontSize: isMobile ? 13 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
            ),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            leftChevronPadding: EdgeInsets.zero,
            rightChevronPadding: EdgeInsets.zero,
            titleTextStyle: GoogleFonts.poppins(
              fontSize: isMobile ? 19 : 17,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              final limited = events.take(4).toList();
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: limited.map((ev) {
                    final e = ev;
                    final c = _hexToColor(e.eventColorHex) ??
                        _categoryColors[e.categoryKey ?? ''] ??
                        ThemeCleanPremium.primary;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
              _focusedMonth = DateTime(focused.year, focused.month, 1);
            });
          },
          onPageChanged: (focused) {
            _focusedDay = focused;
            _focusedMonth = DateTime(focused.year, focused.month, 1);
            _loadEvents();
            _restartAgendaSubscription();
          },
        ),
      ),
    );
  }

  // ─── Selected Day Events ───────────────────────────────────────────────────

  Widget _buildSelectedDayEvents() {
    if (_selectedDay == null) {
      return _emptyDayMessage('Selecione um dia para ver os eventos');
    }
    final key = _dayKey(_selectedDay!);
    final events = _eventsByDay[key] ?? [];
    final label = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDay!);
    final holidayName = HolidayHelper.holidayNameOn(_selectedDay!);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
            child: Text(
              label[0].toUpperCase() + label.substring(1),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.onSurface,
              ),
            ),
          ),
          if (holidayName != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeCleanPremium.spaceMd,
                vertical: ThemeCleanPremium.spaceSm,
              ),
              margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2).withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                border: Border.all(
                  color: const Color(0xFFFECACA).withValues(alpha: 0.9),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_rounded,
                      size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Feriado nacional: $holidayName',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (events.isEmpty)
            _emptyDayMessage('Nenhum evento neste dia')
          else
            ...events.map(_buildEventCard),
        ],
      ),
    );
  }

  Widget _emptyDayMessage(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          Text(msg, style: TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            fontSize: 14,
          )),
        ],
      ),
    );
  }

  Widget _buildEventCard(_CalendarEvent ev) {
    final color = _CalendarPageState._hexToColor(ev.eventColorHex) ?? _eventColors[ev.type] ?? ThemeCleanPremium.primaryLight;
    final time = DateFormat('HH:mm').format(ev.dateTime);

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: GestureDetector(
        onTap: () => _showEventDetails(ev),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: ev.hasConflict
                ? Border.all(color: Colors.deepOrange.shade400, width: 1.5)
                : null,
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ev.title.isNotEmpty ? ev.title : ev.type,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: ThemeCleanPremium.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 16, color: ThemeCleanPremium.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(time,
                                      style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: ThemeCleanPremium.onSurfaceVariant)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _typeBadge(ev.type, color),
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
  }

  Widget _typeBadge(String type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(type, style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      )),
    );
  }

  /// Totais e contagem por categoria no mês visível no calendário.
  Widget _buildFocusedMonthSummary() {
    final y = _focusedMonth.year;
    final m = _focusedMonth.month;
    var total = 0;
    final byCat = <String, int>{};
    for (final e in _eventsByDay.entries) {
      DateTime? d;
      try {
        d = DateFormat('yyyy-MM-dd').parse(e.key);
      } catch (_) {
        continue;
      }
      if (d.year != y || d.month != m) continue;
      for (final ev in e.value) {
        total++;
        final ck = (ev.categoryKey ?? 'outro').trim();
        byCat[ck] = (byCat[ck] ?? 0) + 1;
      }
    }
    final rawMonth = DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth);
    final monthLabel =
        rawMonth.isEmpty ? '' : '${rawMonth[0].toUpperCase()}${rawMonth.substring(1)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  monthLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            total == 0
                ? 'Nenhum evento neste mês na faixa carregada.'
                : '$total evento${total == 1 ? '' : 's'} no mês',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.primary,
            ),
          ),
          if (total > 0 && byCat.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...byCat.entries.map((en) {
              final label = _categoryLabels[en.key] ?? en.key;
              final col = _categoryColors[en.key] ?? ThemeCleanPremium.onSurfaceVariant;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${en.value}',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ─── List Filters ─────────────────────────────────────────────────────────────

  Widget _buildListFilters() {
    final chips = [
      ('Mês anterior', 'mes_anterior'),
      ('Mês atual', 'mes_atual'),
      ('Semanal', 'semanal'),
      ('Diário', 'diario'),
      ('Anual', 'anual'),
      ('Por período', 'periodo'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (final (label, value) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(value == 'periodo' && _periodStart != null && _periodEnd != null
                    ? '${_periodStart!.day}/${_periodStart!.month} - ${_periodEnd!.day}/${_periodEnd!.month}'
                    : label),
                selected: _listFilter == value,
                onSelected: (v) async {
                  if (value == 'periodo') {
                    final start = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (start == null || !mounted) return;
                    final end = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: start,
                      lastDate: DateTime(2035),
                    );
                    if (end != null && mounted) {
                      setState(() {
                        _listFilter = 'periodo';
                        _periodStart = start;
                        _periodEnd = end;
                      });
                      _loadEvents();
                      _restartAgendaSubscription();
                    }
                  } else {
                    setState(() => _listFilter = value);
                    _loadEvents();
                    _restartAgendaSubscription();
                  }
                },
              ),
            ),
          if (_canWrite)
            IconButton(
              tooltip: 'Exportar PDF',
              onPressed: _exportAgendaPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded),
            ),
        ],
      ),
    );
  }

  Future<void> _exportAgendaPdf() async {
    try {
      final sortedKeys = _eventsByDay.keys.toList()..sort();
      if (sortedKeys.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum evento para exportar.')),
        );
        return;
      }
      final pdf = pw.Document();
      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue100),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Data', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Horário', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Título', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Tipo', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          ],
        ),
      ];
      for (final key in sortedKeys) {
        final events = _eventsByDay[key]!;
        for (final ev in events) {
          rows.add(pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(DateFormat('dd/MM/yyyy').format(ev.dateTime), style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(DateFormat('HH:mm').format(ev.dateTime), style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(ev.title.isNotEmpty ? ev.title : ev.type, style: const pw.TextStyle(fontSize: 9), maxLines: 2)),
              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(ev.type, style: const pw.TextStyle(fontSize: 9))),
            ],
          ));
        }
      }
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) {
            final refMonth = DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth);
            return [
              pw.Header(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Agenda — Gestão YAHWEH',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Referência: $refMonth', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.Table(border: pw.TableBorder.all(width: 0.5), children: rows),
            ];
          },
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) {
        final fn =
            'agenda_${_focusedMonth.year}_${_focusedMonth.month.toString().padLeft(2, '0')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await showPdfActions(context, bytes: bytes, filename: fn);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  // ─── List View ─────────────────────────────────────────────────────────────

  Widget _buildListView({Key? key}) {
    final sortedKeys = _eventsByDay.keys.toList()..sort();
    if (sortedKeys.isEmpty && !_loading) {
      return _emptyDayMessage('Nenhum evento neste mês');
    }

    return Column(
      key: key,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: ChurchPanelLoadingBody(),
          ),
        for (final dayKey in sortedKeys) ...[
          _buildDaySection(dayKey),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
        ],
      ],
    );
  }

  Widget _buildDaySection(String dayKey) {
    final date = DateTime.parse(dayKey);
    final label = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(date);
    final events = _eventsByDay[dayKey]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            bottom: ThemeCleanPremium.spaceXs,
            top: ThemeCleanPremium.spaceXs,
          ),
          child: Text(
            label[0].toUpperCase() + label.substring(1),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
        ),
        ...events.map(_buildEventCard),
      ],
    );
  }

  // ─── Event Details Bottom Sheet ────────────────────────────────────────────

  String _googleCalendarUrlForEvent(_CalendarEvent ev) {
    final end = ev.endDateTime ?? ev.dateTime.add(const Duration(hours: 2));
    String fmt(DateTime d) {
      final u = d.toUtc();
      String p2(int n) => n.toString().padLeft(2, '0');
      return '${u.year.toString().padLeft(4, '0')}${p2(u.month)}${p2(u.day)}T${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
    }
    return Uri.parse('https://www.google.com/calendar/render').replace(
      queryParameters: {
        'action': 'TEMPLATE',
        'text': ev.title.isNotEmpty ? ev.title : ev.type,
        'dates': '${fmt(ev.dateTime)}/${fmt(end)}',
        'details': ev.description,
        'location': ev.location,
      },
    ).toString();
  }

  Future<void> _openGoogleCalendarWeb(_CalendarEvent ev) async {
    final u = Uri.parse(_googleCalendarUrlForEvent(ev));
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  void _showEventDetails(_CalendarEvent ev) {
    final color = _hexToColor(ev.eventColorHex) ??
        _eventColors[ev.type] ??
        ThemeCleanPremium.primaryLight;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusXl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          ThemeCleanPremium.spaceLg,
          ThemeCleanPremium.spaceMd,
          ThemeCleanPremium.spaceLg,
          MediaQuery.of(ctx).viewInsets.bottom + ThemeCleanPremium.spaceLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              if (ev.hasConflict)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepOrange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.deepOrange.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Possível conflito: outro evento no mesmo local e horário sobreposto.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepOrange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  ),
                  child: Icon(_iconForType(ev.type), color: color),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.title.isNotEmpty ? ev.title : ev.type,
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: ThemeCleanPremium.onSurface),
                    ),
                    const SizedBox(height: 2),
                    _typeBadge(ev.type, color),
                  ],
                )),
              ]),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _detailRow(Icons.calendar_today_rounded,
                  DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(ev.dateTime)),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              _detailRow(
                  Icons.access_time_rounded,
                  ev.endDateTime != null
                      ? '${DateFormat('HH:mm').format(ev.dateTime)} — ${DateFormat('HH:mm').format(ev.endDateTime!)}'
                      : DateFormat('HH:mm').format(ev.dateTime)),
              if (ev.location.trim().isNotEmpty) ...[
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                _detailRow(Icons.place_rounded, ev.location.trim()),
              ],
              if (ev.responsible.trim().isNotEmpty) ...[
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                _detailRow(Icons.person_rounded, ev.responsible.trim()),
              ],
              if (ev.needSound || ev.needDataShow || ev.needCantina) ...[
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (ev.needSound)
                      Chip(
                          label: const Text('Som'),
                          visualDensity: VisualDensity.compact),
                    if (ev.needDataShow)
                      Chip(
                          label: const Text('DataShow'),
                          visualDensity: VisualDensity.compact),
                    if (ev.needCantina)
                      Chip(
                          label: const Text('Cantina'),
                          visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
              if (ev.description.isNotEmpty) ...[
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                Text(
                  ev.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: ThemeCleanPremium.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              if (kIsWeb)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openGoogleCalendarWeb(ev),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('Abrir no Google Agenda (web)'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final end =
                          ev.endDateTime ?? ev.dateTime.add(const Duration(hours: 2));
                      final ok = await EventoCalendarIntegration.addEventToDeviceCalendar(
                        title: ev.title.isNotEmpty ? ev.title : ev.type,
                        start: ev.dateTime,
                        end: end,
                        location: ev.location,
                        description: ev.description,
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Siga as instruções do sistema para concluir.'
                                : 'Não foi possível abrir o calendário.')));
                      }
                    },
                    icon: const Icon(Icons.event_available_rounded, size: 20),
                    label: const Text('Adicionar ao meu calendário'),
                  ),
                ),
              if (_canWrite && ev.source == 'agenda') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Excluir evento da agenda?'),
                          content: const Text(
                              'Esta ação remove o item da coleção agenda (não afeta posts antigos do mural).'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(dctx, false),
                                child: const Text('Cancelar')),
                            FilledButton(
                                onPressed: () => Navigator.pop(dctx, true),
                                child: const Text('Excluir')),
                          ],
                        ),
                      );
                      if (ok == true && ctx.mounted) {
                        try {
                          await _agenda.doc(ev.id).delete();
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Erro: $e')));
                          }
                        }
                      }
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: ThemeCleanPremium.error),
                    label: Text('Excluir da agenda',
                        style: TextStyle(color: ThemeCleanPremium.error)),
                  ),
                ),
              ],
              const SizedBox(height: ThemeCleanPremium.spaceSm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 18, color: ThemeCleanPremium.onSurfaceVariant),
      const SizedBox(width: ThemeCleanPremium.spaceSm),
      Flexible(child: Text(text, style: const TextStyle(
        fontSize: 14,
        color: ThemeCleanPremium.onSurface,
      ))),
    ]);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Culto':
        return Icons.church_rounded;
      case 'Evento Social':
        return Icons.celebration_rounded;
      case 'Reunião de Liderança':
        return Icons.groups_rounded;
      case 'Ensino / EBD':
        return Icons.menu_book_rounded;
      case 'Célula':
        return Icons.groups_rounded;
      case 'Reunião':
        return Icons.meeting_room_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  List<DateTime> _expandAgendaRecurrence(DateTime first, String mode,
      {int maxOccurrences = 24}) {
    final out = <DateTime>[first];
    if (mode == 'none' || maxOccurrences <= 1) return out;
    var cur = first;
    for (var k = 1; k < maxOccurrences; k++) {
      if (mode == 'weekly') {
        cur = cur.add(const Duration(days: 7));
      } else if (mode == 'biweekly') {
        cur = cur.add(const Duration(days: 14));
      } else if (mode == 'monthly') {
        cur = cur.add(const Duration(days: 30));
      } else {
        break;
      }
      out.add(cur);
    }
    return out;
  }

  // ─── Novo evento → coleção agenda (+ opcional mural) ───────────────────────

  Future<void> _showAddEvent() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final respCtrl = TextEditingController();
    final startTimeNotifier = ValueNotifier<String>('19:00');
    final endTimeNotifier = ValueNotifier<String>('21:00');
    final categoryNotifier = ValueNotifier<String>('culto');
    final dateNotifier = ValueNotifier<DateTime>(_selectedDay ?? DateTime.now());
    final recurrenceNotifier = ValueNotifier<String>('none');
    final publishMuralNotifier = ValueNotifier<bool>(false);
    final needSound = ValueNotifier<bool>(false);
    final needDataShow = ValueNotifier<bool>(false);
    final needCantina = ValueNotifier<bool>(false);
    final saving = ValueNotifier<bool>(false);

    final savedDate = await showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusXl)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ThemeCleanPremium.spaceLg,
            ThemeCleanPremium.spaceMd,
            ThemeCleanPremium.spaceLg,
            MediaQuery.viewInsetsOf(ctx).bottom + ThemeCleanPremium.spaceLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
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
              )),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              Text('Novo evento (agenda)',
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextField(
                controller: titleCtrl,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              ValueListenableBuilder<String>(
                valueListenable: categoryNotifier,
                builder: (_, cat, __) => DropdownButtonFormField<String>(
                  value: cat,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    prefixIcon: Icon(Icons.palette_rounded),
                  ),
                  items: _categoryLabels.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) categoryNotifier.value = v;
                  },
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              ValueListenableBuilder<DateTime>(
                valueListenable: dateNotifier,
                builder: (_, date, __) => InkWell(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) dateNotifier.value = picked;
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                    child: Text(DateFormat('dd/MM/yyyy').format(date)),
                  ),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: startTimeNotifier,
                      builder: (_, timeStr, __) => InkWell(
                        onTap: () async {
                          final parts = timeStr.split(':');
                          final hour =
                              int.tryParse(parts.elementAtOrNull(0) ?? '') ??
                                  19;
                          final minute =
                              int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime:
                                TimeOfDay(hour: hour, minute: minute),
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (t != null) {
                            startTimeNotifier.value =
                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                          }
                        },
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Início',
                            prefixIcon: Icon(Icons.schedule_rounded),
                          ),
                          child: Text(timeStr),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: endTimeNotifier,
                      builder: (_, timeStr, __) => InkWell(
                        onTap: () async {
                          final parts = timeStr.split(':');
                          final hour =
                              int.tryParse(parts.elementAtOrNull(0) ?? '') ??
                                  21;
                          final minute =
                              int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime:
                                TimeOfDay(hour: hour, minute: minute),
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (t != null) {
                            endTimeNotifier.value =
                                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                          }
                        },
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Término',
                            prefixIcon: Icon(Icons.schedule_send_rounded),
                          ),
                          child: Text(timeStr),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'Dica: término antes do início no mesmo dia vira dia seguinte (ex.: 19h–08h).',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              TextField(
                controller: locCtrl,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Local / sala',
                  prefixIcon: Icon(Icons.place_rounded),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              TextField(
                controller: respCtrl,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Responsável',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Text('Recursos', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
              ValueListenableBuilder<bool>(
                valueListenable: needSound,
                builder: (_, v, __) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Som'),
                  value: v,
                  onChanged: (x) => needSound.value = x,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: needDataShow,
                builder: (_, v, __) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('DataShow'),
                  value: v,
                  onChanged: (x) => needDataShow.value = x,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: needCantina,
                builder: (_, v, __) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cantina'),
                  value: v,
                  onChanged: (x) => needCantina.value = x,
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: recurrenceNotifier,
                builder: (_, rec, __) => DropdownButtonFormField<String>(
                  value: rec,
                  decoration: const InputDecoration(
                    labelText: 'Recorrência',
                    prefixIcon: Icon(Icons.repeat_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Não repetir')),
                    DropdownMenuItem(
                        value: 'weekly', child: Text('Semanal')),
                    DropdownMenuItem(
                        value: 'biweekly', child: Text('Quinzenal')),
                    DropdownMenuItem(
                        value: 'monthly', child: Text('Mensal')),
                  ],
                  onChanged: (v) {
                    if (v != null) recurrenceNotifier.value = v;
                  },
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: publishMuralNotifier,
                builder: (_, v, __) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicar também no Mural (avisos/eventos)'),
                  subtitle: const Text(
                      'Cria um post tipo evento visível no feed da igreja.'),
                  value: v,
                  onChanged: (x) => publishMuralNotifier.value = x,
                ),
              ),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  prefixIcon: Icon(Icons.description_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              ValueListenableBuilder<bool>(
                valueListenable: saving,
                builder: (_, isSaving, __) => FilledButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (titleCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Informe o título')),
                            );
                            return;
                          }
                          saving.value = true;
                          try {
                            await FirebaseAuth.instance.currentUser
                                ?.getIdToken(true);
                            final date = dateNotifier.value;
                            final sp = startTimeNotifier.value.split(':');
                            final ep = endTimeNotifier.value.split(':');
                            final sh =
                                int.tryParse(sp.elementAtOrNull(0) ?? '') ??
                                    19;
                            final sm =
                                int.tryParse(sp.elementAtOrNull(1) ?? '') ?? 0;
                            final eh =
                                int.tryParse(ep.elementAtOrNull(0) ?? '') ??
                                    21;
                            final em =
                                int.tryParse(ep.elementAtOrNull(1) ?? '') ?? 0;
                            final startBase = DateTime(
                                date.year, date.month, date.day, sh, sm);
                            var endBase = DateTime(
                                date.year, date.month, date.day, eh, em);
                            if (!endBase.isAfter(startBase)) {
                              endBase =
                                  endBase.add(const Duration(days: 1));
                            }
                            if (!endBase.isAfter(startBase)) {
                              saving.value = false;
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Revise os horários de início e fim.'),
                                  ),
                                );
                              }
                              return;
                            }
                            final dur = endBase.difference(startBase);
                            final cat = categoryNotifier.value;
                            final colorHex = _colorToHex(
                                _categoryColors[cat] ??
                                    ThemeCleanPremium.primary);
                            final rec = recurrenceNotifier.value;
                            final starts =
                                _expandAgendaRecurrence(startBase, rec);
                            final batch = FirebaseFirestore.instance.batch();
                            final seriesId = _agenda.doc().id;
                            for (final st in starts) {
                              final en = st.add(dur);
                              final ref = _agenda.doc();
                              batch.set(ref, {
                                'title': titleCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'startTime': Timestamp.fromDate(st),
                                'endTime': Timestamp.fromDate(en),
                                'color': colorHex,
                                'category': cat,
                                'location': locCtrl.text.trim(),
                                'responsible': respCtrl.text.trim(),
                                'needSound': needSound.value,
                                'needDataShow': needDataShow.value,
                                'needCantina': needCantina.value,
                                'recurrence': rec,
                                'seriesId': seriesId,
                                'createdAt': FieldValue.serverTimestamp(),
                                'createdByUid':
                                    FirebaseAuth.instance.currentUser?.uid ??
                                        '',
                              });
                            }
                            await batch.commit();
                            if (publishMuralNotifier.value) {
                              await _noticias.add({
                                'type': 'evento',
                                'title': titleCtrl.text.trim(),
                                'text': descCtrl.text.trim(),
                                'startAt': Timestamp.fromDate(startBase),
                                'dataEvento': Timestamp.fromDate(startBase),
                                'description': descCtrl.text.trim(),
                                'active': true,
                                'publicSite': true,
                                'generated': false,
                                'likes': <String>[],
                                'rsvp': <String>[],
                                'createdAt': FieldValue.serverTimestamp(),
                                'createdByUid':
                                    FirebaseAuth.instance.currentUser?.uid ??
                                        '',
                                'likesCount': 0,
                                'rsvpCount': 0,
                                'commentsCount': 0,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  ThemeCleanPremium.successSnackBar(
                                      'Evento salvo na agenda.'));
                              final d = dateNotifier.value;
                              Navigator.pop(
                                ctx,
                                DateTime(d.year, d.month, d.day),
                              );
                            }
                          } catch (e) {
                            saving.value = false;
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text('Erro ao salvar: $e')),
                              );
                            }
                          } finally {
                            saving.value = false;
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    isSaving ? 'Salvando...' : 'Salvar na agenda',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (savedDate != null) {
      setState(() {
        _selectedDay =
            DateTime(savedDate.year, savedDate.month, savedDate.day);
        _focusedDay = _selectedDay!;
        _focusedMonth = DateTime(savedDate.year, savedDate.month, 1);
      });
      await _loadEvents();
      _restartAgendaSubscription();
    }
  }
}

// ─── Calendar Event Model ─────────────────────────────────────────────────────

class _CalendarEvent {
  final String id;
  final String title;
  final String type;
  final DateTime dateTime;
  final String description;
  final String source;
  final String? eventColorHex;
  final String? categoryKey;
  final DateTime? endDateTime;
  final String location;
  final String responsible;
  final bool needSound;
  final bool needDataShow;
  final bool needCantina;
  final bool hasConflict;

  const _CalendarEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.dateTime,
    required this.description,
    required this.source,
    this.eventColorHex,
    this.categoryKey,
    this.endDateTime,
    this.location = '',
    this.responsible = '',
    this.needSound = false,
    this.needDataShow = false,
    this.needCantina = false,
    this.hasConflict = false,
  });

  _CalendarEvent copyWith({
    bool? hasConflict,
    String? eventColorHex,
  }) {
    return _CalendarEvent(
      id: id,
      title: title,
      type: type,
      dateTime: dateTime,
      description: description,
      source: source,
      eventColorHex: eventColorHex ?? this.eventColorHex,
      categoryKey: categoryKey,
      endDateTime: endDateTime,
      location: location,
      responsible: responsible,
      needSound: needSound,
      needDataShow: needDataShow,
      needCantina: needCantina,
      hasConflict: hasConflict ?? this.hasConflict,
    );
  }
}
