import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/core/event_template_schedule.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/holiday_footer.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_date_range_picker_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

/// Chaves de dia [`yyyy-MM-dd`]: ordem crescente (menor data → maior).
int _compareAgendaDayKeysAscending(String a, String b) {
  try {
    return DateTime.parse(a).compareTo(DateTime.parse(b));
  } catch (_) {
    return a.compareTo(b);
  }
}

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
  /// `null` = todas as origens; senão `agenda`, `noticias` ou `cultos`.
  String? _filterSourceKey;
  /// Só posts do feed com [publicSite] (visíveis no site público).
  bool _filterPublicSiteOnly = false;
  /// Dias (yyyy-MM-dd) com pelo menos uma escala de ministério — alerta no calendário.
  Set<String> _escalaDayKeys = {};
  bool _loading = false;
  String? _loadError;
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
  /// Categorias personalizadas (`event_categories`) — mesma coleção do Mural de eventos.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _eventCategoryDocs = [];

  static const String _customCategoryPrefix = 'ec_';

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
      final c = _hexToColor(e.eventColorHex) ??
          _categoryColors[e.categoryKey ?? ''] ??
          _eventColors[e.type];
      if (c != null && !out.contains(c)) out.add(c);
    }
    if (out.isEmpty) return [ThemeCleanPremium.primary];
    return out;
  }

  /// 1 evento: célula na cor do evento (ou verde). 2: diagonal (Controle Total). 3+: faixas verticais. 4+: “+N”.
  static const Color _singleEventCellGreen = Color(0xFF16A34A);
  static const Color _singleEventCellText = Colors.white;

  /// Acima disto usamos texto escuro no dia; evita “sumir” o número em amarelos/verdes claros.
  static bool _lightBackground(Color c) => c.computeLuminance() > 0.58;

  bool _sameVisibleMonth(DateTime day, DateTime focusedDay) =>
      day.year == focusedDay.year && day.month == focusedDay.month;

  static const Color _kNationalHolidayDot = Color(0xFFE11D48);

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

  TextStyle _plainDayTextStyle({
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
    required bool isWeekend,
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
    if (isToday) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      );
    }
    if (isOutside) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade400,
      );
    }
    if (isWeekend) {
      return GoogleFonts.poppins(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
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
    const outerPad = EdgeInsets.all(1.85);
    final radius = ControleTotalCalendarTheme.cellRadius;

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: _plainDayDecoration(
          isToday: isToday,
          isSelected: isSelected,
          isOutside: isOutside,
          isWeekend: isWeekend,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Center(
                child: Text(
                  day.day.toString(),
                  style: _plainDayTextStyle(
                    isToday: isToday,
                    isSelected: isSelected,
                    isOutside: isOutside,
                    isWeekend: isWeekend,
                    cellFs: cellFs,
                  ),
                ),
              ),
              if (isHoliday)
                Positioned(
                  bottom: 5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _kNationalHolidayDot,
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
    final events = _eventsByDay[_dayKey(day)] ?? [];
    final isNationalHoliday = HolidayHelper.holidayNameOn(day) != null;
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
    final dim = isOutside ? 0.45 : 1.0;

    List<Color> segmentColors;
    if (n == 1) {
      segmentColors = [
        distinct.isNotEmpty ? distinct.first : _singleEventCellGreen,
      ];
    } else if (n == 2) {
      segmentColors = [
        distinct.isNotEmpty ? distinct[0] : _singleEventCellGreen,
        distinct.length > 1 ? distinct[1] : const Color(0xFF2563EB),
      ];
    } else {
      segmentColors = [
        distinct.isNotEmpty ? distinct[0] : _singleEventCellGreen,
        distinct.length > 1 ? distinct[1] : const Color(0xFF2563EB),
        distinct.length > 2 ? distinct[2] : const Color(0xFF9333EA),
      ];
    }

    final extra = n > 3 ? n - 3 : 0;
    final primary = ThemeCleanPremium.primary;
    final bool multiDay = n >= 2;

    Border border;
    List<BoxShadow>? cellShadow;
    if (isSelected) {
      border = Border.all(color: primary, width: 3.2);
      cellShadow = [
        BoxShadow(
          color: primary.withValues(alpha: 0.38),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (multiDay && !isOutside) {
      // Vários eventos no dia: borda forte como Controle Total (duas escalas bem visíveis).
      border = Border.all(
        color: isToday ? primary : const Color(0xFF0F172A),
        width: isToday ? 3.0 : 2.65,
      );
      cellShadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (isToday) {
      border = Border.all(color: primary, width: 2.4);
    } else {
      border = Border.all(
        color: isOutside ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
        width: n == 1 && !isOutside ? 1.35 : 1,
      );
    }

    final dayNum = day.day.toString();
    final Color fill1 = segmentColors[0];
    final bool light1 = n == 1 && _lightBackground(fill1.withValues(alpha: 0.92));
    final List<Shadow>? dayNumShadows = n == 1
        ? (light1
            ? [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 3,
                  offset: const Offset(0, 1.2),
                ),
              ]
            : const [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 2.5,
                  offset: Offset(0, 1),
                ),
              ])
        : const [
            Shadow(
              color: Color(0xA0000000),
              blurRadius: 5,
              offset: Offset(0, 1.5),
            ),
          ];
    final TextStyle numStyle = GoogleFonts.poppins(
      fontSize: cellFs,
      fontWeight: isSelected || isToday || multiDay ? FontWeight.w800 : FontWeight.w700,
      color: n == 1
          ? (light1 ? const Color(0xFF0F172A) : _singleEventCellText)
          : Colors.white,
      shadows: dayNumShadows,
    );

    Widget stripes;
    if (n == 1) {
      stripes = ColoredBox(
        color: fill1.withValues(alpha: 0.93 * dim),
      );
    } else if (n == 2) {
      // Duas ocorrências: diagonal (triângulos), igual referência Controle Total / Escalas.
      stripes = CustomPaint(
        painter: _AgendaDiagonalSplitPainter(
          segmentColors[0],
          segmentColors[1],
          (0.86 + (isSelected ? 0.05 : 0)) * dim,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      final count = n > 3 ? 3 : n;
      final children = <Widget>[];
      for (var i = 0; i < count; i++) {
        if (i > 0) {
          children.add(
            Container(
              width: 1.6,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          );
        }
        final c = segmentColors[i];
        children.add(
          Expanded(
            child: ColoredBox(
              color: c.withValues(
                alpha: (0.84 + (isSelected ? 0.06 : 0)) * dim,
              ),
            ),
          ),
        );
      }
      stripes = Row(children: children);
    }

    final markerDots = multiDay
        ? ControleTotalCalendarTheme.markerRow(
            colors: distinct.take(n > 3 ? 3 : n).toList(),
            moreCount: extra,
            isMobile: isMobile,
          )
        : null;

    final radius = ControleTotalCalendarTheme.cellRadius;
    // Mesma margem visual do TableCalendar com células padrão — evita overflow para células vizinhas.
    const outerPad = EdgeInsets.all(1.85);

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: border,
          boxShadow: cellShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(child: stripes),
                    Center(child: Text(dayNum, style: numStyle)),
                    if (extra > 0)
                      Positioned(
                        right: 3,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '+$extra',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 9.5 : 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    if (isNationalHoliday)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _kNationalHolidayDot,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (markerDots != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1,
                      ),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: markerDots,
                  ),
                ),
            ],
          ),
        ),
      ),
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

  /// Modelos de evento fixo (pré-cadastro ao escolher o dia).
  CollectionReference<Map<String, dynamic>> get _eventTemplates =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('event_templates');

  static const _keyCustomTipos = 'agenda_tipos_custom';

  Future<void> _loadCustomTipos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_keyCustomTipos}_${widget.tenantId}') ?? '';
    final list = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList()..sort();
    if (mounted) setState(() => _customTipos = list);
  }

  Future<void> _loadEventCategories() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('event_categories')
          .get();
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
    // Evita forçar refresh do token a cada abertura (latência extra no 1.º carregamento).
    FirebaseAuth.instance.currentUser?.getIdToken();
    _loadCustomTipos();
    unawaited(_loadEventCategories());
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
    final snap = await _agenda
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    if (snap.docs.isEmpty) return 0;
    const chunk = 450;
    for (var i = 0; i < snap.docs.length; i += chunk) {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs.skip(i).take(chunk)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    return snap.docs.length;
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
      await _loadEvents();
      _restartAgendaSubscription();
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
      const chunk = 450;
      for (var i = 0; i < ids.length; i += chunk) {
        final batch = FirebaseFirestore.instance.batch();
        for (final id in ids.skip(i).take(chunk)) {
          batch.delete(_agenda.doc(id));
        }
        await batch.commit();
      }
      _clearAgendaBulkUi();
      await _loadEvents();
      _restartAgendaSubscription();
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
      final ts = d['startTime'] ?? d['startAt'];
      if (ts is! Timestamp) continue;
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

  Map<String, List<_CalendarEvent>> _applySourceAndPublicFilter(
    Map<String, List<_CalendarEvent>> input,
  ) {
    final out = <String, List<_CalendarEvent>>{};
    for (final e in input.entries) {
      final filtered = e.value.where((ev) {
        if (_filterSourceKey != null && ev.source != _filterSourceKey) {
          return false;
        }
        if (_filterPublicSiteOnly) {
          if (ev.source != 'noticias' || ev.publicSite != true) {
            return false;
          }
        }
        return true;
      }).toList();
      if (filtered.isNotEmpty) out[e.key] = filtered;
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
    var filtered = _applyCategoryFilter(merged);
    filtered = _applySourceAndPublicFilter(filtered);
    var     marked = _markConflicts(filtered);
    marked = _markScheduleOverlaps(marked);
    for (final list in marked.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
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

    const timeoutDuration = Duration(seconds: 12);

    Future<QuerySnapshot<Map<String, dynamic>>> loadNoticiasPorData() async {
      try {
        return await _noticias
            .where('dataEvento', isGreaterThanOrEqualTo: start)
            .where('dataEvento', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
      } catch (e) {
        err ??= e is TimeoutException
            ? 'Tempo esgotado ao carregar eventos.'
            : e.toString();
        try {
          final snap = await _noticiasIgrejas
              .where('dataEvento', isGreaterThanOrEqualTo: start)
              .where('dataEvento', isLessThanOrEqualTo: end)
              .get()
              .timeout(timeoutDuration);
          err = null;
          return snap;
        } catch (_) {
          return await _noticias.limit(0).get();
        }
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>> loadCultosPorData() async {
      try {
        return await _cultos
            .where('data', isGreaterThanOrEqualTo: start)
            .where('data', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
      } catch (e) {
        err ??= e is TimeoutException
            ? 'Tempo esgotado ao carregar eventos.'
            : e.toString();
        try {
          final snap = await _cultosIgrejas
              .where('data', isGreaterThanOrEqualTo: start)
              .where('data', isLessThanOrEqualTo: end)
              .get()
              .timeout(timeoutDuration);
          err = null;
          return snap;
        } catch (_) {
          return await _cultos.limit(0).get();
        }
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>?> loadMuralEventos() async {
      try {
        return await _noticias
            .where('type', isEqualTo: 'evento')
            .where('startAt', isGreaterThanOrEqualTo: start)
            .where('startAt', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
      } catch (_) {
        return null;
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>?> loadEscalasNoPeriodo() async {
      try {
        return await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .collection('escalas')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end)
            .get()
            .timeout(timeoutDuration);
      } catch (_) {
        return null;
      }
    }

    var escalaKeys = <String>{};
    try {
      final parallel = await Future.wait<dynamic>([
        loadNoticiasPorData(),
        loadCultosPorData(),
        loadMuralEventos(),
        loadEscalasNoPeriodo(),
      ]);
      // Mural (`type: evento` + startAt) primeiro: define hora correta antes do índice por dataEvento.
      final muralSnap =
          parallel[2] as QuerySnapshot<Map<String, dynamic>>?;
      if (muralSnap != null) {
        addNoticias(muralSnap, allowStartAtFallback: true);
      }
      addNoticias(parallel[0] as QuerySnapshot<Map<String, dynamic>>);
      addCultos(parallel[1] as QuerySnapshot<Map<String, dynamic>>);
      final escSnap = parallel[3] as QuerySnapshot<Map<String, dynamic>>?;
      if (escSnap != null) {
        for (final d in escSnap.docs) {
          final dt = (d.data()['date'] as Timestamp?)?.toDate();
          if (dt != null) escalaKeys.add(_dayKey(dt));
        }
      }
    } catch (e) {
      err ??= e is TimeoutException
          ? 'Tempo esgotado ao carregar eventos.'
          : e.toString();
    }

    try {
      final tplSnap =
          await _eventTemplates.where('active', isEqualTo: true).get();
      final dedupe = <String>{};
      for (final list in map.values) {
        for (final ev in list) {
          dedupe.add('${_normTitleDedupe(ev.title)}|${_dayKey(ev.dateTime)}');
        }
      }
      for (final doc in tplSnap.docs) {
        final m = doc.data();
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
    } catch (_) {}

    _suppressCultosWhenFeedCoversSameTitle(map);

    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }

    if (mounted) {
      setState(() {
        _legacyEventsByDay = map;
        _escalaDayKeys = escalaKeys;
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
      bottomNavigationBar: _agendaBulkSelectMode &&
              _agendaView == _AgendaViewKind.list &&
              _canWrite
          ? _buildAgendaBulkSelectBar()
          : (showBottomBar
              ? SafeArea(
                  child: Material(
                    elevation: 8,
                    color: ThemeCleanPremium.cardBackground,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _exportAgendaPdf,
                              icon: const Icon(Icons.picture_as_pdf_rounded,
                                  size: 22),
                              label: Text('PDF',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                minimumSize: const Size(
                                    0, ThemeCleanPremium.minTouchTarget),
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
                                label: Text('Novo evento',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : null),
      body: SafeArea(
        child: useSplitCalendar
            ? Padding(
                padding: bodyPad,
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
                    _buildSourceFilterRow(),
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
          onRefresh: _loadEvents,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              if (_loadError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                    child: ChurchPanelErrorBody(
                      title: 'Não foi possível carregar alguns eventos',
                      error: _loadError,
                      onRetry: _loadEvents,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _buildViewToggleRow(),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: ThemeCleanPremium.spaceSm)),
              SliverToBoxAdapter(
                child: _buildSourceFilterRow(),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: ThemeCleanPremium.spaceMd)),
              SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (ctx, _) {
                    final screenH = MediaQuery.sizeOf(ctx).height;
                    final minFrac = wide
                        ? 0.50
                        : _embeddedMobile
                            ? 0.52
                            : isMobile
                                ? 0.40
                                : 0.45;
                    final minH = screenH * minFrac;
                    final h = math.max(_tableCalendarTotalHeight(), minH);
                    return SizedBox(
                      height: h,
                      child: _buildTableCalendarCard(),
                    );
                  },
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
                  padding:
                      const EdgeInsets.only(top: ThemeCleanPremium.spaceMd),
                  child: _buildSelectedDayEvents(),
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
                  _agendaView == _AgendaViewKind.month,
                  () => setState(() {
                    _clearAgendaBulkUi();
                    _agendaView = _AgendaViewKind.month;
                  }))),
          Expanded(
              child: _toggleBtn(
                  'Semana',
                  Icons.view_week_rounded,
                  _agendaView == _AgendaViewKind.week,
                  () => setState(() {
                    _clearAgendaBulkUi();
                    _agendaView = _AgendaViewKind.week;
                  }))),
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

  Widget _buildCategoryFilterRow() {
    final primary = ThemeCleanPremium.primary;
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 2),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _buildPremiumCategoryFilterChip(
              label: 'Todas',
              icon: Icons.dashboard_customize_rounded,
              accent: primary,
              selected: _filterCategoryKey == null,
              onTap: () {
                _filterCategoryKey = null;
                _rebuildMerged();
              },
            ),
          ),
          for (final e in _categoryLabels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildPremiumCategoryFilterChip(
                label: e.value,
                icon: _iconForCategoryKey(e.key),
                accent: _categoryColors[e.key] ?? primary,
                selected: _filterCategoryKey == e.key,
                onTap: () {
                  _filterCategoryKey =
                      _filterCategoryKey == e.key ? null : e.key;
                  _rebuildMerged();
                },
              ),
            ),
          for (final c in _eventCategoryDocs)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Builder(
                builder: (context) {
                  final key = _categoryKeyForEventCategoryId(c.id);
                  final nome = (c.data()['nome'] ?? 'Categoria').toString();
                  final cor = c.data()['cor'];
                  final accent = cor is int
                      ? Color(cor)
                      : ThemeCleanPremium.primary;
                  return _buildPremiumCategoryFilterChip(
                    label: nome,
                    icon: Icons.label_outline_rounded,
                    accent: accent,
                    selected: _filterCategoryKey == key,
                    onTap: () {
                      _filterCategoryKey =
                          _filterCategoryKey == key ? null : key;
                      _rebuildMerged();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceFilterRow() {
    final primary = ThemeCleanPremium.primary;
    void setSource(String key) {
      setState(() {
        _filterPublicSiteOnly = false;
        _filterSourceKey = _filterSourceKey == key ? null : key;
      });
      _rebuildMerged();
    }

    void togglePublicOnly() {
      setState(() {
        _filterPublicSiteOnly = !_filterPublicSiteOnly;
        if (_filterPublicSiteOnly) {
          _filterSourceKey = null;
        }
      });
      _rebuildMerged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Origem',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 2),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildPremiumCategoryFilterChip(
                  label: 'Todas',
                  icon: Icons.layers_rounded,
                  accent: primary,
                  selected: _filterSourceKey == null && !_filterPublicSiteOnly,
                  onTap: () {
                    setState(() {
                      _filterSourceKey = null;
                      _filterPublicSiteOnly = false;
                    });
                    _rebuildMerged();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildPremiumCategoryFilterChip(
                  label: 'Agenda interna',
                  icon: Icons.edit_calendar_rounded,
                  accent: const Color(0xFF2563EB),
                  selected: _filterSourceKey == 'agenda',
                  onTap: () => setSource('agenda'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildPremiumCategoryFilterChip(
                  label: 'Feed / eventos',
                  icon: Icons.dynamic_feed_rounded,
                  accent: const Color(0xFFDB2777),
                  selected: _filterSourceKey == 'noticias',
                  onTap: () => setSource('noticias'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildPremiumCategoryFilterChip(
                  label: 'Cultos',
                  icon: Icons.church_rounded,
                  accent: const Color(0xFF16A34A),
                  selected: _filterSourceKey == 'cultos',
                  onTap: () => setSource('cultos'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _buildPremiumCategoryFilterChip(
                  label: 'Só site público',
                  icon: Icons.public_rounded,
                  accent: const Color(0xFF0D9488),
                  selected: _filterPublicSiteOnly,
                  onTap: togglePublicOnly,
                ),
              ),
            ],
          ),
        ),
      ],
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
        _buildSelectedDayEvents(),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        _buildMonthSectionHeader(),
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
    // Células altas + margem mínima (alinhado ao calendário de Escalas / Controle Total).
    final rowH = isMobile ? 76.0 : 64.0;
    final dowH = isMobile ? 34.0 : 30.0;
    final cellFs = isMobile ? 17.0 : 15.5;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF64748B), width: 1.25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: TableCalendar<_CalendarEvent>(
          locale: 'pt_BR',
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2036, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (d) =>
              _selectedDay != null && isSameDay(_selectedDay!, d),
          calendarFormat: calFormat,
          // Só swipe horizontal para mudar mês; o vertical fica livre para a página (scroll único).
          availableGestures: AvailableGestures.horizontalSwipe,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          rowHeight: rowH,
          daysOfWeekHeight: dowH,
          eventLoader: (day) => _eventsByDay[_dayKey(day)] ?? const [],
          calendarStyle: ControleTotalCalendarTheme.calendarStyle(
            cellFs: cellFs,
            primary: ThemeCleanPremium.primary,
            onSurface: ThemeCleanPremium.onSurface,
            cellMargin: const EdgeInsets.all(1.85),
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
            // Célula inteira colorida (verde 1 evento; 2–3 faixas; 4+ faixas + contador).
            markerBuilder: (context, day, events) => null,
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
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
              _focusedMonth = DateTime(focused.year, focused.month, 1);
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openDayCommandSheet(selected);
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
    final events = List<_CalendarEvent>.from(_eventsByDay[key] ?? [])
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final label = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDay!);
    final holidayName = HolidayHelper.holidayNameOn(_selectedDay!);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_note_rounded,
                    size: 20, color: Colors.blue.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label[0].toUpperCase() + label.substring(1),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                if (events.isNotEmpty)
                  Text(
                    '${events.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.blue.shade800,
                    ),
                  ),
              ],
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

  /// [overlaySheetContext]: ao tocar (detalhes/editar), fecha o sheet/modal do resumo mensal antes da ação.
  Widget _buildEventCard(_CalendarEvent ev, {BuildContext? overlaySheetContext}) {
    final color = _CalendarPageState._hexToColor(ev.eventColorHex) ?? _eventColors[ev.type] ?? ThemeCleanPremium.primaryLight;
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
                    ? Colors.deepOrange.shade400
                    : (ev.hasScheduleOverlap
                        ? Colors.blue.shade400
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
    Color bg;
    Color fg;
    switch (ev.source) {
      case 'agenda':
        label = 'Agenda interna';
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'noticias':
        label = ev.publicSite ? 'Feed / eventos' : 'Feed (só painel)';
        bg = ev.publicSite ? const Color(0xFFFCE7F3) : const Color(0xFFF3F4F6);
        fg = ev.publicSite ? const Color(0xFFBE185D) : const Color(0xFF6B7280);
        break;
      case 'cultos':
        label = 'Cultos';
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      default:
        label = ev.source;
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
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

    final radius = BorderRadius.circular(ThemeCleanPremium.radiusMd);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: ThemeCleanPremium.cardBackground,
          child: InkWell(
            onTap: () => unawaited(_openFocusedMonthEventsSheet()),
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
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
                      Icon(
                        Icons.chevron_right_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        size: 26,
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
                      final col = _categoryColors[en.key] ??
                          ThemeCleanPremium.onSurfaceVariant;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: col, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: GoogleFonts.poppins(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${en.value}',
                              style: GoogleFonts.poppins(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Toque para ver todos os eventos',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurfaceVariant,
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
        await _loadEvents();
        _restartAgendaSubscription();
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
        await _loadEvents();
        _restartAgendaSubscription();
      }
    } else {
      setState(() => _listFilter = value);
      await _loadEvents();
      _restartAgendaSubscription();
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
      ('Mês anterior', 'mes_anterior', Icons.navigate_before_rounded),
      ('Mês atual', 'mes_atual', Icons.today_rounded),
      ('Outro mês', 'mes_livre', Icons.event_note_rounded),
      ('Semanal', 'semanal', Icons.view_week_rounded),
      ('Diário', 'diario', Icons.view_day_rounded),
      ('Anual', 'anual', Icons.calendar_view_month_rounded),
      ('Por período', 'periodo', Icons.date_range_rounded),
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

  Future<void> _exportAgendaPdf() async {
    try {
      final sortedKeys = _eventsByDay.keys.toList()
        ..sort(_compareAgendaDayKeysAscending);
      if (sortedKeys.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum evento para exportar.')),
          );
        }
        return;
      }
      if (!mounted) return;
      final branding = await loadReportPdfBranding(widget.tenantId);
      if (!mounted) return;

      final refMonth = toBeginningOfSentenceCase(
        DateFormat('MMMM yyyy', 'pt_BR').format(_focusedMonth),
      );

      final data = <List<String>>[];
      for (final key in sortedKeys) {
        final events = _eventsByDay[key]!;
        for (final ev in events) {
          final titulo =
              ev.title.isNotEmpty ? ev.title : ev.type;
          data.add([
            DateFormat('dd/MM/yyyy').format(ev.dateTime),
            DateFormat('HH:mm').format(ev.dateTime),
            titulo,
            ev.type,
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
              'Agenda de eventos',
              branding: branding,
              extraLines: [
                'Referência: $refMonth',
              ],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            PdfSuperPremiumTheme.fromTextArray(
              headers: const ['Data', 'Horário', 'Título', 'Tipo'],
              data: data,
              accent: branding.accent,
              columnWidths: const {
                0: pw.FlexColumnWidth(1.15),
                1: pw.FlexColumnWidth(0.82),
                2: pw.FlexColumnWidth(2.85),
                3: pw.FlexColumnWidth(1.35),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  // ─── List View ─────────────────────────────────────────────────────────────

  Widget _buildListView({Key? key}) {
    final sortedKeys = _eventsByDay.keys.toList()
      ..sort(_compareAgendaDayKeysAscending);
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
    final events = List<_CalendarEvent>.from(_eventsByDay[dayKey] ?? [])
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final stripe = events.isEmpty
        ? ThemeCleanPremium.primary
        : (_hexToColor(events.first.eventColorHex) ??
            _categoryColors[events.first.categoryKey ?? ''] ??
            ThemeCleanPremium.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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

  String? _whatsappDigitsForEvent(_CalendarEvent ev) {
    final w = ev.contactPhone.replaceAll(RegExp(r'\D'), '');
    if (w.length >= 10) return w;
    final r = ev.responsible.replaceAll(RegExp(r'\D'), '');
    if (r.length >= 10) return r;
    return null;
  }

  Future<void> _openWhatsAppDigits(String digits) async {
    var d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return;
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length == 10 && !d.startsWith('55')) d = '55$d';
    final uri = Uri.parse('https://wa.me/$d');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _removeAgendaDocsLinkedToNoticia(String noticiaId) async {
    final q = await _agenda
        .where('noticiaId', isEqualTo: noticiaId)
        .limit(25)
        .get();
    if (q.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  void _showEventDetails(_CalendarEvent ev) {
    if (ev.id.startsWith('virt_tpl_')) {
      showModalBottomSheet<void>(
        context: context,
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
              if (ev.hasScheduleOverlap)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.groups_rounded, color: Colors.blue.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Neste dia há escala de ministério — confira horários em Escalas.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade900,
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
                        await _loadEvents();
                        _restartAgendaSubscription();
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
                        await _loadEvents();
                        _restartAgendaSubscription();
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
      await _agenda.doc(ev.id).delete();
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
      await _loadEvents();
      _restartAgendaSubscription();
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
    final primary = ThemeCleanPremium.primary;
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
    final all = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
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
                                      whatsappCtrl.text =
                                          w.replaceAll(RegExp(r'\D'), '');
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
      text: (doc?['whatsapp'] ?? ev?.contactPhone ?? '').toString(),
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
              Text(
                  existing == null
                      ? 'Novo evento (agenda)'
                      : 'Editar evento (agenda)',
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
                  builder: (_, cat, __) => DropdownButtonFormField<String>(
                    value: cat,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      prefixIcon: Icon(Icons.palette_rounded),
                    ),
                    items: [
                      ..._categoryLabels.entries.map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _categoryColors[e.key] ??
                                      ThemeCleanPremium.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(e.value)),
                            ],
                          ),
                        ),
                      ),
                      ..._eventCategoryDocs.map(
                        (c) {
                          final nome =
                              (c.data()['nome'] ?? 'Categoria').toString();
                          final cor = c.data()['cor'];
                          final col = cor is int
                              ? Color(cor)
                              : ThemeCleanPremium.primary;
                          return DropdownMenuItem(
                            value: _categoryKeyForEventCategoryId(c.id),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: col,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(nome)),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
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
                            await FirebaseAuth.instance.currentUser
                                ?.getIdToken(true);
                            final ref = await FirebaseFirestore.instance
                                .collection('igrejas')
                                .doc(widget.tenantId)
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
              Text(
                'Cor no calendário',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Toque na cor; expanda “Mais cores” para ver a paleta completa.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<Color>(
                valueListenable: agendaColorNotifier,
                builder: (_, picked, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _agendaPaletteColors.take(8).map((c) {
                        final selected = picked == c;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => agendaColorNotifier.value = c,
                            customBorder: const CircleBorder(),
                            child: Ink(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c,
                                border: Border.all(
                                  color: selected
                                      ? ThemeCleanPremium.primary
                                      : Colors.white,
                                  width: selected ? 3 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.4),
                                    blurRadius: selected ? 8 : 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 22)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    Theme(
                      data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Mais cores',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ..._agendaPaletteColors.skip(8).map((c) {
                                final selected = picked == c;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        agendaColorNotifier.value = c,
                                    customBorder: const CircleBorder(),
                                    child: Ink(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                          color: selected
                                              ? ThemeCleanPremium.primary
                                              : Colors.white,
                                          width: selected ? 3 : 1.5,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(Icons.check_rounded,
                                              color: Colors.white, size: 18)
                                          : null,
                                    ),
                                  ),
                                );
                              }),
                              ..._agendaPaletteExtraColors.map((c) {
                                final selected = picked == c;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        agendaColorNotifier.value = c,
                                    customBorder: const CircleBorder(),
                                    child: Ink(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                          color: selected
                                              ? ThemeCleanPremium.primary
                                              : Colors.white,
                                          width: selected ? 3 : 1.5,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(Icons.check_rounded,
                                              color: Colors.white, size: 18)
                                          : null,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
                                final snap = await FirebaseFirestore.instance
                                    .collection('igrejas')
                                    .doc(widget.tenantId)
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
                style: GoogleFonts.poppins(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'WhatsApp do responsável (opcional)',
                  hintText: 'DDD + número, só números',
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
                            await FirebaseAuth.instance.currentUser
                                ?.getIdToken(true);
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
                              await _agenda.doc(existing.id).update(upd);
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
                                final batch = FirebaseFirestore.instance.batch();
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
                                await batch.commit();
                              } else {
                                // Vários dias: um documento na agenda por dia, mesmos horários em cada dia.
                                final batch = FirebaseFirestore.instance.batch();
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
                                await batch.commit();
                              }
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
