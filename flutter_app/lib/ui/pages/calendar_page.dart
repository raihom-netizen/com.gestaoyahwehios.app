import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/core/event_template_schedule.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart'
    show showFinanceLancamentoEditorForTenant;
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/holiday_footer.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_date_range_picker_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_resumo_dia_card.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_visual_palette.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_category_chip_grid.dart';
import 'package:gestao_yahweh/ui/widgets/church_agenda_calendar_cells.dart';
import 'package:gestao_yahweh/ui/widgets/church_agenda_calendar_shell.dart';
import 'package:gestao_yahweh/ui/widgets/church_agenda_wisdom_ui.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_calendar_load_service.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Chaves de dia [`yyyy-MM-dd`]: ordem crescente (menor data → maior).
int _compareAgendaDayKeysAscending(String a, String b) {
  try {
    return DateTime.parse(a).compareTo(DateTime.parse(b));
  } catch (_) {
    return a.compareTo(b);
  }
}

/// Cores premium — Agenda (paridade WISDOMAPP).
abstract final class _AgendaPremiumTheme {
  _AgendaPremiumTheme._();

  static const indigo = ChurchAgendaWisdomUi.navy;
  static const cyan = ChurchAgendaWisdomUi.particularesTeal;
  static const sky = ChurchAgendaWisdomUi.actionBlue;

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      ChurchAgendaWisdomUi.navy,
      ChurchAgendaWisdomUi.particularesTeal,
      ChurchAgendaWisdomUi.actionBlue,
    ],
  );
}

class CalendarPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Permissões fundidas ([users.permissions]) — ex. `agenda_edicao` / `agenda_ver`.
  final List<String>? permissions;
  /// Dentro do [IgrejaCleanShell]: sem barra inferior sobreposta ao calendário; ações compactas na linha do modo de vista.
  final bool embeddedInShell;
  const CalendarPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

/// Cache RAM — eventos da grade instantâneos ao reabrir o mês.
abstract final class _AgendaRamCache {
  _AgendaRamCache._();

  static final Map<
      String,
      ({
        Map<String, List<_CalendarEvent>> legacy,
        Set<String> escalaDayKeys,
        DateTime at,
      })> _byKey = {};

  static const Duration _ttl = Duration(minutes: 20);

  static ({
    Map<String, List<_CalendarEvent>> legacy,
    Set<String> escalaDayKeys,
  })? peek(String key) {
    final hit = _byKey[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byKey.remove(key);
      return null;
    }
    return (legacy: hit.legacy, escalaDayKeys: hit.escalaDayKeys);
  }

  static void put(
    String key,
    Map<String, List<_CalendarEvent>> legacy,
    Set<String> escalaDayKeys,
  ) {
    if (key.trim().isEmpty || legacy.isEmpty) return;
    final copied = <String, List<_CalendarEvent>>{};
    for (final e in legacy.entries) {
      copied[e.key] = List<_CalendarEvent>.from(e.value);
    }
    _byKey[key] = (
      legacy: copied,
      escalaDayKeys: Set<String>.from(escalaDayKeys),
      at: DateTime.now(),
    );
  }
}

enum _AgendaViewKind { month, week, list }

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late DateTime _focusedMonth;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  /// Dia já “primado” após 1º toque — 2º toque abre incluir/editar (padrão Escalas CT).
  DateTime? _dayPrimedForMenu;
  _AgendaViewKind _agendaView = _AgendaViewKind.month;
  Map<String, List<_CalendarEvent>> _eventsByDay = {};
  Map<String, List<_CalendarEvent>> _legacyEventsByDay = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _agendaDocs = [];
  Timer? _webLoadCap;
  Timer? _mobileRefreshTimer;
  int _calendarLoadToken = 0;
  /// Dias (yyyy-MM-dd) com pelo menos uma escala de ministério — alerta no calendário.
  Set<String> _escalaDayKeys = {};
  bool _loading = false;
  bool _fetching = false;
  bool _exportingPdf = false;
  String? _loadError;
  bool _showingStaleCache = false;
  String _effectiveTenantId = '';
  late final AnimationController _slideCtrl;
  String _listFilter = 'mes_atual';
  DateTime? _periodStart;
  DateTime? _periodEnd;
  /// Vista lista: mês arbitrário quando [_listFilter] == `mes_livre`.
  DateTime? _listMonthAnchor;
  /// Vista lista: selecionar vários itens da agenda interna para excluir em lote.
  bool _agendaBulkSelectMode = false;
  final Set<String> _agendaSelectedIds = {};
  List<String> _customTipos = [];
  ChurchAgendaWisdomFilter _wisdomFilter = ChurchAgendaWisdomFilter.particulares;
  /// Categorias personalizadas (`event_categories`) — mesma coleção do Mural de eventos.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _eventCategoryDocs = [];
  ReportPdfBranding? _pdfBrandingReady;
  Future<ReportPdfBranding>? _pdfBrandingFuture;

  static const String _customCategoryPrefix = 'ec_';

  /// Chaves persistidas no Firestore (`agenda.category`).
  static Map<String, String> get _categoryLabels =>
      AgendaVisualPalette.categoryLabels;

  static Map<String, Color> get _categoryColors =>
      AgendaVisualPalette.categoryColors;

  static Map<String, Color> get _eventColors =>
      AgendaVisualPalette.legacyTypeColors;

  /// Mesma família de cores do módulo Escalas — escolha explícita ao criar evento.
  static const List<Color> _agendaPaletteColors = [
    Color(0xFF3B82F6),
    Color(0xFF16A34A),
    Color(0xFFE11D48),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF6366F1),
    Color(0xFFCA8A04),
    Color(0xFF0D9488),
  ];

  /// Paleta extra (mostrada recolhida para poupar espaço).
  static const List<Color> _agendaPaletteExtraColors = [
    Color(0xFFBE123C),
    Color(0xFF7E22CE),
    Color(0xFF0EA5E9),
    Color(0xFF65A30D),
    Color(0xFFDC2626),
    Color(0xFF4F46E5),
    Color(0xFF14B8A6),
    Color(0xFFEAB308),
    Color(0xFF92400E),
    Color(0xFF1E3A8A),
    Color(0xFF831843),
    Color(0xFF14532D),
    Color(0xFF9D174D),
    Color(0xFF312E81),
    Color(0xFF713F12),
    Color(0xFF164E63),
    Color(0xFFEC4899),
    Color(0xFF22C55E),
    Color(0xFF78716C),
    Color(0xFFEF4444),
  ];

  static String _categoryKeyForEventCategoryId(String id) =>
      '$_customCategoryPrefix$id';

  static bool _isCustomCategoryKey(String k) =>
      k.startsWith(_customCategoryPrefix);

  static List<Color> _markerColorsForEvents(List<_CalendarEvent> events) {
    final out = <Color>[];
    for (final e in events.take(8)) {
      if (e.hasConflict && !out.contains(AgendaVisualPalette.pendencia)) {
        out.add(AgendaVisualPalette.pendencia);
      }
      if (e.generatedFromTemplate &&
          !out.contains(AgendaVisualPalette.pendencia)) {
        out.add(AgendaVisualPalette.pendencia);
      }
      final c = _eventPaletteColor(e);
      if (!out.contains(c)) out.add(c);
    }
    if (out.isEmpty) return [AgendaVisualPalette.evento];
    return out;
  }

  static Color _eventPaletteColor(_CalendarEvent e) {
    return AgendaVisualPalette.colorFor(
      source: e.source,
      categoryKey: e.categoryKey,
      type: e.type,
      eventColorHex: e.eventColorHex,
      hasConflict: e.hasConflict,
      generatedFromTemplate: e.generatedFromTemplate,
    );
  }

  bool _dayHasConflict(String dayKey) =>
      (_eventsByDay[dayKey] ?? const []).any((e) => e.hasConflict);

  bool _dayHasEscala(String dayKey) => _escalaDayKeys.contains(dayKey);

  /// 1 evento: célula na cor do evento (ou verde). 2: diagonal (Controle Total). 3+: faixas verticais. 4+: “+N”.
  static const Color _singleEventCellGreen = AgendaVisualPalette.curso;
  static const Color _singleEventCellText = Colors.white;

  /// Acima disto usamos texto escuro no dia; evita “sumir” o número em amarelos/verdes claros.
  static bool _lightBackground(Color c) => c.computeLuminance() > 0.58;

  bool _sameVisibleMonth(DateTime day, DateTime focusedDay) =>
      day.year == focusedDay.year && day.month == focusedDay.month;

  BoxDecoration _plainDayDecoration({
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
    required bool isWeekend,
  }) {
    final primary = ThemeCleanPremium.primary;
    final radius = ControleTotalCalendarTheme.cellRadius;
    if (isSelected) {
      return BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
    }
    if (isToday) {
      return BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: primary, width: 2.2),
      );
    }
    if (isOutside) {
      return BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      );
    }
    if (isWeekend) {
      return BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.05),
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFF94A3B8), width: 1.1),
    );
  }

  /// Vermelho de calendário (padrão Controle Total): sábado, domingo e feriado nacional.
  static const Color _calendarRedDay = Color(0xFFE53935);

  TextStyle _plainDayTextStyle({
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
    required bool isWeekend,
    required bool isHoliday,
    required double cellFs,
  }) {
    final primary = ThemeCleanPremium.primary;
    if (isSelected) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      );
    }
    if (isOutside) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w500,
        color: (isWeekend || isHoliday)
            ? _calendarRedDay.withValues(alpha: 0.45)
            : Colors.grey.shade400,
      );
    }
    // Padrão Controle Total: SAB/DOM/feriado em vermelho negrito (mesmo sendo hoje).
    if (isWeekend || isHoliday) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w900,
        color: _calendarRedDay,
      );
    }
    if (isToday) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      );
    }
    return GoogleFonts.poppins(
      fontSize: cellFs,
      fontWeight: FontWeight.w600,
      color: ThemeCleanPremium.onSurface,
    );
  }

  /// Dia sem eventos da agenda: mantém o visual do [TableCalendar] + ponto vermelho em feriado nacional.
  Widget _buildPlainDayCell(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final cellFs = isMobile ? 17.0 : 15.5;
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final isHoliday = HolidayHelper.holidayNameOn(day) != null;
    final dayKey = _dayKey(day);
    final hasEscala = _dayHasEscala(dayKey);
    const outerPad = EdgeInsets.all(1.85);
    final radius = ControleTotalCalendarTheme.cellRadius;
    var decoration = _plainDayDecoration(
      isToday: isToday,
      isSelected: isSelected,
      isOutside: isOutside,
      isWeekend: isWeekend,
    );
    if (hasEscala && !isSelected) {
      decoration = decoration.copyWith(
        color: AgendaVisualPalette.escala.withValues(alpha: 0.1),
        border: Border.all(
          color: AgendaVisualPalette.escala.withValues(alpha: 0.55),
          width: isToday ? 2.2 : 1.35,
        ),
      );
    }

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: decoration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              if (hasEscala)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: AgendaVisualPalette.escala.withValues(
                      alpha: isOutside ? 0.45 : 0.92,
                    ),
                  ),
                ),
              Center(
                child: Text(
                  day.day.toString(),
                  style: _plainDayTextStyle(
                    isToday: isToday,
                    isSelected: isSelected,
                    isOutside: isOutside,
                    isWeekend: isWeekend,
                    isHoliday: isHoliday,
                    cellFs: cellFs,
                  ),
                ),
              ),
              if (hasEscala)
                const Positioned(
                  left: 4,
                  top: 4,
                  child: AgendaDayCornerBadge(
                    color: AgendaVisualPalette.escala,
                    icon: Icons.groups_rounded,
                    tooltip: 'Escala de ministério',
                  ),
                ),
              if (isHoliday)
                Positioned(
                  bottom: hasEscala ? 8 : 5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AgendaVisualPalette.feriado,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fundo da célula quando há eventos; `null` deixa o tema padrão do [TableCalendar].
  Widget? _buildCalendarDayWithEvents(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final dayKey = _dayKey(day);
    final events = _eventsByDay[dayKey] ?? [];
    final isNationalHoliday = HolidayHelper.holidayNameOn(day) != null;
    final hasEscala = _dayHasEscala(dayKey);
    final hasConflict = _dayHasConflict(dayKey);
    if (events.isEmpty) {
      return _buildPlainDayCell(
        context,
        day,
        focusedDay,
        isToday: isToday,
        isSelected: isSelected,
        isOutside: isOutside,
      );
    }

    final isMobile = ThemeCleanPremium.isMobile(context);
    final cellFs = isMobile ? 17.0 : 15.5;
    final n = events.length;
    final distinct = _markerColorsForEvents(events);
    List<Color> segmentColors;
    if (n == 1) {
      segmentColors = [
        distinct.isNotEmpty ? distinct.first : _singleEventCellGreen,
      ];
    } else if (n == 2) {
      segmentColors = [
        distinct.isNotEmpty ? distinct[0] : _singleEventCellGreen,
        distinct.length > 1 ? distinct[1] : AgendaVisualPalette.culto,
      ];
    } else {
      segmentColors = [
        distinct.isNotEmpty ? distinct[0] : _singleEventCellGreen,
        distinct.length > 1 ? distinct[1] : AgendaVisualPalette.culto,
        distinct.length > 2 ? distinct[2] : AgendaVisualPalette.evento,
      ];
    }

    return ChurchAgendaCalendarCells.buildDayWithSegmentColors(
      context,
      day,
      focusedDay,
      segmentColors: segmentColors,
      eventCount: n,
      isToday: isToday,
      isSelected: isSelected,
      isOutside: isOutside,
    );
  }

  /// Altura total aproximada do [TableCalendar] (cabeçalho + DOW + linhas).
  double _tableCalendarTotalHeight() {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final rowH = isMobile ? 76.0 : 64.0;
    final dowH = isMobile ? 34.0 : 30.0;
    const headerH = 52.0;
    final bodyRows = _agendaView == _AgendaViewKind.week ? 1 : 6;
    return headerH + dowH + rowH * bodyRows + 24;
  }

  static String _colorToHex(Color c) => AgendaVisualPalette.colorToHex(c);

  static Color? _hexToColor(String? hex) => AgendaVisualPalette.hexToColor(hex);

  /// Mesma regra que o formulário de eventos do feed (endereço em uma linha).
  static String _churchAddressLineFromTenant(Map<String, dynamic> data) {
    final endereco = (data['endereco'] ?? '').toString().trim();
    if (endereco.isNotEmpty) return endereco;
    final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    final cep = (data['cep'] ?? '').toString().trim();
    final parts = <String>[];
    if (rua.isNotEmpty) parts.add(rua);
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cep.isNotEmpty) parts.add('CEP $cep');
    return parts.join(', ');
  }

  static String _onlyDigitsAgenda(String s) =>
      s.replaceAll(RegExp(r'\D'), '');

  static String _formatCepDisplayAgenda(String digits) {
    final d = _onlyDigitsAgenda(digits);
    if (d.length <= 5) return d;
    return '${d.substring(0, 5)}-${d.substring(5, d.length.clamp(5, 8))}';
  }

  static String _mergeAgendaLocationParts({
    required String logradouro,
    required String numero,
    required String quadraLote,
    required String bairro,
    required String cidade,
    required String uf,
    required String cepDigits,
  }) {
    final parts = <String>[];
    final rua = logradouro.trim();
    final nume = numero.trim();
    if (rua.isNotEmpty) {
      parts.add(nume.isNotEmpty ? '$rua, Nº $nume' : rua);
    } else if (nume.isNotEmpty) {
      parts.add('Nº $nume');
    }
    final qd = quadraLote.trim();
    if (qd.isNotEmpty) parts.add('Qd/Lt $qd');
    final b = bairro.trim();
    if (b.isNotEmpty) parts.add(b);
    final cid = cidade.trim();
    final u = uf.trim();
    if (cid.isNotEmpty && u.isNotEmpty) {
      parts.add('$cid - $u');
    } else if (cid.isNotEmpty) {
      parts.add(cid);
    } else if (u.isNotEmpty) {
      parts.add(u);
    }
    final cep = _onlyDigitsAgenda(cepDigits);
    if (cep.length == 8) parts.add('CEP ${_formatCepDisplayAgenda(cep)}');
    return parts.join(', ');
  }

  bool get _embeddedMobile =>
      widget.embeddedInShell && ThemeCleanPremium.isMobile(context);

  bool get _agendaOverlayAsDialog =>
      kIsWeb || MediaQuery.sizeOf(context).width >= 720;

  bool get _canWrite => AppPermissions.canManageChurchMuralEventsAgenda(
        widget.role,
        permissions: widget.permissions,
      );

  /// Lançamento financeiro na agenda — só corpo administrativo (pastor, gestor, ADM, secretário, tesoureiro).
  bool get _canShowAgendaFinance =>
      ChurchRolePermissions.isFinancePanelTeam(widget.role);

  Future<void> _openAgendaFinanceEditor(DateTime day) async {
    if (!_canShowAgendaFinance) return;
    await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: _churchId,
      panelRole: widget.role,
    );
  }

  String get _tid => _churchId;

  String get _churchId => ChurchPanelTenant.forFirestore(
        _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId,
      );

  String _agendaCacheKey() {
    final (rangeStart, rangeEnd) = _computeLoadRange();
    return '${_tid.trim()}_${_dayKey(rangeStart)}_${_dayKey(rangeEnd)}';
  }

  void _hydrateAgendaFromRam() {
    final hit = _AgendaRamCache.peek(_agendaCacheKey());
    if (hit == null) return;
    _legacyEventsByDay = hit.legacy;
    _escalaDayKeys = hit.escalaDayKeys;
    final (rangeStart, rangeEnd) = _computeLoadRange();
    final agendaRam = ChurchAgendaLoadService.peekAnyRam(
      _churchId,
      start: Timestamp.fromDate(rangeStart),
      end: Timestamp.fromDate(rangeEnd),
    );
    if (agendaRam != null && agendaRam.isNotEmpty) {
      _agendaDocs = agendaRam;
    }
    _loading = false;
    _loadError = null;
    _rebuildMerged();
  }

  Future<void> _bootstrapAgendaTenant() async {
    final resolved = ChurchPanelTenant.forFirestore(widget.tenantId).trim();
    if (resolved.isEmpty || !mounted) return;
    if (resolved == _effectiveTenantId) return;
    setState(() => _effectiveTenantId = resolved);
  }

  CollectionReference<Map<String, dynamic>> get _agenda =>
      ChurchUiCollections.agenda(_churchId);

  CollectionReference<Map<String, dynamic>> get _noticias =>
      ChurchUiCollections.eventos(_churchId);

  CollectionReference<Map<String, dynamic>> get _cultos =>
      ChurchUiCollections.churchDoc(_churchId).collection('cultos');

  /// Modelos de evento fixo (pré-cadastro ao escolher o dia).
  CollectionReference<Map<String, dynamic>> get _eventTemplates =>
      ChurchUiCollections.churchDoc(_churchId).collection('event_templates');

  static const _keyCustomTipos = 'agenda_tipos_custom';

  Future<void> _loadCustomTipos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_keyCustomTipos}_${widget.tenantId}') ?? '';
    final list = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    if (mounted) setState(() => _customTipos = list);
  }

  Future<void> _loadEventCategories() async {
    try {
      final q = await ChurchTenantResilientReads.eventCategories(_tid)
          .timeout(const Duration(seconds: 6));
      final list = q.docs.toList()
        ..sort((a, b) => (a.data()['nome'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
      if (mounted) {
        setState(() => _eventCategoryDocs = list);
        _rebuildMerged();
      }
    } catch (_) {}
  }

  List<String> get _allTipos {
    const base = ['Culto', 'Célula', 'Evento', 'Reunião'];
    final merged = <String>{...base, ..._customTipos};
    return merged.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _effectiveTenantId = ChurchPanelTenant.forFirestore(widget.tenantId).trim();
    _loadCustomTipos();
    unawaited(_loadEventCategories());
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _focusedDay = DateTime(now.year, now.month, now.day);
    _selectedDay = DateTime(now.year, now.month, now.day);
    // Hoje selecionado + resumo no rodapé; 1º toque só seleciona, 2º abre o dia.
    _dayPrimedForMenu = null;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _seedAgendaDocsFromCache();
    _hydrateAgendaFromRam();
    _fetching = _agendaDocs.isEmpty && _eventsByDay.isEmpty;
    _loading = _fetching;
    _startWebLoadingCap();
    unawaited(_reloadCalendar());
    _scheduleMobileAgendaRefresh();
    unawaited(PdfSuperPremiumTheme.loadRobotoPdfTheme());
    _pdfBrandingFuture = loadReportPdfBranding(_churchId).then((b) {
      _pdfBrandingReady = b;
      return b;
    });
  }

  void _startWebLoadingCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(const Duration(seconds: 14), () {
      if (!mounted) return;
      if (_loading || _fetching) {
        setState(() {
          _loading = false;
          _fetching = false;
          if (_eventsByDay.isEmpty && _agendaDocs.isEmpty) {
            _loadError ??= 'Tempo esgotado ao carregar a agenda na Web.';
          } else {
            _showingStaleCache = true;
            _loadError = null;
          }
        });
      }
    });
  }

  void _seedAgendaDocsFromCache() {
    final (rangeStart, rangeEnd) = _computeLoadRange();
    final start = Timestamp.fromDate(rangeStart);
    final end = Timestamp.fromDate(rangeEnd);
    final ram = ChurchAgendaLoadService.peekAnyRam(
      _churchId,
      start: start,
      end: end,
    );
    if (ram != null) {
      _agendaDocs = ram;
      _loading = false;
      _showingStaleCache = true;
      _rebuildMerged();
    }
  }

  bool get _agendaHasLocalData =>
      _eventsByDay.isNotEmpty ||
      _agendaDocs.isNotEmpty ||
      _legacyEventsByDay.isNotEmpty;

  Widget _buildAgendaResilienceBanner({VoidCallback? onRetry}) {
    return ChurchPanelResilientLoadBanner(
      hasLocalData: _agendaHasLocalData,
      isSyncing: _fetching && _agendaHasLocalData,
      showStaleCache: _showingStaleCache && !_fetching,
      errorTitle: 'Não foi possível carregar alguns eventos',
      error: _loadError,
      onRetry: onRetry ?? () => _reloadCalendar(forceRefresh: true),
      staleMessage:
          'Modo offline — agenda com últimos compromissos guardados. Puxe para atualizar.',
      syncMessage:
          'Sincronizando agenda… a mostrar dados guardados enquanto atualiza.',
    );
  }

  /// Carga única — agenda + eventos + cultos (sem triplicar queries).
  Future<void> _reloadCalendar({bool forceRefresh = false}) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    await _bootstrapAgendaTenant();
    if (mounted) await _loadEvents(forceRefresh: forceRefresh);
  }

  /// Mobile: polling leve — pausa em background (evita travar o app aberto).
  void _scheduleMobileAgendaRefresh() {
    _mobileRefreshTimer?.cancel();
    if (kIsWeb) return;
    _mobileRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted || _fetching) return;
      unawaited(_reloadCalendar());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleMobileAgendaRefresh();
      if (mounted && !_fetching) {
        unawaited(_reloadCalendar());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _mobileRefreshTimer?.cancel();
      _mobileRefreshTimer = null;
    }
  }

  @override
  void didUpdateWidget(covariant CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _effectiveTenantId = ChurchPanelTenant.forFirestore(widget.tenantId).trim();
      _legacyEventsByDay = {};
      _eventsByDay = {};
      _agendaDocs = [];
      _hydrateAgendaFromRam();
      unawaited(_reloadCalendar());
      _scheduleMobileAgendaRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webLoadCap?.cancel();
    _mobileRefreshTimer?.cancel();
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
      case 'mes_livre':
        final a = _listMonthAnchor ?? DateTime(n.year, n.month);
        return a.year;
      default:
        return n.year;
    }
  }

  /// Mês alinhado ao calendário / lista (feriados do rodapé).
  int get _holidayFooterMonth {
    if (_agendaView != _AgendaViewKind.list) return _focusedMonth.month;
    final n = DateTime.now();
    switch (_listFilter) {
      case 'mes_anterior':
        final p = DateTime(n.year, n.month - 1);
        return p.month;
      case 'mes_atual':
        return n.month;
      case 'anual':
        return n.month;
      case 'periodo':
        if (_periodStart != null) return _periodStart!.month;
        return n.month;
      case 'mes_livre':
        final a = _listMonthAnchor ?? DateTime(n.year, n.month);
        return a.month;
      default:
        return n.month;
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
        case 'mes_livre':
          final a = _listMonthAnchor ?? DateTime(now.year, now.month);
          return (
            DateTime(a.year, a.month, 1),
            DateTime(a.year, a.month + 1, 0, 23, 59, 59),
          );
        default:
          return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      }
    }
    return (
      DateTime(_focusedMonth.year, _focusedMonth.month, 1),
      DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0, 23, 59, 59),
    );
  }

  void _clearAgendaBulkUi() {
    _agendaBulkSelectMode = false;
    _agendaSelectedIds.clear();
  }

  /// Só itens persistidos em `agenda` (exclui pré-visualizações `virt_tpl_`).
  bool _agendaDocSelectable(_CalendarEvent ev) {
    return ev.source == 'agenda' && !ev.id.startsWith('virt_tpl_');
  }

  /// Remove documentos `agenda` com `startTime` no intervalo inclusive (mural/cultos não entram).
  Future<int> _deleteAgendaDocsInRange(DateTime start, DateTime end) async {
    return ChurchAgendaLoadService.deleteAgendaDocsInRange(
      churchId: _churchId,
      start: start,
      end: end,
    );
  }

  Future<void> _confirmAndDeleteAgendaRange(
    DateTime start,
    DateTime end, {
    required String scopeLabel,
  }) async {
    if (!_canWrite) return;
    final snap = await _agenda
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    final n = snap.docs.length;
    if (n == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nenhum evento da agenda interna em $scopeLabel.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      builder: (dctx) => AlertDialog(
        title: const Text('Remover eventos da agenda?'),
        content: Text(
          n == 1
              ? 'Será removido 1 evento da agenda interna ($scopeLabel). '
                  'Itens do mural ou cultos não são afetados.'
              : 'Serão removidos $n eventos da agenda interna ($scopeLabel). '
                  'Itens do mural ou cultos não são afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(n > 1 ? 'Remover todos' : 'Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _deleteAgendaDocsInRange(start, end);
      _clearAgendaBulkUi();
      await _reloadCalendar(forceRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$n evento${n == 1 ? '' : 's'} removido${n == 1 ? '' : 's'} da agenda.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _showAgendaCleanupToolsSheet() async {
    if (!_canWrite) return;
    final primary = ThemeCleanPremium.primary;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusXl),
        ),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              elevation: 0,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: primary, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: ThemeCleanPremium.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
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
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      primary,
                      Color.lerp(primary, const Color(0xFF1E3A8A), 0.35)!,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.cleaning_services_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Limpar agenda interna',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Remove apenas eventos criados na Agenda. '
                      'Mural, cultos e escalas não são apagados aqui.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              tile(
                icon: Icons.view_day_rounded,
                title: 'Por dia',
                subtitle: 'Escolha uma data e remova todos os eventos da agenda nesse dia.',
                onTap: () async {
                  Navigator.pop(ctx);
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (d == null || !mounted) return;
                  final start = DateTime(d.year, d.month, d.day);
                  final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
                  final label =
                      DateFormat("d 'de' MMMM yyyy", 'pt_BR').format(d);
                  await _confirmAndDeleteAgendaRange(
                    start,
                    end,
                    scopeLabel: label,
                  );
                },
              ),
              tile(
                icon: Icons.date_range_rounded,
                title: 'Por período',
                subtitle: 'Data inicial e final — remove tudo da agenda entre essas datas.',
                onTap: () async {
                  Navigator.pop(ctx);
                  final start = await showDatePicker(
                    context: context,
                    initialDate: _periodStart ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (start == null || !mounted) return;
                  final end = await showDatePicker(
                    context: context,
                    initialDate: _periodEnd ?? start,
                    firstDate: start,
                    lastDate: DateTime(2035),
                  );
                  if (end == null || !mounted) return;
                  final a = DateTime(start.year, start.month, start.day);
                  final b = DateTime(end.year, end.month, end.day, 23, 59, 59);
                  if (a.isAfter(b)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('A data inicial deve ser antes da final.'),
                        ),
                      );
                    }
                    return;
                  }
                  await _confirmAndDeleteAgendaRange(
                    a,
                    b,
                    scopeLabel:
                        '${DateFormat('dd/MM/yyyy').format(a)} — ${DateFormat('dd/MM/yyyy').format(DateTime(end.year, end.month, end.day))}',
                  );
                },
              ),
              tile(
                icon: Icons.calendar_month_rounded,
                title: 'Por mês',
                subtitle: 'Escolha um mês (qualquer dia) e remova toda a agenda daquele mês.',
                onTap: () async {
                  Navigator.pop(ctx);
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (d == null || !mounted) return;
                  final start = DateTime(d.year, d.month, 1);
                  final end = DateTime(d.year, d.month + 1, 0, 23, 59, 59);
                  final cap = toBeginningOfSentenceCase(
                    DateFormat('MMMM yyyy', 'pt_BR').format(d),
                  );
                  await _confirmAndDeleteAgendaRange(
                    start,
                    end,
                    scopeLabel: cap ?? 'mês selecionado',
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Dica: na vista "Agenda", use "Selecionar" para marcar vários cartões e excluir só os escolhidos.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _commitBulkDeleteSelected() async {
    if (!_canWrite || _agendaSelectedIds.isEmpty) return;
    final ids = _agendaSelectedIds.toList();
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      builder: (dctx) => AlertDialog(
        title: const Text('Remover selecionados?'),
        content: Text(
          n == 1
              ? 'Será removido 1 evento da agenda interna.'
              : 'Serão removidos $n eventos da agenda interna.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ChurchAgendaLoadService.deleteAgendaEventsByIds(
        churchId: _churchId,
        docIds: ids,
      );
      _clearAgendaBulkUi();
      await _reloadCalendar(forceRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$n evento${n == 1 ? '' : 's'} removido${n == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Widget _buildAgendaBulkSelectBar() {
    final n = _agendaSelectedIds.length;
    final primary = ThemeCleanPremium.primary;
    return Material(
      elevation: 12,
      color: ThemeCleanPremium.cardBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancelar seleção',
                onPressed: () => setState(_clearAgendaBulkUi),
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      n == 0
                          ? 'Toque nos eventos da agenda'
                          : '$n selecionado${n == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    Text(
                      'Só agenda interna',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (n > 0)
                TextButton(
                  onPressed: () =>
                      setState(() => _agendaSelectedIds.clear()),
                  child: Text(
                    'Limpar',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: n == 0 ? null : () => unawaited(_commitBulkDeleteSelected()),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                child: Text(
                  'Excluir',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
      if (!ChurchModuleFirestoreListRead.isActiveRecord(d)) continue;
      final ts = ChurchAgendaLoadService.docStartTimestamp(d);
      if (ts == null) continue;
      final dt = ts.toDate();
      final key = _dayKey(dt);
      final endRaw = d['endTime'] ?? d['endAt'];
      DateTime? endDt;
      if (endRaw is Timestamp) endDt = endRaw.toDate();
      var cat = (d['category'] ?? 'culto').toString().trim();
      final ecId = (d['eventCategoryId'] ?? '').toString().trim();
      if (ecId.isNotEmpty && !_isCustomCategoryKey(cat)) {
        cat = _categoryKeyForEventCategoryId(ecId);
      }
      if (!_categoryColors.containsKey(cat) && !_isCustomCategoryKey(cat)) {
        cat = 'culto';
      }
      var colorHex = (d['color'] ?? '').toString().trim();
      if (colorHex.isEmpty) {
        if (_isCustomCategoryKey(cat)) {
          final id = cat.substring(_customCategoryPrefix.length);
          Color? col;
          for (final c in _eventCategoryDocs) {
            if (c.id == id) {
              final cor = c.data()['cor'];
              if (cor is int) col = Color(cor);
              break;
            }
          }
          colorHex = _colorToHex(
              col ?? _categoryColors['culto'] ?? ThemeCleanPremium.primary);
        } else {
          colorHex = _colorToHex(_categoryColors[cat]!);
        }
      }
      final waRaw =
          (d['whatsapp'] ?? d['contactPhone'] ?? d['telefone'] ?? '').toString();
      final nid = (d['noticiaId'] ?? '').toString().trim();
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
            contactPhone: waRaw.replaceAll(RegExp(r'\D'), ''),
            needSound: false,
            needDataShow: false,
            needCantina: false,
            linkedNoticiaId: nid.isEmpty ? null : nid,
          ));
    }
    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return map;
  }

  String _labelForCategoryKey(String cat) {
    if (_isCustomCategoryKey(cat)) {
      final id = cat.substring(_customCategoryPrefix.length);
      for (final c in _eventCategoryDocs) {
        if (c.id == id) {
          final n = (c.data()['nome'] ?? '').toString().trim();
          if (n.isNotEmpty) return n;
        }
      }
      return 'Categoria';
    }
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

  static String _normTitleDedupe(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  /// Evita duplicar o mesmo culto quando já existe o mesmo título vindo do Mural / evento fixo (`noticias`).
  void _suppressCultosWhenFeedCoversSameTitle(
    Map<String, List<_CalendarEvent>> map,
  ) {
    for (final e in map.entries.toList()) {
      final key = e.key;
      final list = e.value;
      final feedTitles = list
          .where((x) => x.source == 'noticias')
          .map((x) => _normTitleDedupe(x.title))
          .where((t) => t.isNotEmpty)
          .toSet();
      if (feedTitles.isEmpty) continue;
      final kept = list.where((x) {
        if (x.source != 'cultos') return true;
        final nt = _normTitleDedupe(x.title);
        if (nt.isEmpty) return true;
        return !feedTitles.contains(nt);
      }).toList();
      if (kept.length != list.length) {
        map[key] = kept;
      }
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

  /// Remove do feed os posts já representados por um item da agenda com [noticiaId].
  Map<String, List<_CalendarEvent>> _dedupeLinkedNoticias(
    Map<String, List<_CalendarEvent>> merged,
  ) {
    final linked = <String>{};
    for (final list in merged.values) {
      for (final ev in list) {
        final n = ev.linkedNoticiaId;
        if (ev.source == 'agenda' && n != null && n.isNotEmpty) {
          linked.add(n);
        }
      }
    }
    if (linked.isEmpty) return merged;
    final out = <String, List<_CalendarEvent>>{};
    for (final e in merged.entries) {
      final list = e.value
          .where((ev) =>
              !(ev.source == 'noticias' && linked.contains(ev.id)))
          .toList();
      if (list.isNotEmpty) out[e.key] = list;
    }
    return out;
  }

  Map<String, List<_CalendarEvent>> _markScheduleOverlaps(
    Map<String, List<_CalendarEvent>> input,
  ) {
    final out = <String, List<_CalendarEvent>>{};
    for (final e in input.entries) {
      final dayHasEscala = _escalaDayKeys.contains(e.key);
      out[e.key] = List.generate(
        e.value.length,
        (i) {
          final ev = e.value[i];
          if (!dayHasEscala) return ev;
          return ev.copyWith(hasScheduleOverlap: true);
        },
      );
    }
    return out;
  }

  void _rebuildMerged() {
    var merged =
        _mergeDayMaps(_legacyEventsByDay, _agendaEventsFromDocs(_agendaDocs));
    merged = _dedupeLinkedNoticias(merged);
    // Sem filtros — mostra tudo (agenda interna, feed, cultos, escalas).
    var marked = _markConflicts(merged);
    marked = _markScheduleOverlaps(marked);
    for (final list in marked.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    if (mounted) {
      setState(() => _eventsByDay = marked);
    }
  }

  Future<void> _loadEvents({bool forceRefresh = false}) async {
    final loadToken = ++_calendarLoadToken;
    if (forceRefresh) {
      unawaited(ChurchAgendaLoadService.invalidate(_churchId));
    }
    if (!mounted) return;
    final (rangeStart, rangeEnd) = _computeLoadRange();
    final cacheKey = _agendaCacheKey();
    final ram = _AgendaRamCache.peek(cacheKey);
    if (ram != null) {
      setState(() {
        _legacyEventsByDay = ram.legacy;
        _escalaDayKeys = ram.escalaDayKeys;
        final agendaRam = ChurchAgendaLoadService.peekAnyRam(
          _churchId,
          start: Timestamp.fromDate(rangeStart),
          end: Timestamp.fromDate(rangeEnd),
        );
        if (agendaRam != null && agendaRam.isNotEmpty) {
          _agendaDocs = agendaRam;
        }
        _loading = false;
        _loadError = null;
      });
      _rebuildMerged();
    } else if (_legacyEventsByDay.isEmpty && _agendaDocs.isEmpty) {
      setState(() {
        _loading = true;
        _fetching = true;
        _loadError = null;
      });
    }

    final map = <String, List<_CalendarEvent>>{};
    final seenNoticiaIds = <String>{};
    String? err;

    void addNoticias(QuerySnapshot<Map<String, dynamic>> snap,
        {bool allowStartAtFallback = false}) {
      for (final doc in snap.docs) {
        if (seenNoticiaIds.contains(doc.id)) continue;
        final d = doc.data();
        final typeField = (d['type'] ?? '').toString().trim();
        final startAt = d['startAt'];
        final dataEv = (d['dataEvento'] ?? d['data']) as Timestamp?;
        // Posts `type: evento` (Mural / eventos fixos): hora canónica está em startAt;
        // dataEvento às vezes veio só como data (meia-noite) ou desalinhado — priorizar startAt.
        Timestamp? ts;
        if (typeField == 'evento' && startAt is Timestamp) {
          ts = startAt;
        } else {
          ts = dataEv;
          if (ts == null && allowStartAtFallback && startAt is Timestamp) {
            ts = startAt;
          }
        }
        if (ts == null) continue;
        seenNoticiaIds.add(doc.id);
        final dt = ts.toDate();
        final key = _dayKey(dt);
        final tipo = (d['tipo'] ?? d['type'] ?? 'Evento').toString();
        final ck = _categoryKeyFromLegacyType(tipo);
        final eventColorStr =
            (d['eventColor'] ?? d['color'] ?? '').toString().trim();
        final eventColorHex = eventColorStr.isNotEmpty
            ? eventColorStr
            : (d['eventCategoryColor'] is int
                ? _colorToHex(Color(d['eventCategoryColor'] as int))
                : _colorToHex(
                    _categoryColors[ck] ?? ThemeCleanPremium.primary));
        final tplId = (d['templateId'] ?? '').toString().trim();
        final gen = d['generated'] == true;
        map.putIfAbsent(key, () => []).add(_CalendarEvent(
              id: doc.id,
              title: (d['title'] ?? d['titulo'] ?? '').toString(),
              type: _normalizeType(tipo),
              dateTime: dt,
              description: (d['description'] ?? d['descricao'] ?? '').toString(),
              source: 'noticias',
              eventColorHex: eventColorHex,
              categoryKey: ck,
              publicSite: d['publicSite'] != false,
              contactPhone: '',
              templateId: tplId.isEmpty ? null : tplId,
              generatedFromTemplate: gen,
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
              publicSite: false,
              eventColorHex: eventColor.isEmpty
                  ? _colorToHex(_categoryColors['culto']!)
                  : eventColor,
              categoryKey: 'culto',
              contactPhone: '',
            ));
      }
    }

    var escalaKeys = <String>{};
    var agendaDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    try {
      final loaded = await ChurchCalendarLoadService.loadMonth(
        seedTenantId: _churchId,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        forceRefresh: forceRefresh,
      );
      if (!mounted || loadToken != _calendarLoadToken) return;
      err = loaded.softError;
      if (loaded.muralEventos != null) {
        addNoticias(loaded.muralEventos!, allowStartAtFallback: true);
      }
      addNoticias(loaded.eventosByDataEvento);
      addCultos(loaded.cultos);
      final escSnap = loaded.escalas;
      if (escSnap != null) {
        for (final d in escSnap.docs) {
          final dt = (d.data()['date'] as Timestamp?)?.toDate();
          if (dt != null) escalaKeys.add(_dayKey(dt));
        }
      }
      agendaDocs = loaded.agendaDocs;

      final tplSnap = loaded.eventTemplates;
      final dedupe = <String>{};
      for (final list in map.values) {
        for (final ev in list) {
          dedupe.add('${_normTitleDedupe(ev.title)}|${_dayKey(ev.dateTime)}');
        }
      }
      for (final doc in tplSnap.docs) {
        final m = doc.data();
        if (m['active'] == false) continue;
        if (!eventTemplateIncludeInAgenda(m)) continue;
        final title = (m['title'] ?? 'Culto').toString().trim();
        if (title.isEmpty) continue;
        final wd = (m['weekday'] is int) ? (m['weekday'] as int).clamp(1, 7) : 7;
        final time = (m['time'] ?? '19:30').toString();
        final rec = (m['recurrence'] ?? 'weekly').toString();
        final loc = (m['location'] ?? '').toString();
        final dates = expandTemplateOccurrencesInRange(
          weekday: wd,
          timeHHmm: time,
          recurrence: rec,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );
        for (final dt in dates) {
          final dk = '${_normTitleDedupe(title)}|${_dayKey(dt)}';
          if (dedupe.contains(dk)) continue;
          dedupe.add(dk);
          final dayKey = _dayKey(dt);
          final cat = _categoryKeyFromLegacyType(title);
          map.putIfAbsent(dayKey, () => []).add(_CalendarEvent(
                id: 'virt_tpl_${doc.id}_$dayKey',
                title: title,
                type: _normalizeType(title),
                dateTime: dt,
                description: loc.isNotEmpty ? 'Local: $loc' : '',
                source: 'noticias',
                eventColorHex: _colorToHex(
                    _categoryColors[cat] ?? ThemeCleanPremium.primary),
                categoryKey: cat,
                publicSite: true,
                location: loc,
                templateId: doc.id,
                generatedFromTemplate: true,
              ));
        }
      }
    } catch (e) {
      err ??= e is TimeoutException
          ? 'Tempo esgotado ao carregar eventos.'
          : e.toString();
    }

    _suppressCultosWhenFeedCoversSameTitle(map);

    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    if (!mounted || loadToken != _calendarLoadToken) return;
    final hasNewData = map.isNotEmpty || agendaDocs.isNotEmpty;
    final hadCachedUi = _legacyEventsByDay.isNotEmpty ||
        _agendaDocs.isNotEmpty ||
        _eventsByDay.isNotEmpty;

    if (hasNewData) {
      setState(() {
        _legacyEventsByDay = map;
        _escalaDayKeys = escalaKeys;
        _agendaDocs = agendaDocs;
        _loading = false;
        _fetching = false;
        _showingStaleCache = false;
        _loadError = null;
      });
      _AgendaRamCache.put(cacheKey, map, escalaKeys);
    } else if (hadCachedUi) {
      setState(() {
        _loading = false;
        _fetching = false;
        _showingStaleCache = true;
        _loadError = null;
      });
    } else {
      setState(() {
        _legacyEventsByDay = map;
        _escalaDayKeys = escalaKeys;
        _agendaDocs = agendaDocs;
        _loading = false;
        _fetching = false;
        _showingStaleCache = false;
        _loadError = err;
      });
    }
    _rebuildMerged();
    _webLoadCap?.cancel();
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
    final fullBleedAgenda = _embeddedMobile && useSplitCalendar && !wide;
    final bodyPad = fullBleedAgenda
        ? EdgeInsets.fromLTRB(
            8,
            4,
            8,
            0,
          )
        : pad;

    return Scaffold(
      appBar: !showAppBar
          ? null
          : AppBar(
              backgroundColor: _AgendaPremiumTheme.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
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
                      tooltip: 'Limpar por dia, período ou mês',
                      onPressed: _showAgendaCleanupToolsSheet,
                      icon: const Icon(Icons.auto_delete_rounded),
                    ),
                  if (_canWrite)
                    IconButton(
                      tooltip: 'Novo evento',
                      onPressed: () => _showAddEvent(),
                      icon: const Icon(Icons.add_rounded),
                    ),
                ] else if (_canWrite) ...[
                  IconButton(
                    tooltip: 'Limpar por dia, período ou mês',
                    onPressed: _showAgendaCleanupToolsSheet,
                    icon: const Icon(Icons.auto_delete_rounded),
                  ),
                  IconButton(
                    tooltip: _agendaBulkSelectMode
                        ? 'Cancelar seleção'
                        : 'Selecionar vários',
                    onPressed: () {
                      setState(() {
                        _agendaBulkSelectMode = !_agendaBulkSelectMode;
                        if (!_agendaBulkSelectMode) {
                          _agendaSelectedIds.clear();
                        }
                      });
                    },
                    icon: Icon(
                      _agendaBulkSelectMode
                          ? Icons.close_rounded
                          : Icons.checklist_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Novo evento',
                    onPressed: () => _showAddEvent(),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ],
            ),
      floatingActionButton: _canWrite &&
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
      bottomNavigationBar: _agendaBulkSelectMode &&
              _agendaView == _AgendaViewKind.list &&
              _canWrite
          ? _buildAgendaBulkSelectBar()
          : null,
      body: SafeArea(
        child: useSplitCalendar
            ? Padding(
                padding: bodyPad,
                child: _buildSplitCalendarBody(wide: wide, isMobile: isMobile),
              )
            : RefreshIndicator(
                onRefresh: () => _reloadCalendar(forceRefresh: true),
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
                    if (_agendaHasLocalData ||
                        _loadError != null ||
                        _fetching ||
                        _showingStaleCache) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: ThemeCleanPremium.spaceMd),
                        child: _buildAgendaResilienceBanner(),
                      ),
                    ],
                    _buildViewToggleRow(),
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
                    HolidayFooter(
                        year: _holidayFooterYear, month: _holidayFooterMonth),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                  ],
                ),
              ),
      ),
    );
  }

  /// Calendário em cima (altura generosa), eventos do dia + resumo do mês abaixo — um único scroll em todos os breakpoints.
  Widget _buildSplitCalendarBody({required bool wide, required bool isMobile}) {
    final detailsBottomPad =
        isMobile && !_embeddedMobile ? 72.0 : ThemeCleanPremium.spaceMd;

    Widget unifiedScroll() => RefreshIndicator(
          onRefresh: () => _reloadCalendar(forceRefresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              if (_agendaHasLocalData ||
                  _loadError != null ||
                  _fetching ||
                  _showingStaleCache)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                    child: _buildAgendaResilienceBanner(),
                  ),
                ),
              SliverToBoxAdapter(
                child: _AgendaHeroHeader(
                  eventCount: _eventsByDay.values.fold<int>(
                    0,
                    (sum, list) => sum + list.length,
                  ),
                  monthLabel: DateFormat('MMMM yyyy', 'pt_BR')
                      .format(_focusedMonth),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: ThemeCleanPremium.spaceSm),
              ),
              SliverToBoxAdapter(
                child: _buildViewToggleRow(),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: ThemeCleanPremium.spaceMd)),
              SliverToBoxAdapter(
                // Card único: Hoje + calendário + Resumo do dia (clone Escalas CT).
                child: _buildEscalasStyleCalendarBlock(),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(ThemeCleanPremium.spaceSm),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: ThemeCleanPremium.spaceSm,
                    bottom: ThemeCleanPremium.spaceSm,
                  ),
                  child: HolidayFooter(
                      year: _holidayFooterYear, month: _holidayFooterMonth),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: ThemeCleanPremium.spaceMd),
                  child: _buildMonthSectionHeader(),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildFocusedMonthSummary(),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: detailsBottomPad),
              ),
            ],
          ),
        );

    if (_embeddedMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: unifiedScroll()),
        ],
      );
    }

    if (isMobile && !wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_embeddedMobile)
            Padding(
              padding:
                  const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: Text(
                'Agenda inteligente',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ),
          Expanded(child: unifiedScroll()),
        ],
      );
    }

    // Desktop / tablet: scroll único — sem coluna de detalhe à direita.
    return unifiedScroll();
  }

  /// PDF + novo evento compactos (painel igreja no telefone — evita barra inferior sobre o calendário).
  Widget _embeddedAgendaIconActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_agendaView == _AgendaViewKind.list && _canWrite) ...[
          IconButton(
            tooltip: 'Limpar por dia, período ou mês',
            onPressed: _showAgendaCleanupToolsSheet,
            icon: const Icon(Icons.auto_delete_rounded),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, 44),
            ),
          ),
          IconButton(
            tooltip: _agendaBulkSelectMode
                ? 'Cancelar seleção'
                : 'Selecionar vários',
            onPressed: () {
              setState(() {
                _agendaBulkSelectMode = !_agendaBulkSelectMode;
                if (!_agendaBulkSelectMode) {
                  _agendaSelectedIds.clear();
                }
              });
            },
            icon: Icon(
              _agendaBulkSelectMode
                  ? Icons.close_rounded
                  : Icons.checklist_rounded,
            ),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, 44),
            ),
          ),
        ],
        IconButton(
          tooltip: 'Exportar PDF',
          onPressed: _exportAgendaPdf,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(ThemeCleanPremium.minTouchTarget, 44),
            ),
        ),
        if (_canWrite && _agendaView != _AgendaViewKind.list)
          IconButton(
            tooltip: 'Limpar por dia, período ou mês',
            onPressed: _showAgendaCleanupToolsSheet,
            icon: const Icon(Icons.auto_delete_rounded),
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

  /// Volta o calendário para o dia atual (mês, seleção e resumo do dia) — padrão Controle Total.
  Future<void> _goToToday() async {
    final now = DateTime.now();
    final changedMonth =
        _focusedMonth.year != now.year || _focusedMonth.month != now.month;
    setState(() {
      _selectedDay = DateTime(now.year, now.month, now.day);
      _focusedDay = _selectedDay!;
      _focusedMonth = DateTime(now.year, now.month, 1);
      _dayPrimedForMenu = null;
      if (_agendaView == _AgendaViewKind.list) {
        _clearAgendaBulkUi();
        _agendaView = _AgendaViewKind.month;
      }
    });
    if (changedMonth) {
      await _reloadCalendar();
    }
  }

  bool _isDayPrimedForMenu(DateTime day) =>
      _dayPrimedForMenu != null && isSameDay(_dayPrimedForMenu!, day);

  /// Botão «Hoje» em gradiente, acima do calendário (clone do módulo Escalas / Controle Total).
  Widget _buildVoltarHojeButton() {
    final now = DateTime.now();
    final sameMonth =
        _focusedMonth.year == now.year && _focusedMonth.month == now.month;
    final label = sameMonth ? 'Hoje' : 'Voltar para hoje';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(_goToToday()),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _AgendaPremiumTheme.heroGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: ChurchAgendaWisdomUi.navy.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.today_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF64748B), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
              child: _toggleBtn(
                  'Mês',
                  Icons.calendar_month_rounded,
                  _agendaView != _AgendaViewKind.list,
                  () => setState(() {
                    _clearAgendaBulkUi();
                    _agendaView = _AgendaViewKind.month;
                  }))),
          Expanded(
              child: _toggleBtn(
                  'Lista',
                  Icons.view_agenda_rounded,
                  _agendaView == _AgendaViewKind.list,
                  () {
                    setState(() => _agendaView = _AgendaViewKind.list);
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _reloadCalendar());
                  })),
        ],
      ),
    );
  }

  Widget _buildPremiumCategoryFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? accent,
    int maxLabelLines = 1,
  }) {
    final primary = ThemeCleanPremium.primary;
    final ac = accent ?? primary;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? ac.withValues(alpha: 0.22)
                : const Color(0xFFF1F5F9),
            border: Border.all(
              color: selected ? ac : const Color(0xFFCBD5E1),
              width: selected ? 2.5 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ac.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: selected ? ac : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
              ],
              if (maxLabelLines > 1)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 158),
                  child: Text(
                    label,
                    maxLines: maxLabelLines,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF475569),
                      letterSpacing: -0.25,
                      height: 1.2,
                    ),
                  ),
                )
              else
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF475569),
                    letterSpacing: -0.25,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        onTap();
        if (_agendaView != _AgendaViewKind.list) {
          _reloadCalendar();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? ThemeCleanPremium.primary : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? ThemeCleanPremium.primary
                : const Color(0xFF94A3B8),
            width: active ? 2.0 : 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: active ? Colors.white : ThemeCleanPremium.onSurface),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: active ? Colors.white : ThemeCleanPremium.onSurface,
            )),
          ],
        ),
      ),
    );
  }

  // ─── Calendário (table_calendar) — mês / semana ────────────────────────────

  Widget _buildMonthSectionHeader() {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return InkWell(
      onTap: () => unawaited(_openFocusedMonthEventsSheet()),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Resumo do mês',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 17 : 16,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ThemeCleanPremium.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  /// Só a grade (uso no layout “calendário em cima”).
  Widget _buildCalendarTopOnly({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChurchAgendaWisdomUi.filterToggleRow(
          selected: _wisdomFilter,
          showFinance: _canShowAgendaFinance,
          onChanged: (v) => setState(() => _wisdomFilter = v),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        ChurchAgendaWisdomUi.holidaySummaryCard(
          year: _focusedMonth.year,
          month: _focusedMonth.month,
          onExportPdf: _exportAgendaPdf,
          exporting: _exportingPdf,
        ),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        _buildEscalasStyleCalendarBlock(),
        ChurchAgendaWisdomUi.calendarLegend(),
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
        _buildMonthSectionHeader(),
        const SizedBox(height: ThemeCleanPremium.spaceSm),
        _buildFocusedMonthSummary(),
      ],
    );
  }

  /// Card único Escalas CT: botão Hoje + grade + Resumo do dia.
  Widget _buildEscalasStyleCalendarBlock() {
    return ChurchAgendaCalendarPremiumShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _buildVoltarHojeButton(),
          ),
          _buildTableCalendarInner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
            child: _buildSelectedDayEvents(),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCalendarCard() => _buildEscalasStyleCalendarBlock();

  Widget _buildTableCalendarInner() {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final calFormat = CalendarFormat.month;
    final rowH = isMobile ? 76.0 : 64.0;
    final dowH = isMobile ? 34.0 : 30.0;
    final cellFs = isMobile ? 17.0 : 15.5;
    final wisdomPrimary = ChurchAgendaWisdomUi.navy;
    return TableCalendar<_CalendarEvent>(
          locale: 'pt_BR',
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2036, 12, 31),
          focusedDay: _focusedDay,
          sixWeekMonthsEnforced: true,
          selectedDayPredicate: (d) =>
              _selectedDay != null && isSameDay(_selectedDay!, d),
          calendarFormat: calFormat,
          availableGestures: AvailableGestures.horizontalSwipe,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          rowHeight: rowH,
          daysOfWeekHeight: dowH,
          eventLoader: (day) => _eventsByDay[_dayKey(day)] ?? const [],
          calendarStyle: ControleTotalCalendarTheme.calendarStyle(
            cellFs: cellFs,
            primary: wisdomPrimary,
            onSurface: ThemeCleanPremium.onSurface,
            cellMargin: const EdgeInsets.all(1.85),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: GoogleFonts.poppins(
              fontSize: isMobile ? 12.5 : 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: const Color(0xFF475569),
            ),
            weekendStyle: GoogleFonts.poppins(
              fontSize: isMobile ? 12.5 : 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: _calendarRedDay,
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
            markerBuilder: (context, day, events) => null,
            dowBuilder: (context, day) {
              final isWeekend = day.weekday == DateTime.saturday ||
                  day.weekday == DateTime.sunday;
              final label = DateFormat.E('pt_BR').format(day).toUpperCase();
              return Center(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 12.5 : 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: isWeekend ? _calendarRedDay : const Color(0xFF475569),
                  ),
                ),
              );
            },
            defaultBuilder: (context, day, focusedDay) => _buildCalendarDayWithEvents(
                  context,
                  day,
                  focusedDay,
                  isToday: isSameDay(day, DateTime.now()),
                  isSelected:
                      _selectedDay != null && isSameDay(_selectedDay!, day),
                  isOutside: false,
                ),
            outsideBuilder: (context, day, focusedDay) =>
                _buildCalendarDayWithEvents(
                  context,
                  day,
                  focusedDay,
                  isToday: isSameDay(day, DateTime.now()),
                  isSelected:
                      _selectedDay != null && isSameDay(_selectedDay!, day),
                  isOutside: true,
                ),
            todayBuilder: (context, day, focusedDay) =>
                _buildCalendarDayWithEvents(
                  context,
                  day,
                  focusedDay,
                  isToday: true,
                  isSelected:
                      _selectedDay != null && isSameDay(_selectedDay!, day),
                  isOutside: !_sameVisibleMonth(day, focusedDay),
                ),
            selectedBuilder: (context, day, focusedDay) =>
                _buildCalendarDayWithEvents(
                  context,
                  day,
                  focusedDay,
                  isToday: isSameDay(day, DateTime.now()),
                  isSelected: true,
                  isOutside: !_sameVisibleMonth(day, focusedDay),
                ),
          ),
          onDaySelected: (selected, focused) {
            final dayStart =
                DateTime(selected.year, selected.month, selected.day);
            final segundoToque = _isDayPrimedForMenu(selected);
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
              _focusedMonth = DateTime(focused.year, focused.month, 1);
              _dayPrimedForMenu = dayStart;
            });
            if (segundoToque) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _openDayCommandSheet(selected);
              });
            }
          },
          onPageChanged: (focused) {
            _focusedDay = focused;
            _focusedMonth = DateTime(focused.year, focused.month, 1);
            _reloadCalendar();
          },
        );
  }

  // ─── Selected Day Events ───────────────────────────────────────────────────

  Widget _buildSelectedDayEvents() {
    if (_selectedDay == null) {
      return ControleTotalResumoDiaCard(
        day: DateTime.now(),
        showTapHint: false,
        emptyMessage: 'Selecione um dia para ver os eventos',
        children: const [],
      );
    }
    final key = _dayKey(_selectedDay!);
    final events = List<_CalendarEvent>.from(_eventsByDay[key] ?? [])
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final holidayName = HolidayHelper.holidayNameOn(_selectedDay!);
    final showHint = _isDayPrimedForMenu(_selectedDay!);

    final children = <Widget>[
        if (holidayName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFECACA).withValues(alpha: 0.9),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_rounded, size: 18, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Feriado nacional: $holidayName',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (events.isEmpty)
        Text(
          'Nenhum compromisso neste dia.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        )
      else
        ...events.map((ev) {
        final color = _eventPaletteColor(ev);
        final time = DateFormat('HH:mm').format(ev.dateTime);
        final title =
            (ev.title.isNotEmpty ? ev.title : ev.type).trim();
        final meta =
            '${DateFormat("EEEE", 'pt_BR').format(ev.dateTime)} · ${DateFormat('dd/MM/yyyy').format(ev.dateTime)} · $time';
        return ControleTotalResumoDiaItem(
          accent: color,
          title: title,
          subtitle: meta[0].toUpperCase() + meta.substring(1),
          icon: Icons.event_rounded,
          onTap: () => _showEventDetails(ev),
          trailing: ev.type.trim().isNotEmpty
              ? Text(
                  ev.type.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.primary,
                  ),
                )
              : null,
        );
      }),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: ControleTotalResumoDiaCard(
        key: ValueKey(key),
        day: _selectedDay!,
        showTapHint: true,
        tapHint: showHint
            ? 'Toque novamente no dia no calendário para abrir o que tem neste dia.'
            : 'Toque no dia no calendário para selecionar. Toque de novo para abrir.',
        emptyMessage: 'Nenhum compromisso neste dia.',
        footer: _agendaDaySummaryFooter(events.length),
        children: children,
      ),
    );
  }

  Widget _agendaDaySummaryFooter(int count) {
    final label = count == 0
        ? 'Total do dia: nenhum compromisso'
        : count == 1
            ? 'Total do dia: 1 compromisso'
            : 'Total do dia: $count compromissos';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.12),
            const Color(0xFF14B8A6).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.summarize_rounded,
            size: 18,
            color: ThemeCleanPremium.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
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

  /// [overlaySheetContext]: ao tocar (detalhes/editar), fecha o sheet/modal do resumo mensal antes da ação.
  Widget _buildEventCard(_CalendarEvent ev, {BuildContext? overlaySheetContext}) {
    final color = _eventPaletteColor(ev);
    final time = DateFormat('HH:mm').format(ev.dateTime);
    final canEditAgenda = _canWrite && ev.source == 'agenda';
    final bulk =
        _agendaBulkSelectMode && _agendaView == _AgendaViewKind.list;
    final selectable = bulk && _agendaDocSelectable(ev);
    final selected = _agendaSelectedIds.contains(ev.id);
    String? monthListDayLine;
    if (overlaySheetContext != null) {
      final raw = DateFormat('EEEE, d/MM', 'pt_BR').format(ev.dateTime);
      monthListDayLine =
          raw.isEmpty ? raw : '${raw[0].toUpperCase()}${raw.substring(1)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(
            color: selected
                ? ThemeCleanPremium.primary
                : (ev.hasConflict
                    ? AgendaVisualPalette.pendencia
                    : (ev.hasScheduleOverlap
                        ? AgendaVisualPalette.escala
                        : const Color(0xFFF1F5F9))),
            width: selected
                ? 2
                : ((ev.hasConflict || ev.hasScheduleOverlap) ? 1.5 : 1),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              if (bulk) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Center(
                    child: selectable
                        ? Checkbox(
                            value: selected,
                            activeColor: ThemeCleanPremium.primary,
                            onChanged: (_) {
                              setState(() {
                                if (selected) {
                                  _agendaSelectedIds.remove(ev.id);
                                } else {
                                  _agendaSelectedIds.add(ev.id);
                                }
                              });
                            },
                          )
                        : Tooltip(
                            message: 'Só eventos da agenda interna',
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 22,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
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
                child: GestureDetector(
                  onTap: () {
                    if (bulk) {
                      if (selectable) {
                        setState(() {
                          if (selected) {
                            _agendaSelectedIds.remove(ev.id);
                          } else {
                            _agendaSelectedIds.add(ev.id);
                          }
                        });
                      }
                      return;
                    }
                    if (overlaySheetContext != null) {
                      Navigator.pop(overlaySheetContext);
                    }
                    _showEventDetails(ev);
                  },
                  behavior: HitTestBehavior.opaque,
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
                              if (monthListDayLine != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded,
                                        size: 14,
                                        color: ThemeCleanPremium.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        monthListDayLine,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeCleanPremium.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _originMetaChip(ev),
                                  if (ev.linkedNoticiaId != null &&
                                      ev.linkedNoticiaId!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Vinculado ao feed',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  if (ev.hasScheduleOverlap)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Escala no dia',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1D4ED8),
                                        ),
                                      ),
                                    ),
                                  // Chips clicáveis padrão Controle Total (Localização/WhatsApp).
                                  if (ev.location.trim().isNotEmpty)
                                    _ctGradientActionChip(
                                      icon: Icons.location_on_rounded,
                                      label: 'Localização',
                                      colors: const [
                                        Color(0xFF1D4ED8),
                                        Color(0xFF38BDF8),
                                      ],
                                      onTap: () => unawaited(
                                          _openEventLocation(ev.location)),
                                    ),
                                  if (_whatsappDigitsForEvent(ev) != null)
                                    _ctGradientActionChip(
                                      icon: Icons.chat_rounded,
                                      label: 'WhatsApp',
                                      colors: const [
                                        Color(0xFF128C7E),
                                        Color(0xFF25D366),
                                      ],
                                      onTap: () => unawaited(
                                          _openWhatsAppDigits(
                                              _whatsappDigitsForEvent(ev)!)),
                                    ),
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
              ),
              if (_whatsappDigitsForEvent(ev) != null && !bulk)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: IconButton(
                    tooltip: 'WhatsApp',
                    icon: const Icon(Icons.chat_rounded,
                        color: Color(0xFF25D366), size: 24),
                    onPressed: () =>
                        _openWhatsAppDigits(_whatsappDigitsForEvent(ev)!),
                  ),
                ),
              if (canEditAgenda && !bulk)
                Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        icon: Icon(Icons.edit_outlined,
                            color: ThemeCleanPremium.primary, size: 22),
                        onPressed: () {
                          if (overlaySheetContext != null) {
                            Navigator.pop(overlaySheetContext);
                          }
                          _showAddEvent(existing: ev);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remover só este',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: ThemeCleanPremium.error, size: 22),
                        onPressed: () =>
                            _confirmDeleteSingleAgendaEvent(ev,
                                sheetContext: overlaySheetContext),
                      ),
                    ],
                  ),
                ),
            ],
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

  Widget _originMetaChip(_CalendarEvent ev) {
    String label;
    Color accent;
    switch (ev.source) {
      case 'agenda':
        label = 'Agenda interna';
        accent = AgendaVisualPalette.agendaInterna;
        break;
      case 'noticias':
        label = ev.publicSite ? 'Feed / eventos' : 'Feed (só painel)';
        accent = ev.publicSite
            ? AgendaVisualPalette.feedEvento
            : const Color(0xFF6B7280);
        break;
      case 'cultos':
        label = 'Cultos';
        accent = AgendaVisualPalette.culto;
        break;
      default:
        label = ev.source;
        accent = AgendaVisualPalette.evento;
    }
    final bg = AgendaVisualPalette.chipBackground(accent);
    final fg = AgendaVisualPalette.chipForeground(accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  /// Grupo do resumo mensal (padrão Controle Total: Cultos, Reuniões, Ensino, Avisos, Eventos).
  static String _monthSummaryGroup(_CalendarEvent ev) {
    final t = ev.type.toLowerCase();
    final ck = (ev.categoryKey ?? '').trim().toLowerCase();
    if (ev.source == 'cultos' || ck == 'culto' || t.contains('culto')) {
      return 'Cultos';
    }
    if (t.contains('reuni')) return 'Reuniões';
    if (ck == 'ensino_ebd' ||
        t.contains('ebd') ||
        t.contains('ensino') ||
        t.contains('curso') ||
        t.contains('célula') ||
        t.contains('celula')) {
      return 'Ensino/EBD';
    }
    if (ev.source == 'noticias') return 'Avisos/Feed';
    return 'Eventos';
  }

  static ({Color color, IconData icon}) _monthSummaryGroupStyle(String group) {
    switch (group) {
      case 'Cultos':
        return (color: AgendaVisualPalette.culto, icon: Icons.church_rounded);
      case 'Reuniões':
        return (
          color: ChurchAgendaWisdomUi.particularesTeal,
          icon: Icons.groups_rounded,
        );
      case 'Ensino/EBD':
        return (color: AgendaVisualPalette.curso, icon: Icons.school_rounded);
      case 'Avisos/Feed':
        return (
          color: AgendaVisualPalette.feedEvento,
          icon: Icons.campaign_rounded,
        );
      default:
        return (
          color: AgendaVisualPalette.evento,
          icon: Icons.celebration_rounded,
        );
    }
  }

  /// Totais e contagem por categoria no mês visível no calendário.
  Widget _buildFocusedMonthSummary() {
    final y = _focusedMonth.year;
    final m = _focusedMonth.month;
    var total = 0;
    final byGroup = <String, int>{};
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
        final g = _monthSummaryGroup(ev);
        byGroup[g] = (byGroup[g] ?? 0) + 1;
      }
    }
    final rawMonth = DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth);
    final monthLabel =
        rawMonth.isEmpty ? '' : '${rawMonth[0].toUpperCase()}${rawMonth.substring(1)}';

    const groupOrder = [
      'Cultos',
      'Eventos',
      'Reuniões',
      'Ensino/EBD',
      'Avisos/Feed',
    ];
    final breakdown =
        <({String label, int count, Color color, IconData icon})>[];
    for (final g in groupOrder) {
      final count = byGroup[g] ?? 0;
      if (count <= 0) continue;
      final style = _monthSummaryGroupStyle(g);
      breakdown.add(
        (label: g, count: count, color: style.color, icon: style.icon),
      );
    }

    return ChurchAgendaWisdomUi.monthSummaryCard(
      monthLabel: monthLabel,
      filter: _wisdomFilter,
      total: total,
      breakdown: breakdown,
      onTap: () => unawaited(_openFocusedMonthEventsSheet()),
    );
  }

  List<_CalendarEvent> _eventsInFocusedMonthSorted() {
    final y = _focusedMonth.year;
    final m = _focusedMonth.month;
    final out = <_CalendarEvent>[];
    for (final e in _eventsByDay.entries) {
      DateTime? d;
      try {
        d = DateFormat('yyyy-MM-dd').parse(e.key);
      } catch (_) {
        continue;
      }
      if (d.year != y || d.month != m) continue;
      out.addAll(e.value);
    }
    out.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return out;
  }

  /// Lista completa do mês (mesmo critério do resumo): diálogo na web/tablet, bottom sheet no telefone.
  Future<void> _openFocusedMonthEventsSheet() async {
    final events = _eventsInFocusedMonthSorted();
    final rawMonth = DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth);
    final monthTitle = rawMonth.isEmpty
        ? ''
        : '${rawMonth[0].toUpperCase()}${rawMonth.substring(1)}';

    final mq = MediaQuery.of(context);
    final useDialog =
        kIsWeb || mq.size.width >= 720 || !ThemeCleanPremium.isMobile(context);
    final padH = useDialog ? 24.0 : 20.0;
    final primary = ThemeCleanPremium.primary;

    if (!mounted) return;

    List<Widget> listBody(BuildContext sheetCtx) {
      if (events.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined,
                    size: 52, color: Colors.grey.shade400),
                const SizedBox(height: 14),
                Text(
                  'Nenhum evento neste mês.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ];
      }
      return [
        for (final ev in events)
          _buildEventCard(ev, overlaySheetContext: sheetCtx),
      ];
    }

    Widget monthHeaderBox() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              primary.withValues(alpha: 0.14),
              primary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, color: primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Eventos em $monthTitle',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    events.isEmpty
                        ? 'Nenhum evento neste mês'
                        : '${events.length} ${events.length == 1 ? 'evento' : 'eventos'} · toque no cartão para detalhes',
                    style: TextStyle(
                      fontSize: 13,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget footerActions(BuildContext sheetCtx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padH, 4, padH, useDialog ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_canWrite) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _openNewEventForDay(
                      DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month,
                        1,
                        10,
                        0,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: Text(
                    'Novo evento',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize:
                        const Size(0, ThemeCleanPremium.minTouchTarget),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
                child: Text(
                  'Fechar',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (useDialog) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: math.max(20, (mq.size.width - 520) / 2),
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: math.min(520, mq.size.width - 40),
              height: math.min(620.0, mq.size.height * 0.82),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padH, 20, padH, 8),
                    child: monthHeaderBox(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(padH, 8, padH, 8),
                      children: [
                        ...listBody(ctx),
                        if (events.any((e) => e.source != 'agenda'))
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              _canWrite
                                  ? 'Abra o evento para excluir posts do mural ou cultos — horários do mural seguem o início (startAt).'
                                  : 'Itens do Mural ou Cultos só podem ser removidos por quem tem permissão (abrir o cartão).',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  footerActions(ctx),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, scrollCtrl) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(padH, 16, padH, 8),
                  child: monthHeaderBox(),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.fromLTRB(padH, 4, padH, 8),
                    children: [
                      ...listBody(ctx),
                      if (events.any((e) => e.source != 'agenda'))
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            _canWrite
                                ? 'Abra o evento para excluir posts do mural ou cultos — horários do mural seguem o início (startAt).'
                                : 'Itens do Mural ou Cultos só podem ser removidos por quem tem permissão (abrir o cartão).',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                footerActions(ctx),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── List Filters ─────────────────────────────────────────────────────────────

  String _listFilterChipLabel(String value, String defaultLabel) {
    if (value == 'periodo' && _periodStart != null && _periodEnd != null) {
      return '${_periodStart!.day}/${_periodStart!.month} - ${_periodEnd!.day}/${_periodEnd!.month}';
    }
    if (value == 'mes_livre' && _listMonthAnchor != null) {
      final raw = DateFormat('MMM yyyy', 'pt_BR').format(_listMonthAnchor!);
      if (raw.isEmpty) return defaultLabel;
      return '${raw[0].toUpperCase()}${raw.substring(1)}';
    }
    return defaultLabel;
  }

  Future<void> _applyListPeriodFilter(String value) async {
    if (value == 'mes_livre') {
      final d = await showDatePicker(
        context: context,
        initialDate: _listMonthAnchor ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
      );
      if (d != null && mounted) {
        setState(() {
          _listFilter = 'mes_livre';
          _listMonthAnchor = DateTime(d.year, d.month, 1);
        });
        await _reloadCalendar(forceRefresh: true);
      }
      return;
    }
    if (value == 'periodo') {
      final start = await showDatePicker(
        context: context,
        initialDate: _periodStart ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
      );
      if (start == null || !mounted) return;
      final end = await showDatePicker(
        context: context,
        initialDate: _periodEnd ?? start,
        firstDate: start,
        lastDate: DateTime(2035),
      );
      if (end != null && mounted) {
        setState(() {
          _listFilter = 'periodo';
          _periodStart = start;
          _periodEnd = end;
        });
        await _reloadCalendar(forceRefresh: true);
      }
    } else {
      setState(() => _listFilter = value);
      await _reloadCalendar(forceRefresh: true);
    }
  }

  Widget _buildListPdfExportAction() {
    final primary = ThemeCleanPremium.primary;
    return Tooltip(
      message: 'Exportar agenda em PDF',
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: _exportAgendaPdf,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: primary.withValues(alpha: 0.10),
              border: Border.all(
                color: primary.withValues(alpha: 0.45),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.picture_as_pdf_rounded,
              size: 22,
              color: primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListFilters() {
    final primary = ThemeCleanPremium.primary;
    final showTopAppBar =
        !ThemeCleanPremium.isMobile(context) || Navigator.canPop(context);
    const chipData = <(String, String, IconData)>[
      ('Mês atual', 'mes_atual', Icons.today_rounded),
      ('Mês anterior', 'mes_anterior', Icons.navigate_before_rounded),
      ('Anual', 'anual', Icons.calendar_view_month_rounded),
      ('Período', 'periodo', Icons.date_range_rounded),
    ];

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF64748B), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x180F172A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (label, value, icon) in chipData)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _buildPremiumCategoryFilterChip(
                          label: _listFilterChipLabel(value, label),
                          icon: icon,
                          accent: primary,
                          selected: _listFilter == value,
                          maxLabelLines:
                              (value == 'periodo' || value == 'mes_livre')
                                  ? 2
                                  : 1,
                          onTap: () {
                            unawaited(_applyListPeriodFilter(value));
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_canWrite) ...[
              if (!showTopAppBar) ...[
                IconButton(
                  tooltip: 'Limpar por dia, período ou mês',
                  onPressed: _showAgendaCleanupToolsSheet,
                  icon: Icon(Icons.auto_delete_rounded, color: primary),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(44, 44),
                  ),
                ),
                IconButton(
                  tooltip: _agendaBulkSelectMode
                      ? 'Cancelar seleção'
                      : 'Selecionar vários',
                  onPressed: () {
                    setState(() {
                      _agendaBulkSelectMode = !_agendaBulkSelectMode;
                      if (!_agendaBulkSelectMode) {
                        _agendaSelectedIds.clear();
                      }
                    });
                  },
                  icon: Icon(
                    _agendaBulkSelectMode
                        ? Icons.close_rounded
                        : Icons.checklist_rounded,
                    color: primary,
                  ),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              _buildListPdfExportAction(),
            ],
          ],
        ),
      ),
    );
  }

  String _pdfExportPeriodLabel() {
    if (_agendaView != _AgendaViewKind.list) {
      return toBeginningOfSentenceCase(
        DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth),
      );
    }
    const labels = <String, String>{
      'mes_atual': 'Mês atual',
      'mes_anterior': 'Mês anterior',
      'anual': 'Anual',
      'periodo': 'Período',
    };
    return _listFilterChipLabel(
      _listFilter,
      labels[_listFilter] ?? _listFilter,
    );
  }

  /// Mapa completo (sem filtros) para exportação PDF — respeita o período visível.
  Map<String, List<_CalendarEvent>> _eventsForPdfExport() {
    var merged =
        _mergeDayMaps(_legacyEventsByDay, _agendaEventsFromDocs(_agendaDocs));
    merged = _dedupeLinkedNoticias(merged);
    final (rangeStart, rangeEnd) = _computeLoadRange();
    final startDay = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final endDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    final out = <String, List<_CalendarEvent>>{};
    for (final e in merged.entries) {
      try {
        final day = DateTime.parse(e.key);
        final d = DateTime(day.year, day.month, day.day);
        if (d.isBefore(startDay) || d.isAfter(endDay)) continue;
      } catch (_) {
        continue;
      }
      if (e.value.isEmpty) continue;
      out[e.key] = List<_CalendarEvent>.from(e.value)
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return out;
  }

  Future<void> _exportAgendaPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    var dialogOpen = false;
    try {
      final exportMap = _eventsForPdfExport();
      final sortedKeys = exportMap.keys.toList()
        ..sort(_compareAgendaDayKeysAscending);
      if (sortedKeys.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum evento no período para exportar.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Gerando relatório PDF…'),
                ],
              ),
            ),
          ),
        ),
      );
      dialogOpen = true;

      final branding = _pdfBrandingReady ??
          await (_pdfBrandingFuture ?? loadReportPdfBranding(_churchId))
              .timeout(
            const Duration(milliseconds: 800),
            onTimeout: () => ReportPdfBranding(
              churchName: 'Agenda da Igreja',
              accent: ReportPdfBranding.defaultAccent,
            ),
          );

      final refLabel = _pdfExportPeriodLabel();
      final generatedAt =
          DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      final data = <List<String>>[];
      for (final key in sortedKeys) {
        for (final ev in exportMap[key]!) {
          final titulo = ev.title.isNotEmpty ? ev.title : ev.type;
          final cat = ev.categoryKey != null
              ? _labelForCategoryKey(ev.categoryKey!)
              : ev.type;
          final loc = (ev.location).trim();
          final desc = ev.description.trim();
          final descShort = desc.length > 72 ? '${desc.substring(0, 69)}…' : desc;
          data.add([
            DateFormat('dd/MM/yyyy').format(ev.dateTime),
            DateFormat('HH:mm').format(ev.dateTime),
            titulo,
            cat,
            loc.isEmpty ? '—' : loc,
            descShort.isEmpty ? '—' : descShort,
          ]);
        }
      }

      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              'Agenda — relatório',
              branding: branding,
              extraLines: [
                'Período: $refLabel',
                'Gerado em: $generatedAt',
                'Total: ${data.length} compromisso(s)',
              ],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            PdfSuperPremiumTheme.fromTextArray(
              headers: const [
                'Data',
                'Hora',
                'Título',
                'Categoria',
                'Local',
                'Descrição',
              ],
              data: data,
              accent: branding.accent,
              columnWidths: const {
                0: pw.FlexColumnWidth(0.95),
                1: pw.FlexColumnWidth(0.62),
                2: pw.FlexColumnWidth(1.65),
                3: pw.FlexColumnWidth(1.05),
                4: pw.FlexColumnWidth(1.35),
                5: pw.FlexColumnWidth(1.55),
              },
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) {
        final fn =
            'agenda_${_focusedMonth.year}_${_focusedMonth.month.toString().padLeft(2, '0')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await showPdfActions(context, bytes: bytes, filename: fn);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar PDF: $e')),
        );
      }
    } finally {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  // ─── List View ─────────────────────────────────────────────────────────────

  Widget _buildListView({Key? key}) {
    final sortedKeys = _eventsByDay.keys.toList()
      ..sort(_compareAgendaDayKeysAscending);
    if (sortedKeys.isEmpty && !_loading) {
      return _emptyDayMessage('Nenhum evento neste mês');
    }

    final flat = _flattenAgendaListItems(sortedKeys);
    if (flat.isEmpty && !_loading) {
      return _emptyDayMessage('Nenhum evento neste mês');
    }

    return ListView.builder(
      key: key,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: flat.length,
      itemBuilder: (context, i) => _buildFlatAgendaListItem(flat[i]),
    );
  }

  List<_AgendaFlatListItem> _flattenAgendaListItems(List<String> sortedKeys) {
    final flat = <_AgendaFlatListItem>[];
    if (_loading) {
      flat.add(const _AgendaFlatListItem.loading());
    }
    for (final dayKey in sortedKeys) {
      flat.add(_AgendaFlatListItem.dayHeader(dayKey));
      final events = List<_CalendarEvent>.from(_eventsByDay[dayKey] ?? [])
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
      for (final ev in events) {
        flat.add(_AgendaFlatListItem.event(ev));
      }
      flat.add(const _AgendaFlatListItem.gap());
    }
    return flat;
  }

  Widget _buildFlatAgendaListItem(_AgendaFlatListItem item) {
    return switch (item.kind) {
      _AgendaFlatListItemKind.loading => const Padding(
          padding: EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: ChurchPanelLoadingBody(),
        ),
      _AgendaFlatListItemKind.dayHeader => _buildDaySectionHeader(item.dayKey!),
      _AgendaFlatListItemKind.event => _buildEventCard(item.event!),
      _AgendaFlatListItemKind.gap => const SizedBox(height: ThemeCleanPremium.spaceSm),
    };
  }

  Widget _buildDaySectionHeader(String dayKey) {
    final date = DateTime.parse(dayKey);
    final label = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(date);
    final events = List<_CalendarEvent>.from(_eventsByDay[dayKey] ?? [])
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final stripe = events.isEmpty
        ? ThemeCleanPremium.primary
        : (_hexToColor(events.first.eventColorHex) ??
            _categoryColors[events.first.categoryKey ?? ''] ??
            ThemeCleanPremium.primary);
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: ThemeCleanPremium.spaceXs,
            top: ThemeCleanPremium.spaceXs,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                stripe.withValues(alpha: 0.14),
                ThemeCleanPremium.primary.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(color: stripe.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: stripe.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 40,
                decoration: BoxDecoration(
                  color: stripe,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label[0].toUpperCase() + label.substring(1),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${events.length}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: stripe,
                  ),
                ),
              ),
            ],
          ),
        );
  }

  // _buildDaySection removido — lista achatada lazy em _buildListView.

  String? _whatsappDigitsForEvent(_CalendarEvent ev) {
    final w = ev.contactPhone.replaceAll(RegExp(r'\D'), '');
    if (w.length >= 10) return w;
    final r = ev.responsible.replaceAll(RegExp(r'\D'), '');
    if (r.length >= 10) return r;
    return null;
  }

  Future<void> _openWhatsAppDigits(String digits) async {
    await YahwehWhatsAppService.openPhoneDigits(digits);
  }

  /// Abre a localização do evento no Google Maps: link direto ou busca pelo endereço.
  Future<void> _openEventLocation(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return;
    final low = t.toLowerCase();
    Uri uri;
    if (low.startsWith('http://') || low.startsWith('https://')) {
      uri = Uri.tryParse(t) ??
          Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t)}');
    } else if (low.contains('maps.google') ||
        low.contains('google.com/maps') ||
        low.contains('maps.app.goo.gl') ||
        low.contains('goo.gl/maps')) {
      uri = Uri.parse('https://$t');
    } else {
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t)}');
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o mapa.')),
        );
      }
    }
  }

  /// Chip de ação em gradiente (Localização/WhatsApp) — clone do Controle Total.
  Widget _ctGradientActionChip({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeAgendaDocsLinkedToNoticia(String noticiaId) async {
    final q = await _agenda
        .where('noticiaId', isEqualTo: noticiaId)
        .limit(25)
        .get();
    if (q.docs.isEmpty) return;
    final batch = ChurchRepository.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await ChurchAgendaLoadService.commitAgendaBatch(batch);
  }

  void _showEventDetails(_CalendarEvent ev) {
    if (ev.id.startsWith('virt_tpl_')) {
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: widget.embeddedInShell,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusXl)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.paddingOf(ctx).bottom + 20,
          ),
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
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.event_repeat_rounded,
                      color: ThemeCleanPremium.primary, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Horário recorrente (modelo)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${ev.title}\n\n'
                'Este item é uma pré-visualização da programação fixa (eventos fixos). '
                'Já aparece na agenda mesmo antes de gerar ocorrências no banco ou publicar no feed. '
                'Para editar ou gerar em massa, use Eventos → Eventos fixos.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final color = _eventPaletteColor(ev);
    showModalBottomSheet(
      context: context,
      useRootNavigator: widget.embeddedInShell,
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
                    color: AgendaVisualPalette.chipBackground(
                      AgendaVisualPalette.pendencia,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AgendaVisualPalette.pendencia.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AgendaVisualPalette.pendencia,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Possível conflito: outro evento no mesmo local e horário sobreposto.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AgendaVisualPalette.chipForeground(
                              AgendaVisualPalette.pendencia,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (ev.hasScheduleOverlap)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AgendaVisualPalette.chipBackground(
                      AgendaVisualPalette.escala,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AgendaVisualPalette.escala.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: AgendaVisualPalette.escala,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Neste dia há escala de ministério — confira horários em Escalas.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AgendaVisualPalette.chipForeground(
                              AgendaVisualPalette.escala,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _originMetaChip(ev),
                  if (ev.linkedNoticiaId != null &&
                      ev.linkedNoticiaId!.isNotEmpty)
                    Chip(
                      label: const Text('Vinculado ao post do feed'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelStyle: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () =>
                        unawaited(_openEventLocation(ev.location)),
                    icon: const Icon(Icons.location_on_rounded, size: 22),
                    label: Text(
                      'Abrir localização no Maps',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
              if (ev.responsible.trim().isNotEmpty) ...[
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                _detailRow(Icons.person_rounded, ev.responsible.trim()),
              ],
              if (_whatsappDigitsForEvent(ev) != null) ...[
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () =>
                        _openWhatsAppDigits(_whatsappDigitsForEvent(ev)!),
                    icon: const Icon(Icons.chat_rounded, size: 22),
                    label: Text(
                      'WhatsApp',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
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
              if (_canWrite && ev.source == 'agenda') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _showAddEvent(existing: ev);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: const Text('Editar evento'),
                  ),
                ),
                const SizedBox(height: 8),
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
              if (_canWrite && ev.source == 'noticias') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: Text(ev.generatedFromTemplate
                              ? 'Remover esta ocorrência?'
                              : 'Excluir do Mural de Eventos?'),
                          content: Text(
                            ev.generatedFromTemplate
                                ? 'Apaga só este registo em notícias (gerado pelo evento fixo). O modelo em «Eventos fixos» continua; pode gerar novamente.'
                                : 'O post sai do Mural e dos espelhos na agenda interna.',
                            style: const TextStyle(height: 1.35),
                          ),
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
                      if (ok != true || !ctx.mounted) return;
                      try {
                        await _removeAgendaDocsLinkedToNoticia(ev.id);
                        await _noticias.doc(ev.id).delete();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _reloadCalendar(forceRefresh: true);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          ThemeCleanPremium.successSnackBar('Evento removido.'),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro: $e')),
                          );
                        }
                      }
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: ThemeCleanPremium.error),
                    label: Text(
                      ev.generatedFromTemplate
                          ? 'Remover ocorrência gerada'
                          : 'Excluir do mural',
                      style: TextStyle(
                          color: ThemeCleanPremium.error,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
              if (_canWrite && ev.source == 'cultos') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Excluir culto da agenda?'),
                          content: const Text(
                            'Remove o registo na coleção cultos. Não altera o Mural de Eventos.',
                            style: TextStyle(height: 1.35),
                          ),
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
                      if (ok != true || !ctx.mounted) return;
                      try {
                        await _cultos.doc(ev.id).delete();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _reloadCalendar(forceRefresh: true);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          ThemeCleanPremium.successSnackBar('Culto removido.'),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro: $e')),
                          );
                        }
                      }
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: ThemeCleanPremium.error),
                    label: Text(
                      'Excluir registo de culto',
                      style: TextStyle(
                          color: ThemeCleanPremium.error,
                          fontWeight: FontWeight.w700),
                    ),
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

  /// Uma ocorrência em [day] (só o dia civil) com os mesmos horários; término antes
  /// do início no relógio ⇒ cruza a meia-noite (igual a um dia único).
  (DateTime, DateTime) _agendaTimeWindowForOneDay(
    DateTime day,
    int sh,
    int sm,
    int eh,
    int em,
  ) {
    var st = DateTime(day.year, day.month, day.day, sh, sm);
    var en = DateTime(day.year, day.month, day.day, eh, em);
    if (!en.isAfter(st)) {
      en = en.add(const Duration(days: 1));
    }
    return (st, en);
  }

  /// [sheetContext] — se não for `null`, fecha o resumo do dia (bottom sheet/diálogo) após remover.
  Future<void> _confirmDeleteSingleAgendaEvent(
    _CalendarEvent ev, {
    BuildContext? sheetContext,
  }) async {
    if (ev.source != 'agenda' || !_canWrite) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      builder: (dctx) => AlertDialog(
        title: const Text('Remover este evento?'),
        content: const Text(
          'Apenas este item será excluído da agenda. Os outros eventos do mesmo dia permanecem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ChurchAgendaLoadService.deleteAgendaEvent(_agenda.doc(ev.id));
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evento removido da agenda.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _confirmClearAgendaForDay(DateTime day) async {
    final key = _dayKey(day);
    final ids = (_eventsByDay[key] ?? [])
        .where((e) => e.source == 'agenda')
        .map((e) => e.id)
        .toList();
    if (ids.isEmpty) return;
    final multi = ids.length > 1;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      builder: (dctx) => AlertDialog(
        title: Text(multi
            ? 'Remover todos os eventos deste dia?'
            : 'Remover evento da agenda?'),
        content: Text(
          multi
              ? 'Serão removidos ${ids.length} eventos da agenda neste dia. '
                  'Para apagar só um, use o ícone de lixeira no cartão do evento ou abra o evento e exclua.'
              : 'Este é o único evento da agenda neste dia. '
                  'Itens de cultos ou mural legado não são afetados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(multi ? 'Remover todos' : 'Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final removed = await _deleteAgendaDocsInRange(
        DateTime(day.year, day.month, day.day),
        DateTime(day.year, day.month, day.day, 23, 59, 59),
      );
      await _reloadCalendar(forceRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$removed evento${removed == 1 ? '' : 's'} removido${removed == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  /// Cabeçalho + lista + rodapé do resumo do dia (bottom sheet ou diálogo web/tablet).
  Widget _agendaDaySummaryShell({
    required BuildContext ctx,
    required DateTime day,
    required String labelCap,
    required List<_CalendarEvent> events,
    required List<_CalendarEvent> agendaDeletable,
    required ScrollController? scrollController,
    required bool useDialogLayout,
  }) {
    final primary = ChurchAgendaWisdomUi.navy;
    final actionBlue = ChurchAgendaWisdomUi.actionBlue;
    final padH = useDialogLayout ? 24.0 : 20.0;
    final isMobile = ThemeCleanPremium.isMobile(ctx);

    Widget header() {
      if (useDialogLayout) {
        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary,
                  Color.lerp(primary, const Color(0xFF1E3A8A), 0.35)!,
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labelCap,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        events.isEmpty
                            ? 'Sem eventos neste dia'
                            : '${events.length} ${events.length == 1 ? 'evento' : 'eventos'} agendado${events.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(ctx),
                  icon: Icon(Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.95), size: 26),
                ),
              ],
            ),
          ),
        );
      }
      return Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primary.withValues(alpha: 0.14),
                    primary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_available_rounded, color: primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labelCap,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: isMobile ? 16 : 17,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          events.isEmpty
                              ? 'Toque em + para criar'
                              : '${events.length} ${events.length == 1 ? 'evento' : 'eventos'} · toque para detalhes',
                          style: TextStyle(
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    List<Widget> eventListChildren() {
      if (events.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined,
                    size: 52, color: Colors.grey.shade400),
                const SizedBox(height: 14),
                Text(
                  'Nada agendado neste dia.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ];
      }
      return events.map((ev) {
        final stripeColor = _hexToColor(ev.eventColorHex) ??
            _categoryColors[ev.categoryKey ?? ''] ??
            _eventColors[ev.type] ??
            primary;
        final time = DateFormat('HH:mm').format(ev.dateTime);
        final title = ev.title.isNotEmpty ? ev.title : ev.type;
        final canEditThis = _canWrite && ev.source == 'agenda';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEventDetails(ev);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: math.max(52.0, isMobile ? 56.0 : 58.0),
                            margin: const EdgeInsets.only(left: 6, right: 4),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 6),
                            decoration: BoxDecoration(
                              color: stripeColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: stripeColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              time,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                                height: 1.1,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      fontSize: isMobile ? 15 : 16,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(_iconForType(ev.type),
                                          size: 16,
                                          color: stripeColor),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          ev.type,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (ev.responsible.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.person_rounded,
                                            size: 15,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            ev.responsible.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.25,
                                              color: Colors.grey.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (_whatsappDigitsForEvent(ev) !=
                                            null)
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 34, minHeight: 34),
                                            tooltip: 'WhatsApp',
                                            icon: const Icon(Icons.chat_rounded,
                                                color: Color(0xFF25D366),
                                                size: 22),
                                            onPressed: () =>
                                                _openWhatsAppDigits(
                                                    _whatsappDigitsForEvent(
                                                        ev)!),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (!canEditThis)
                            Icon(Icons.chevron_right_rounded,
                                color: Colors.grey.shade400, size: 26),
                        ],
                      ),
                    ),
                  ),
                ),
                if (canEditThis) ...[
                  IconButton(
                    tooltip: 'Editar',
                    icon: Icon(Icons.edit_outlined,
                        color: ThemeCleanPremium.primary, size: 22),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _showAddEvent(existing: ev);
                    },
                  ),
                  IconButton(
                    tooltip: 'Remover só este',
                    icon: Icon(Icons.delete_outline_rounded,
                        color: ThemeCleanPremium.error, size: 22),
                    onPressed: () =>
                        _confirmDeleteSingleAgendaEvent(ev, sheetContext: ctx),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList();
    }

    final footer = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(padH, 4, padH, useDialogLayout ? 16 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_canWrite) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openNewEventForDay(day);
                },
                icon: const Icon(Icons.add_rounded, size: 22),
                label: Text(
                  'Adicionar evento neste dia',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: actionBlue,
                  padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 16 : 14),
                  minimumSize:
                      const Size(0, ThemeCleanPremium.minTouchTarget),
                ),
              ),
              if (agendaDeletable.isNotEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _confirmClearAgendaForDay(day);
                  },
                  icon: Icon(Icons.delete_sweep_rounded,
                      color: ThemeCleanPremium.error),
                  label: Text(
                    agendaDeletable.length > 1
                        ? 'Remover todos deste dia (${agendaDeletable.length})'
                        : 'Remover evento da agenda',
                    style: TextStyle(
                      color: ThemeCleanPremium.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 14 : 12),
                    minimumSize:
                        const Size(0, ThemeCleanPremium.minTouchTarget),
                  ),
                ),
              ],
            ],
            if (_canShowAgendaFinance) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_openAgendaFinanceEditor(day));
                },
                icon: const Icon(Icons.payments_rounded, size: 20),
                label: Text(
                  'Lançamento financeiro',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 12),
                  minimumSize:
                      const Size(0, ThemeCleanPremium.minTouchTarget),
                ),
              ),
            ],
            if (!useDialogLayout)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Fechar',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );

    final listChildren = <Widget>[
      ...eventListChildren(),
      if (events.any((e) => e.source != 'agenda'))
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            _canWrite
                ? 'Abra o evento para excluir posts do mural ou registos antigos de cultos — horários do mural usam o início (startAt) definido no editor.'
                : 'Alguns itens vêm do Mural de Eventos ou de Cultos; só quem tem permissão pode removê-los ao abrir o cartão.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(padH, 8, padH, 8),
            children: listChildren,
          ),
        ),
        footer,
      ],
    );
  }

  /// Resumo do dia: diálogo centrado na web/tablet; bottom sheet no telefone.
  Future<void> _openDayCommandSheet(DateTime day) async {
    final key = _dayKey(day);
    final events = List<_CalendarEvent>.from(_eventsByDay[key] ?? []);
    final agendaDeletable =
        events.where((e) => e.source == 'agenda').toList();
    final rawLabel =
        DateFormat("EEEE, d 'de' MMMM yyyy", 'pt_BR').format(day);
    final labelCap = rawLabel.isEmpty
        ? ''
        : '${rawLabel[0].toUpperCase()}${rawLabel.substring(1)}';

    final mq = MediaQuery.of(context);
    final useDialog =
        kIsWeb || mq.size.width >= 720 || !ThemeCleanPremium.isMobile(context);

    if (!mounted) return;

    if (useDialog) {
      await showDialog<void>(
        context: context,
        useRootNavigator: widget.embeddedInShell,
        barrierDismissible: true,
        builder: (ctx) {
          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: math.max(20, (mq.size.width - 520) / 2),
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: math.min(520, mq.size.width - 40),
              height: math.min(620.0, mq.size.height * 0.82),
              child: _agendaDaySummaryShell(
                ctx: ctx,
                day: day,
                labelCap: labelCap,
                events: events,
                agendaDeletable: agendaDeletable,
                scrollController: null,
                useDialogLayout: true,
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: widget.embeddedInShell,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.32,
        maxChildSize: 0.94,
        expand: false,
        builder: (_, scrollCtrl) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: _agendaDaySummaryShell(
              ctx: ctx,
              day: day,
              labelCap: labelCap,
              events: events,
              agendaDeletable: agendaDeletable,
              scrollController: scrollCtrl,
              useDialogLayout: false,
            ),
          );
        },
      ),
    );
  }

  // ─── Novo/editar evento → coleção agenda (+ opcional mural ao criar) ────────

  Future<void> _pickMemberForResponsibleSheet(
    BuildContext ctx,
    TextEditingController respCtrl,
    TextEditingController whatsappCtrl,
  ) async {
    final op = ChurchRepository.churchId(widget.tenantId.trim());
    final all = await         ChurchUiCollections.membros(op)
        .limit(500)
        .get();
    if (!ctx.mounted) return;
    final qCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (bctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            final q = qCtrl.text.toLowerCase().trim();
            final filtered = all.docs.where((d) {
              final data = d.data();
              final nome = (data['nome'] ??
                      data['NOME_COMPLETO'] ??
                      data['displayName'] ??
                      '')
                  .toString()
                  .toLowerCase();
              if (q.length < 2) return nome.isNotEmpty;
              return nome.contains(q);
            }).take(80)
                .toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Membros',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Digite 2+ letras para filtrar (ou veja a lista).',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Buscar',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => setSt(() {}),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: math.min(
                          420, MediaQuery.sizeOf(context).height * 0.48),
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                q.length < 2
                                    ? 'Digite para filtrar ou aguarde.'
                                    : 'Nenhum resultado.',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade600),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final d = filtered[i];
                                final data = d.data();
                                final nome = (data['nome'] ??
                                        data['NOME_COMPLETO'] ??
                                        data['displayName'] ??
                                        'Membro')
                                    .toString();
                                final w = (data['whatsapp'] ??
                                        data['telefone'] ??
                                        data['celular'] ??
                                        '')
                                    .toString();
                                return ListTile(
                                  title: Text(nome),
                                  onTap: () {
                                    respCtrl.text = nome;
                                    if (w.isNotEmpty) {
                                      whatsappCtrl.text = brPhoneMaskLive(w);
                                    }
                                    Navigator.pop(bctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openNewEventForDay(DateTime day) async {
    if (!_canWrite) return;
    try {
      final snap =
          await _eventTemplates.where('active', isEqualTo: true).limit(48).get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        await _showAddEvent(presetDate: day);
        return;
      }
      final pick = await showModalBottomSheet<_AgendaTplPick>(
        context: context,
        useRootNavigator: widget.embeddedInShell,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusXl)),
        ),
        builder: (ctx) {
          final h = MediaQuery.sizeOf(ctx).height * 0.62;
          return SafeArea(
            child: SizedBox(
              height: h,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Pré-cadastro ou novo',
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Use um evento fixo já cadastrado ou crie em branco.',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            leading: Icon(Icons.add_circle_outline_rounded,
                                color: ThemeCleanPremium.primary),
                            title: Text(
                              'Novo evento em branco',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text('Preencher manualmente'),
                            onTap: () =>
                                Navigator.pop(ctx, const _AgendaTplPick.blank()),
                          ),
                          const Divider(height: 1),
                          ...snap.docs.map((d) {
                            final m = d.data();
                            final title =
                                (m['title'] ?? m['titulo'] ?? 'Evento').toString();
                            final t = (m['time'] ?? '19:30').toString();
                            final loc = (m['location'] ?? '').toString();
                            return ListTile(
                              leading: Icon(Icons.event_repeat_rounded,
                                  color: ThemeCleanPremium.primary),
                              title: Text(title,
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [t, loc]
                                    .where((s) => s.toString().trim().isNotEmpty)
                                    .join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  Navigator.pop(ctx, _AgendaTplPick.template(d)),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (!mounted || pick == null) return;
      if (pick.isBlank) {
        await _showAddEvent(presetDate: day);
      } else if (pick.template != null) {
        await _showAddEvent(presetDate: day, templateDoc: pick.template);
      }
    } catch (_) {
      if (mounted) await _showAddEvent(presetDate: day);
    }
  }

  Future<void> _showAddEvent({
    DateTime? presetDate,
    _CalendarEvent? existing,
    DocumentSnapshot<Map<String, dynamic>>? templateDoc,
  }) async {
    await _loadEventCategories();
    Map<String, dynamic>? existingDoc;
    if (existing != null) {
      final snap = await _agenda.doc(existing.id).get();
      if (!snap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Evento não encontrado ou já removido.')),
          );
        }
        return;
      }
      existingDoc = snap.data();
    }

    String fmtTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    final ev = existing;
    final doc = existingDoc;
    var initialCat =
        (ev?.categoryKey ?? doc?['category'] ?? 'culto').toString().trim();
    final ecPersist = (doc?['eventCategoryId'] ?? '').toString().trim();
    if (ecPersist.isNotEmpty && !_isCustomCategoryKey(initialCat)) {
      initialCat = _categoryKeyForEventCategoryId(ecPersist);
    }
    if (!_categoryColors.containsKey(initialCat) &&
        !_isCustomCategoryKey(initialCat)) {
      initialCat = 'culto';
    }
    final catKey = initialCat;

    Color initialAgendaColor() {
      if (ev != null) {
        final fromHex = _hexToColor(ev.eventColorHex);
        if (fromHex != null) return fromHex;
      }
      final hex = (doc?['color'] ?? '').toString().trim();
      final c = _hexToColor(hex.isEmpty ? null : hex);
      if (c != null) return c;
      if (_isCustomCategoryKey(catKey)) {
        final id = catKey.substring(_customCategoryPrefix.length);
        for (final docc in _eventCategoryDocs) {
          if (docc.id == id) {
            final cor = docc.data()['cor'];
            if (cor is int) return Color(cor);
          }
        }
      }
      return _categoryColors[_categoryColors.containsKey(catKey) ? catKey : 'culto'] ??
          ThemeCleanPremium.primary;
    }

    var startDt =
        ev?.dateTime ?? (presetDate ?? _selectedDay ?? DateTime.now());
    var endDt = ev?.endDateTime ?? startDt.add(const Duration(hours: 2));
    final tpl = templateDoc?.data();
    if (tpl != null && existing == null) {
      final pd = presetDate ?? _selectedDay ?? DateTime.now();
      final tstr = (tpl['time'] ?? '19:30').toString();
      final tp = tstr.split(':');
      final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
      final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 0;
      startDt = DateTime(pd.year, pd.month, pd.day, hh, mm);
      endDt = startDt.add(const Duration(hours: 2));
    }

    final titleCtrl = TextEditingController(
        text: (tpl != null && existing == null)
            ? (tpl['title'] ?? '').toString()
            : (ev?.title ?? ''));
    final descCtrl = TextEditingController(text: ev?.description ?? '');
    final locCtrl = TextEditingController(
        text: (tpl != null && existing == null)
            ? (tpl['location'] ?? '').toString()
            : (ev?.location ?? ''));
    final respCtrl = TextEditingController(text: ev?.responsible ?? '');
    final whatsappCtrl = TextEditingController(
      text: brPhoneMaskLive(
        (doc?['whatsapp'] ?? ev?.contactPhone ?? '').toString(),
      ),
    );
    final cepPartCtrl = TextEditingController();
    final logradouroPartCtrl = TextEditingController();
    final numeroPartCtrl = TextEditingController();
    final quadraPartCtrl = TextEditingController();
    final bairroPartCtrl = TextEditingController();
    final cidadePartCtrl = TextEditingController();
    final ufPartCtrl = TextEditingController();
    final locUsePartsNotifier = ValueNotifier<bool>(false);
    final cepLoading = ValueNotifier<bool>(false);

    final startTimeNotifier = ValueNotifier<String>(fmtTime(startDt));
    final endTimeNotifier = ValueNotifier<String>(fmtTime(endDt));
    final categoryNotifier = ValueNotifier<String>(catKey);
    final agendaColorNotifier = ValueNotifier<Color>(initialAgendaColor());
    final sDay = DateTime(startDt.year, startDt.month, startDt.day);
    var eDay = DateTime(endDt.year, endDt.month, endDt.day);
    if (eDay.isBefore(sDay)) eDay = sDay;
    var recStr = (doc?['recurrence'] ?? 'none').toString().trim();
    if (recStr.isEmpty) recStr = 'none';
    if (!isSameDay(sDay, eDay) && recStr != 'none') {
      recStr = 'none';
    }
    final dateStartNotifier = ValueNotifier<DateTime>(sDay);
    final dateEndNotifier = ValueNotifier<DateTime>(eDay);
    final recurrenceNotifier = ValueNotifier<String>(recStr);
    final publishMuralNotifier = ValueNotifier<bool>(false);
    final publishSiteNotifier = ValueNotifier<bool>(true);
    final categoryListRevision = ValueNotifier<int>(0);
    final saving = ValueNotifier<bool>(false);

    if (!mounted) return;
    Widget addEventForm(BuildContext ctx) {
      final formHeight = _agendaOverlayAsDialog
          ? math.min(680.0, MediaQuery.sizeOf(ctx).height * 0.92)
          : MediaQuery.sizeOf(ctx).height * 0.92;
      return SizedBox(
        height: formHeight,
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
              Text(
                  existing == null
                      ? 'Novo culto / compromisso'
                      : 'Editar culto / compromisso',
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
              ValueListenableBuilder<int>(
                valueListenable: categoryListRevision,
                builder: (_, __, ___) => ValueListenableBuilder<String>(
                  valueListenable: categoryNotifier,
                  builder: (_, cat, __) => AgendaCategoryChipGrid(
                    selectedKey: cat,
                    categoryLabels: _categoryLabels,
                    categoryColors: _categoryColors,
                    customCategoryDocs: _eventCategoryDocs,
                    customCategoryKeyBuilder: _categoryKeyForEventCategoryId,
                    onSelected: (v) {
                      categoryNotifier.value = v;
                      if (_isCustomCategoryKey(v)) {
                        final id = v.substring(_customCategoryPrefix.length);
                        for (final c in _eventCategoryDocs) {
                          if (c.id == id) {
                            final cor = c.data()['cor'];
                            if (cor is int) {
                              agendaColorNotifier.value = Color(cor);
                            }
                            return;
                          }
                        }
                      } else {
                        agendaColorNotifier.value =
                            _categoryColors[v] ?? ThemeCleanPremium.primary;
                      }
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                          Color pickColor = _agendaPaletteColors[0];
                          final nome = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dctx) => StatefulBuilder(
                              builder: (context, setD) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                title: const Text('Nova categoria'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      controller: nome,
                                      decoration: const InputDecoration(
                                        labelText: 'Nome da categoria',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Cor',
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final c in _agendaPaletteColors
                                            .take(10))
                                          InkWell(
                                            onTap: () =>
                                                setD(() => pickColor = c),
                                            child: CircleAvatar(
                                              backgroundColor: c,
                                              radius: 18,
                                              child: pickColor == c
                                                  ? const Icon(Icons.check,
                                                      color: Colors.white,
                                                      size: 18)
                                                  : null,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dctx, false),
                                      child: const Text('Cancelar')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dctx, true),
                                      child: const Text('Salvar')),
                                ],
                              ),
                            ),
                          );
                          if (ok != true || nome.text.trim().isEmpty) return;
                          try {
                            final op = ChurchPanelTenant.forFirestore(
                                widget.tenantId.trim());
                            final ref = await                                 ChurchUiCollections.churchDoc(op)
                                .collection('event_categories')
                                .add({
                              'nome': nome.text.trim(),
                              'cor': pickColor.toARGB32(),
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            await _loadEventCategories();
                            categoryNotifier.value =
                                _categoryKeyForEventCategoryId(ref.id);
                            agendaColorNotifier.value = pickColor;
                            categoryListRevision.value++;
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                ThemeCleanPremium.successSnackBar(
                                    'Categoria criada.'),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Erro: $e')),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Nova categoria',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              ValueListenableBuilder<Color>(
                valueListenable: agendaColorNotifier,
                builder: (_, picked, __) => AgendaColorPaletteGrid(
                  colors: ChurchAgendaCalendarCells.compromissoPalette,
                  selected: picked,
                  onSelected: (c) => agendaColorNotifier.value = c,
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              ValueListenableBuilder<DateTime>(
                valueListenable: dateStartNotifier,
                builder: (_, d0, __) => ValueListenableBuilder<DateTime>(
                  valueListenable: dateEndNotifier,
                  builder: (_, d1, ___) => InkWell(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    onTap: () async {
                      final picked = await showAgendaDateRangePicker(
                        ctx,
                        initialStart: d0,
                        initialEnd: d1,
                      );
                      if (picked == null) return;
                      dateStartNotifier.value = picked.start;
                      dateEndNotifier.value = picked.end;
                      if (!isSameDay(picked.start, picked.end) &&
                          recurrenceNotifier.value != 'none') {
                        recurrenceNotifier.value = 'none';
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Período (data inicial e data final)',
                        prefixIcon: Icon(Icons.date_range_rounded),
                      ),
                      child: Text(
                        isSameDay(d0, d1)
                            ? DateFormat('dd/MM/yyyy').format(d0)
                            : '${DateFormat('dd/MM/yyyy').format(d0)}  —  ${DateFormat('dd/MM/yyyy').format(d1)}',
                        style: GoogleFonts.poppins(fontSize: 15),
                      ),
                    ),
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
                  'Dica: em um único dia, término antes do início vira o dia seguinte (ex.: 19h–08h). Vários dias: o evento (mesmos horários) gera uma entrada no calendário em cada um dos dias selecionados. Recorrência (semanal etc.) vale só se início e fim forem o mesmo dia.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Material(
                color: const Color(0xFFF8FAFC),
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusSm),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  title: Text(
                    'Local do evento',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Igreja, CEP ou texto livre.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final op = ChurchRepository.churchId(widget.tenantId.trim());
                                final snap = await                                     ChurchUiCollections.churchDoc(op)
                                    .get();
                                final line = _churchAddressLineFromTenant(
                                    snap.data() ?? {});
                                if (line.isEmpty) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      ThemeCleanPremium.successSnackBar(
                                        'Cadastre o endereço da igreja em Cadastro da Igreja.',
                                      ),
                                    );
                                  }
                                  return;
                                }
                                locCtrl.text = line;
                                locUsePartsNotifier.value = false;
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Erro: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.church_rounded, size: 20),
                            label: const Text('Usar endereço da igreja'),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: cepPartCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'CEP',
                                    hintText: '00000-000',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<bool>(
                                valueListenable: cepLoading,
                                builder: (_, loading, __) => IconButton.filled(
                                  tooltip: 'Buscar CEP',
                                  onPressed: loading
                                      ? null
                                      : () async {
                                          final d = _onlyDigitsAgenda(
                                              cepPartCtrl.text);
                                          if (d.length != 8) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Informe 8 dígitos.'),
                                              ),
                                            );
                                            return;
                                          }
                                          cepLoading.value = true;
                                          try {
                                            final r = await fetchCep(d);
                                            if (!r.ok) {
                                              if (ctx.mounted) {
                                                ScaffoldMessenger.of(ctx)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'CEP não encontrado.'),
                                                  ),
                                                );
                                              }
                                              return;
                                            }
                                            logradouroPartCtrl.text =
                                                r.logradouro ?? '';
                                            bairroPartCtrl.text =
                                                r.bairro ?? '';
                                            cidadePartCtrl.text =
                                                r.localidade ?? '';
                                            ufPartCtrl.text = r.uf ?? '';
                                            cepPartCtrl.text =
                                                _formatCepDisplayAgenda(d);
                                            locUsePartsNotifier.value = true;
                                            locCtrl.text =
                                                _mergeAgendaLocationParts(
                                              logradouro: logradouroPartCtrl.text,
                                              numero: numeroPartCtrl.text,
                                              quadraLote: quadraPartCtrl.text,
                                              bairro: bairroPartCtrl.text,
                                              cidade: cidadePartCtrl.text,
                                              uf: ufPartCtrl.text,
                                              cepDigits: cepPartCtrl.text,
                                            );
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx)
                                                  .showSnackBar(
                                                ThemeCleanPremium.successSnackBar(
                                                  'CEP encontrado. Complete número e Qd/Lt se precisar.',
                                                ),
                                              );
                                            }
                                          } finally {
                                            cepLoading.value = false;
                                          }
                                        },
                                  icon: loading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.search_rounded),
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: logradouroPartCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Rua / Av.',
                            ),
                            onChanged: (_) {
                              if (locUsePartsNotifier.value) {
                                locCtrl.text = _mergeAgendaLocationParts(
                                  logradouro: logradouroPartCtrl.text,
                                  numero: numeroPartCtrl.text,
                                  quadraLote: quadraPartCtrl.text,
                                  bairro: bairroPartCtrl.text,
                                  cidade: cidadePartCtrl.text,
                                  uf: ufPartCtrl.text,
                                  cepDigits: cepPartCtrl.text,
                                );
                              }
                            },
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: numeroPartCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nº',
                                  ),
                                  onChanged: (_) {
                                    if (locUsePartsNotifier.value) {
                                      locCtrl.text =
                                          _mergeAgendaLocationParts(
                                        logradouro: logradouroPartCtrl.text,
                                        numero: numeroPartCtrl.text,
                                        quadraLote: quadraPartCtrl.text,
                                        bairro: bairroPartCtrl.text,
                                        cidade: cidadePartCtrl.text,
                                        uf: ufPartCtrl.text,
                                        cepDigits: cepPartCtrl.text,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: quadraPartCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Qd / Lt',
                                  ),
                                  onChanged: (_) {
                                    if (locUsePartsNotifier.value) {
                                      locCtrl.text =
                                          _mergeAgendaLocationParts(
                                        logradouro: logradouroPartCtrl.text,
                                        numero: numeroPartCtrl.text,
                                        quadraLote: quadraPartCtrl.text,
                                        bairro: bairroPartCtrl.text,
                                        cidade: cidadePartCtrl.text,
                                        uf: ufPartCtrl.text,
                                        cepDigits: cepPartCtrl.text,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: bairroPartCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bairro',
                            ),
                            onChanged: (_) {
                              if (locUsePartsNotifier.value) {
                                locCtrl.text = _mergeAgendaLocationParts(
                                  logradouro: logradouroPartCtrl.text,
                                  numero: numeroPartCtrl.text,
                                  quadraLote: quadraPartCtrl.text,
                                  bairro: bairroPartCtrl.text,
                                  cidade: cidadePartCtrl.text,
                                  uf: ufPartCtrl.text,
                                  cepDigits: cepPartCtrl.text,
                                );
                              }
                            },
                          ),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: cidadePartCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Cidade',
                                  ),
                                  onChanged: (_) {
                                    if (locUsePartsNotifier.value) {
                                      locCtrl.text =
                                          _mergeAgendaLocationParts(
                                        logradouro: logradouroPartCtrl.text,
                                        numero: numeroPartCtrl.text,
                                        quadraLote: quadraPartCtrl.text,
                                        bairro: bairroPartCtrl.text,
                                        cidade: cidadePartCtrl.text,
                                        uf: ufPartCtrl.text,
                                        cepDigits: cepPartCtrl.text,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: ufPartCtrl,
                                  maxLength: 2,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: 'UF',
                                    counterText: '',
                                  ),
                                  onChanged: (_) {
                                    if (locUsePartsNotifier.value) {
                                      locCtrl.text =
                                          _mergeAgendaLocationParts(
                                        logradouro: logradouroPartCtrl.text,
                                        numero: numeroPartCtrl.text,
                                        quadraLote: quadraPartCtrl.text,
                                        bairro: bairroPartCtrl.text,
                                        cidade: cidadePartCtrl.text,
                                        uf: ufPartCtrl.text,
                                        cepDigits: cepPartCtrl.text,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              TextField(
                controller: locCtrl,
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Local (linha final)',
                  prefixIcon: Icon(Icons.place_rounded),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: respCtrl,
                      style: GoogleFonts.poppins(fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Responsável',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Buscar membro',
                    icon: Icon(Icons.groups_rounded,
                        color: ThemeCleanPremium.primary),
                    onPressed: () => _pickMemberForResponsibleSheet(
                        ctx, respCtrl, whatsappCtrl),
                  ),
                ],
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              TextField(
                controller: whatsappCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: const [BrPhoneInputFormatter()],
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'WhatsApp do responsável (opcional)',
                  hintText: '62 9.9170-5247',
                  prefixIcon: Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              ValueListenableBuilder<DateTime>(
                valueListenable: dateStartNotifier,
                builder: (_, ds, __) => ValueListenableBuilder<DateTime>(
                  valueListenable: dateEndNotifier,
                  builder: (_, de, ___) => ValueListenableBuilder<String>(
                    valueListenable: recurrenceNotifier,
                    builder: (_, rec, __) {
                      final canRec = isSameDay(ds, de);
                      final v = canRec ? rec : 'none';
                      return DropdownButtonFormField<String>(
                        value: v,
                        decoration: const InputDecoration(
                          labelText: 'Recorrência',
                          prefixIcon: Icon(Icons.repeat_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'none', child: Text('Não repetir')),
                          DropdownMenuItem(
                              value: 'weekly', child: Text('Semanal')),
                          DropdownMenuItem(
                              value: 'biweekly', child: Text('Quinzenal')),
                          DropdownMenuItem(
                              value: 'monthly', child: Text('Mensal')),
                        ],
                        onChanged: canRec
                            ? (x) {
                                if (x != null) recurrenceNotifier.value = x;
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ),
              if (existing == null) ...[
                ValueListenableBuilder<bool>(
                  valueListenable: publishMuralNotifier,
                  builder: (_, v, __) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                        'Publicar também no Mural (avisos/eventos)'),
                    subtitle: const Text(
                        'Cria um post tipo evento visível no feed da igreja.'),
                    value: v,
                    onChanged: (x) {
                      publishMuralNotifier.value = x;
                      if (!x) publishSiteNotifier.value = false;
                    },
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: publishMuralNotifier,
                  builder: (_, muralOn, __) => muralOn
                      ? ValueListenableBuilder<bool>(
                          valueListenable: publishSiteNotifier,
                          builder: (_, siteOn, ___) => SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Visível no site público'),
                            subtitle: const Text(
                              'Quem acessa o site da igreja vê este evento (respeita data e local).'),
                            value: siteOn,
                            onChanged: (x) =>
                                publishSiteNotifier.value = x,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
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
                            var dayStart = DateTime(
                              dateStartNotifier.value.year,
                              dateStartNotifier.value.month,
                              dateStartNotifier.value.day,
                            );
                            var dayEnd = DateTime(
                              dateEndNotifier.value.year,
                              dateEndNotifier.value.month,
                              dateEndNotifier.value.day,
                            );
                            if (dayEnd.isBefore(dayStart)) {
                              final t = dayStart;
                              dayStart = dayEnd;
                              dayEnd = t;
                            }
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
                            var startBase = DateTime(
                              dayStart.year, dayStart.month, dayStart.day, sh, sm);
                            var endBase = DateTime(
                              dayEnd.year, dayEnd.month, dayEnd.day, eh, em);
                            if (isSameDay(dayStart, dayEnd)) {
                              if (!endBase.isAfter(startBase)) {
                                endBase =
                                    endBase.add(const Duration(days: 1));
                              }
                            }
                            if (!endBase.isAfter(startBase)) {
                              saving.value = false;
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Revise as datas e horários de início e fim.'),
                                  ),
                                );
                              }
                              return;
                            }
                            final dur = endBase.difference(startBase);
                            final cat = categoryNotifier.value;
                            final colorHex =
                                _colorToHex(agendaColorNotifier.value);
                            var rec = recurrenceNotifier.value;
                            if (!isSameDay(dayStart, dayEnd)) {
                              rec = 'none';
                            }

                            if (existing != null) {
                              final nid =
                                  (existingDoc?['noticiaId'] ?? '').toString().trim();
                              final upd = <String, dynamic>{
                                'title': titleCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'startTime': Timestamp.fromDate(startBase),
                                'endTime': Timestamp.fromDate(endBase),
                                'color': colorHex,
                                'category': cat,
                                'location': locCtrl.text.trim(),
                                'responsible': respCtrl.text.trim(),
                                'whatsapp':
                                    whatsappCtrl.text.replaceAll(RegExp(r'\D'), ''),
                                'needSound': false,
                                'needDataShow': false,
                                'needCantina': false,
                                'recurrence': rec,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (_isCustomCategoryKey(cat)) {
                                final cid =
                                    cat.substring(_customCategoryPrefix.length);
                                upd['eventCategoryId'] = cid;
                                for (final c in _eventCategoryDocs) {
                                  if (c.id == cid) {
                                    upd['eventCategoryName'] =
                                        (c.data()['nome'] ?? '').toString();
                                    final cor = c.data()['cor'];
                                    if (cor is int) {
                                      upd['eventCategoryColor'] = cor;
                                    }
                                    break;
                                  }
                                }
                              } else {
                                upd['eventCategoryId'] = FieldValue.delete();
                                upd['eventCategoryName'] = FieldValue.delete();
                                upd['eventCategoryColor'] = FieldValue.delete();
                              }
                              if (nid.isNotEmpty) upd['noticiaId'] = nid;
                              await ChurchAgendaLoadService.updateAgendaEvent(
                                ref: _agenda.doc(existing.id),
                                payload: upd,
                              );
                              // updateAgendaEvent já invalida; não forçar refresh
                              // destrutivo que pode envenenar cache ao trocar de módulo.
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                        'Evento atualizado.'));
                                final d = dateStartNotifier.value;
                                Navigator.pop(
                                  ctx,
                                  DateTime(d.year, d.month, d.day),
                                );
                              }
                            } else {
                              String? muralNoticiaId;
                              if (publishMuralNotifier.value) {
                                final notRef = await _noticias.add({
                                  'type': 'evento',
                                  'title': titleCtrl.text.trim(),
                                  'text': descCtrl.text.trim(),
                                  'startAt': Timestamp.fromDate(startBase),
                                  'dataEvento': Timestamp.fromDate(startBase),
                                  'description': descCtrl.text.trim(),
                                  'location': locCtrl.text.trim(),
                                  'active': true,
                                  'publicSite': publishSiteNotifier.value,
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
                                muralNoticiaId = notRef.id;
                              }
                              if (isSameDay(dayStart, dayEnd)) {
                                final starts =
                                    _expandAgendaRecurrence(startBase, rec);
                                final batch = ChurchRepository.batch();
                                final seriesId = _agenda.doc().id;
                                for (final st in starts) {
                                  final en = st.add(dur);
                                  final ref = _agenda.doc();
                                  final row = <String, dynamic>{
                                    'title': titleCtrl.text.trim(),
                                    'description': descCtrl.text.trim(),
                                    'startTime': Timestamp.fromDate(st),
                                    'endTime': Timestamp.fromDate(en),
                                    'color': colorHex,
                                    'category': cat,
                                    'location': locCtrl.text.trim(),
                                    'responsible': respCtrl.text.trim(),
                                    'whatsapp': whatsappCtrl.text
                                        .replaceAll(RegExp(r'\D'), ''),
                                    'needSound': false,
                                    'needDataShow': false,
                                    'needCantina': false,
                                    'recurrence': rec,
                                    'seriesId': seriesId,
                                    'createdAt': FieldValue.serverTimestamp(),
                                    'createdByUid':
                                        FirebaseAuth.instance.currentUser
                                                ?.uid ??
                                            '',
                                    if (muralNoticiaId != null)
                                      'noticiaId': muralNoticiaId,
                                  };
                                  if (_isCustomCategoryKey(cat)) {
                                    final cid = cat
                                        .substring(_customCategoryPrefix.length);
                                    row['eventCategoryId'] = cid;
                                    for (final c in _eventCategoryDocs) {
                                      if (c.id == cid) {
                                        row['eventCategoryName'] =
                                            (c.data()['nome'] ?? '').toString();
                                        final cor = c.data()['cor'];
                                        if (cor is int) {
                                          row['eventCategoryColor'] = cor;
                                        }
                                        break;
                                      }
                                    }
                                  }
                                  batch.set(ref, row);
                                }
                                await ChurchAgendaLoadService.commitAgendaBatch(
                                    batch);
                              } else {
                                // Vários dias: um documento na agenda por dia, mesmos horários em cada dia.
                                final batch = ChurchRepository.batch();
                                final seriesId = _agenda.doc().id;
                                final daysCount =
                                    dayEnd.difference(dayStart).inDays + 1;
                                for (var t = 0; t < daysCount; t++) {
                                  final d = dayStart.add(Duration(days: t));
                                  final (st, en) = _agendaTimeWindowForOneDay(
                                    d, sh, sm, eh, em);
                                  final ref = _agenda.doc();
                                  final row = <String, dynamic>{
                                    'title': titleCtrl.text.trim(),
                                    'description': descCtrl.text.trim(),
                                    'startTime': Timestamp.fromDate(st),
                                    'endTime': Timestamp.fromDate(en),
                                    'color': colorHex,
                                    'category': cat,
                                    'location': locCtrl.text.trim(),
                                    'responsible': respCtrl.text.trim(),
                                    'whatsapp': whatsappCtrl.text
                                        .replaceAll(RegExp(r'\D'), ''),
                                    'needSound': false,
                                    'needDataShow': false,
                                    'needCantina': false,
                                    'recurrence': rec,
                                    'seriesId': seriesId,
                                    'createdAt': FieldValue.serverTimestamp(),
                                    'createdByUid':
                                        FirebaseAuth.instance.currentUser
                                                ?.uid ??
                                            '',
                                    if (muralNoticiaId != null)
                                      'noticiaId': muralNoticiaId,
                                  };
                                  if (_isCustomCategoryKey(cat)) {
                                    final cid = cat
                                        .substring(_customCategoryPrefix.length);
                                    row['eventCategoryId'] = cid;
                                    for (final c in _eventCategoryDocs) {
                                      if (c.id == cid) {
                                        row['eventCategoryName'] =
                                            (c.data()['nome'] ?? '').toString();
                                        final cor = c.data()['cor'];
                                        if (cor is int) {
                                          row['eventCategoryColor'] = cor;
                                        }
                                        break;
                                      }
                                    }
                                  }
                                  batch.set(ref, row);
                                }
                                await ChurchAgendaLoadService.commitAgendaBatch(
                                    batch);
                              }
                              unawaited(
                                  ChurchAgendaLoadService.invalidate(_churchId));
                              if (ctx.mounted) {
                                if (!isSameDay(dayStart, dayEnd)) {
                                  final n =
                                      dayEnd.difference(dayStart).inDays + 1;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                      'Evento replicado em $n dia(s) na agenda.',
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                        'Evento salvo na agenda.'),
                                  );
                                }
                                final d = dateStartNotifier.value;
                                Navigator.pop(
                                  ctx,
                                  DateTime(d.year, d.month, d.day),
                                );
                              }
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
                    isSaving
                        ? 'Salvando...'
                        : (existing == null
                            ? 'Salvar na agenda'
                            : 'Salvar alterações'),
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
      );
    }

    final DateTime? savedDate;
    if (_agendaOverlayAsDialog) {
      savedDate = await showDialog<DateTime?>(
        context: context,
        useRootNavigator: widget.embeddedInShell,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: addEventForm(ctx),
        ),
      );
    } else {
      savedDate = await showModalBottomSheet<DateTime?>(
        context: context,
        useRootNavigator: widget.embeddedInShell,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusXl)),
        ),
        builder: addEventForm,
      );
    }
    if (!mounted) return;
    final picked = savedDate;
    if (picked != null) {
      setState(() {
        _selectedDay = DateTime(picked.year, picked.month, picked.day);
        _focusedDay = _selectedDay!;
        _focusedMonth = DateTime(picked.year, picked.month, 1);
        _dayPrimedForMenu = _selectedDay;
      });
      await _reloadCalendar(forceRefresh: true);
    }
  }
}

/// Dois eventos no mesmo dia: triângulos na diagonal (referência Controle Total / Escalas).
class _AgendaDiagonalSplitPainter extends CustomPainter {
  _AgendaDiagonalSplitPainter(this.c1, this.c2, this.alphaMul);
  final Color c1;
  final Color c2;
  final double alphaMul;

  @override
  void paint(Canvas canvas, Size size) {
    final a1 = c1.withValues(alpha: (c1.a * alphaMul).clamp(0.0, 1.0));
    final a2 = c2.withValues(alpha: (c2.a * alphaMul).clamp(0.0, 1.0));
    final topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(topLeft, Paint()..color = a1);
    final bottomRight = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(bottomRight, Paint()..color = a2);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), line);
  }

  @override
  bool shouldRepaint(covariant _AgendaDiagonalSplitPainter old) =>
      old.c1 != c1 || old.c2 != c2 || old.alphaMul != alphaMul;
}

class _AgendaTplPick {
  final bool isBlank;
  final QueryDocumentSnapshot<Map<String, dynamic>>? template;
  const _AgendaTplPick.blank() : isBlank = true, template = null;
  const _AgendaTplPick.template(this.template) : isBlank = false;
}

// ─── Hero premium ─────────────────────────────────────────────────────────────

class _AgendaHeroHeader extends StatelessWidget {
  const _AgendaHeroHeader({
    required this.eventCount,
    required this.monthLabel,
  });

  final int eventCount;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final month = monthLabel.isEmpty
        ? monthLabel
        : '${monthLabel[0].toUpperCase()}${monthLabel.substring(1)}';
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: _AgendaPremiumTheme.heroGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _AgendaPremiumTheme.indigo.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.calendar_month_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agenda inteligente',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  month,
                  style: tt.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$eventCount',
                style: tt.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'eventos',
                style: tt.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
  /// Dígitos do WhatsApp / telefone (agenda interna).
  final String contactPhone;
  final bool needSound;
  final bool needDataShow;
  final bool needCantina;
  final bool hasConflict;
  /// Doc `noticias` vinculado (agenda interna espelhando o feed).
  final String? linkedNoticiaId;
  /// `event_templates` quando o post veio de evento fixo / gerado.
  final String? templateId;
  final bool generatedFromTemplate;
  /// Só relevante para [source] == `noticias` — exibe no filtro “site público”.
  final bool publicSite;
  final bool hasScheduleOverlap;

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
    this.contactPhone = '',
    this.needSound = false,
    this.needDataShow = false,
    this.needCantina = false,
    this.hasConflict = false,
    this.linkedNoticiaId,
    this.templateId,
    this.generatedFromTemplate = false,
    this.publicSite = true,
    this.hasScheduleOverlap = false,
  });

  _CalendarEvent copyWith({
    bool? hasConflict,
    bool? hasScheduleOverlap,
    String? eventColorHex,
    String? contactPhone,
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
      contactPhone: contactPhone ?? this.contactPhone,
      needSound: needSound,
      needDataShow: needDataShow,
      needCantina: needCantina,
      hasConflict: hasConflict ?? this.hasConflict,
      linkedNoticiaId: linkedNoticiaId,
      templateId: templateId,
      generatedFromTemplate: generatedFromTemplate,
      publicSite: publicSite,
      hasScheduleOverlap: hasScheduleOverlap ?? this.hasScheduleOverlap,
    );
  }
}

enum _AgendaFlatListItemKind { loading, dayHeader, event, gap }

class _AgendaFlatListItem {
  const _AgendaFlatListItem._({
    required this.kind,
    this.dayKey,
    this.event,
  });

  const _AgendaFlatListItem.loading()
      : this._(kind: _AgendaFlatListItemKind.loading);

  const _AgendaFlatListItem.gap() : this._(kind: _AgendaFlatListItemKind.gap);

  _AgendaFlatListItem.dayHeader(String key)
      : this._(kind: _AgendaFlatListItemKind.dayHeader, dayKey: key);

  _AgendaFlatListItem.event(_CalendarEvent ev)
      : this._(kind: _AgendaFlatListItemKind.event, event: ev);

  final _AgendaFlatListItemKind kind;
  final String? dayKey;
  final _CalendarEvent? event;
}
