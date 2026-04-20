import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/pdf/fornecedor_recibo_pdf.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart'
    show kFornecedoresModuleIcon;
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/brasil_cnpj_service.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart'
    show excluirLancamentoFinanceiroComAuditoria, showFinanceLancamentoEditorForTenant;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/module_header_premium.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_calendar_theme.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

/// Moldura para o [TableCalendar] (sombras, borda, cantos) — alinhado ao painel premium.
Widget _fornecedorAgendaCalendarPremiumShell({required Widget child}) {
  return Material(
    color: Colors.transparent,
    elevation: 0,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    ),
  );
}

/// Células do calendário de compromissos (agenda geral e agenda por fornecedor).
class FornecedorAgendaCalendarCells {
  FornecedorAgendaCalendarCells._();

  static const Color kNationalHolidayDot = Color(0xFFE11D48);

  static String dayKey(DateTime d) => DateFormat('yyyy-MM-dd')
      .format(DateTime(d.year, d.month, d.day));

  /// Dia sem compromissos — feriado nacional com célula inteira em tom rosado.
  static Widget buildPlainDay(
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
    final primary = ThemeCleanPremium.primary;

    BoxDecoration deco;
    TextStyle textStyle;
    if (isSelected) {
      deco = BoxDecoration(
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
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      );
    } else if (isToday) {
      deco = BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: primary, width: 2.2),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w800,
        color: primary,
      );
    } else if (isOutside) {
      deco = BoxDecoration(
        color: const Color(0xFFF1F5F9).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade400,
      );
    } else if (isHoliday) {
      deco = BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFFECDD3), width: 1.15),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF9F1239),
      );
    } else if (isWeekend) {
      deco = BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.05),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFBE123C),
      );
    } else {
      deco = BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.1),
      );
      textStyle = TextStyle(
        fontSize: cellFs,
        fontWeight: FontWeight.w600,
        color: ThemeCleanPremium.onSurface,
      );
    }

    final showHolidayDot =
        isHoliday && (isSelected || isToday || isOutside);

    return Padding(
      padding: outerPad,
      child: DecoratedBox(
        decoration: deco,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 0.5),
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Center(
                child: Text(day.day.toString(), style: textStyle),
              ),
              if (showHolidayDot)
                Positioned(
                  bottom: 5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: kNationalHolidayDot,
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

  /// Célula inteira preenchida quando há compromissos.
  static Widget buildDayWithCompromissos(
    BuildContext context,
    DateTime day,
    DateTime focusedDay, {
    required Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        byDay,
    required bool isToday,
    required bool isSelected,
    required bool isOutside,
  }) {
    final k = dayKey(day);
    final items = byDay[k] ?? [];
    if (items.isEmpty) {
      return buildPlainDay(
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
    final n = items.length;
    final dim = isOutside ? 0.45 : 1.0;
    const outerPad = EdgeInsets.all(1.85);
    final radius = ControleTotalCalendarTheme.cellRadius;
    final primary = ThemeCleanPremium.primary;
    const green = Color(0xFF16A34A);
    final isNationalHoliday = HolidayHelper.holidayNameOn(day) != null;

    final Color fill1 = green;
    final Color fill2 = const Color(0xFF2563EB);
    final Color fill3 = const Color(0xFF9333EA);

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
    } else if (n >= 2 && !isOutside) {
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
    final multiDay = n >= 2;
    final isWeekendCell =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final TextStyle numStyle = TextStyle(
      fontSize: cellFs,
      fontWeight:
          isSelected || isToday || multiDay ? FontWeight.w800 : FontWeight.w700,
      color: isWeekendCell ? const Color(0xFFFFE4E8) : Colors.white,
      shadows: [
        Shadow(
          color: isWeekendCell
              ? const Color(0xFF7F1D1D).withValues(alpha: 0.85)
              : const Color(0xA0000000),
          blurRadius: isWeekendCell ? 6 : 5,
          offset: const Offset(0, 1.5),
        ),
      ],
    );

    final extra = n > 3 ? n - 3 : 0;

    Widget stripes;
    if (n == 1) {
      stripes = ColoredBox(
        color: fill1.withValues(alpha: 0.93 * dim),
      );
    } else if (n == 2) {
      stripes = Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: fill1.withValues(alpha: 0.88 * dim),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: fill2.withValues(alpha: 0.88 * dim),
            ),
          ),
        ],
      );
    } else {
      final count = n > 3 ? 3 : n;
      final children = <Widget>[];
      final cols = [fill1, fill2, fill3];
      for (var i = 0; i < count; i++) {
        if (i > 0) {
          children.add(
            Container(
              width: 1.6,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          );
        }
        children.add(
          Expanded(
            child: ColoredBox(
              color: cols[i].withValues(
                alpha: (0.84 + (isSelected ? 0.06 : 0)) * dim,
              ),
            ),
          ),
        );
      }
      stripes = Row(children: children);
    }

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '+$extra',
                      style: TextStyle(
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
                      color: kNationalHolidayDot,
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
      ),
    );
  }
}

String _capitalizePtFornecedorAgenda(String s) {
  if (s.isEmpty) return s;
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

Future<bool> _confirmDeleteFornecedorCompromisso(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir compromisso?'),
      content: const Text(
        'O registro será removido permanentemente. Deseja continuar?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  return r == true;
}

/// Novo compromisso ou edição (coleção [fornecedor_compromissos]).
Future<void> showFornecedorCompromissoEditor(
  BuildContext context, {
  required CollectionReference<Map<String, dynamic>> compCol,
  required String fornecedorId,
  required DateTime day,
  QueryDocumentSnapshot<Map<String, dynamic>>? existing,
}) async {
  var initialDate = DateTime(day.year, day.month, day.day);
  final tituloCtrl = TextEditingController();
  final valorCtrl = TextEditingController();
  final timeNotify = ValueNotifier(const TimeOfDay(hour: 9, minute: 0));

  if (existing != null) {
    final m = existing.data();
    tituloCtrl.text = (m['titulo'] ?? '').toString();
    final v = m['valorEstimado'];
    if (v is num && v > 0) {
      valorCtrl.text = formatBrCurrencyInitial(v.toDouble());
    }
    final ts = m['dataVencimento'];
    if (ts is Timestamp) {
      final dtx = ts.toDate();
      initialDate = DateTime(dtx.year, dtx.month, dtx.day);
      timeNotify.value = TimeOfDay(hour: dtx.hour, minute: dtx.minute);
    }
  }

  final dateNotify = ValueNotifier<DateTime>(initialDate);

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 16, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ThemeCleanPremium.primary,
                      ThemeCleanPremium.primary.withValues(alpha: 0.88),
                    ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(10),
                        minimumSize: const Size(44, 44),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        existing == null
                            ? Icons.event_available_rounded
                            : Icons.edit_calendar_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: dateNotify,
                        builder: (_, dDay, __) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                existing == null
                                    ? 'Compromisso / vencimento'
                                    : 'Editar compromisso',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _capitalizePtFornecedorAgenda(
                                  DateFormat(
                                          "EEEE, d 'de' MMMM 'de' yyyy", 'pt_BR')
                                      .format(dDay),
                                ),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: TextField(
                  controller: tituloCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Descrição',
                    hintText: 'Ex.: Internet, aluguel, fornecedor',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrCurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Valor previsto (opcional)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: dateNotify,
                  builder: (context, dSel, _) {
                    return Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dSel,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            locale: const Locale('pt', 'BR'),
                            helpText: 'Data do compromisso',
                            cancelText: 'Cancelar',
                            confirmText: 'Definir',
                          );
                          if (picked != null) {
                            dateNotify.value = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded,
                                  color: ThemeCleanPremium.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Data do compromisso',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _capitalizePtFornecedorAgenda(
                                        DateFormat(
                                                "d 'de' MMMM 'de' yyyy", 'pt_BR')
                                            .format(dSel),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: ValueListenableBuilder<TimeOfDay>(
                  valueListenable: timeNotify,
                  builder: (context, t, _) {
                    return Material(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: t,
                            helpText: 'Horário do compromisso',
                            cancelText: 'Cancelar',
                            confirmText: 'Definir',
                          );
                          if (picked != null) timeNotify.value = picked;
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.schedule_rounded,
                                  color: ThemeCleanPremium.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Horário',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      t.format(context),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          existing == null ? 'Salvar' : 'Atualizar',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final tituloSalvar = tituloCtrl.text.trim();
  final valorParse = parseBrCurrencyInput(valorCtrl.text);
  final tod = timeNotify.value;
  final dEnd = dateNotify.value;
  timeNotify.dispose();
  dateNotify.dispose();
  tituloCtrl.dispose();
  valorCtrl.dispose();

  if (ok != true || !context.mounted) return;
  await FirebaseAuth.instance.currentUser?.getIdToken(true);
  final dt = DateTime(
    dEnd.year,
    dEnd.month,
    dEnd.day,
    tod.hour,
    tod.minute,
  );
  if (existing == null) {
    await compCol.add({
      'fornecedorId': fornecedorId,
      'titulo': tituloSalvar.isEmpty ? 'Compromisso' : tituloSalvar,
      'dataVencimento': Timestamp.fromDate(dt),
      'valorEstimado': valorParse,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    await existing.reference.update({
      'titulo': tituloSalvar.isEmpty ? 'Compromisso' : tituloSalvar,
      'dataVencimento': Timestamp.fromDate(dt),
      'valorEstimado': valorParse,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Cadastro de fornecedores/prestadores + hub financeiro integrado ao `finance`.
class FornecedoresPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final bool? podeVerFinanceiro;
  final bool? podeVerFornecedores;
  final List<String>? permissions;
  /// Dentro de [IgrejaCleanShell]: sem [ModuleHeaderPremium] duplicado; abas “pill” coladas ao cartão do módulo.
  final bool embeddedInShell;

  const FornecedoresPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.podeVerFinanceiro,
    this.podeVerFornecedores,
    this.permissions,
    this.embeddedInShell = false,
  });

  @override
  State<FornecedoresPage> createState() => _FornecedoresPageState();
}

class _FornecedoresPageState extends State<FornecedoresPage>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _q = '';
  late TabController _tabMain;

  @override
  void initState() {
    super.initState();
    _tabMain = TabController(length: 3, vsync: this);
    _tabMain.addListener(() {
      if (!_tabMain.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabMain.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _canAccess => AppPermissions.canViewFornecedores(
        widget.role,
        memberCanViewFinance: widget.podeVerFinanceiro,
        memberCanViewFornecedores: widget.podeVerFornecedores,
        permissions: widget.permissions,
      );

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('fornecedores');

  void _openHub(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FornecedorHubPage(
          tenantId: widget.tenantId,
          role: widget.role,
          fornecedorId: id,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerFornecedores: widget.podeVerFornecedores,
          permissions: widget.permissions,
        ),
      ),
    );
  }

  Future<void> _openEditor({String? docId}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FornecedorFormSheet(
        tenantId: widget.tenantId,
        col: _col,
        docId: docId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final canPop = Navigator.canPop(context);
    final embedded = widget.embeddedInShell;
    /// No shell: só faixa “pill” — sem AppBar com título (evita repetir “Fornecedores”).
    final showScaffoldAppBar = !embedded && (!isMobile || canPop);
    if (!_canAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fornecedores')),
        body: const Center(
            child: Text(
                'Acesso restrito. É necessário permissão de Fornecedores ou Financeiro.')),
      );
    }

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: showScaffoldAppBar
          ? AppBar(
              leading: canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Fornecedores & prestadores'),
              bottom: TabBar(
                controller: _tabMain,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(
                    text: 'Cadastros',
                    icon: Icon(kFornecedoresModuleIcon, size: 20),
                  ),
                  Tab(
                    text: 'Agenda geral',
                    icon: Icon(Icons.calendar_month_rounded, size: 20),
                  ),
                  Tab(
                    text: 'Lista',
                    icon: Icon(Icons.view_agenda_rounded, size: 20),
                  ),
                ],
              ),
            )
          : null,
      floatingActionButton: _tabMain.index == 0
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.42),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () => _openEditor(),
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                ),
                extendedPadding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                icon: const Icon(Icons.add_rounded, size: 24),
                label: Text(
                  'Novo cadastro',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            )
          : null,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ThemeCleanPremium.churchPanelBodyGradient),
        child: SafeArea(
          top: !embedded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (embedded)
                Container(
                  color: ThemeCleanPremium.primary,
                  child: ChurchPanelPillTabBar(
                    dense: true,
                    controller: _tabMain,
                    tabs: const [
                      Tab(
                        text: 'Cadastros',
                        icon: Icon(kFornecedoresModuleIcon, size: 18),
                      ),
                      Tab(
                        text: 'Agenda geral',
                        icon: Icon(Icons.calendar_month_rounded, size: 18),
                      ),
                      Tab(
                        text: 'Lista',
                        icon: Icon(Icons.view_agenda_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              if (!embedded && isMobile && !canPop)
                Padding(
                  padding: ThemeCleanPremium.pagePadding(context),
                  child: ModuleHeaderPremium(
                    title: 'Fornecedores & prestadores',
                    icon: kFornecedoresModuleIcon,
                    subtitle: 'Cadastro completo, financeiro e agenda de vencimentos',
                  ),
                ),
              if (!embedded && isMobile && !canPop)
                TabBar(
                  controller: _tabMain,
                  isScrollable: true,
                  labelColor: ThemeCleanPremium.primary,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: ThemeCleanPremium.primary,
                  tabs: const [
                    Tab(
                      text: 'Cadastros',
                      icon: Icon(kFornecedoresModuleIcon, size: 20),
                    ),
                    Tab(
                      text: 'Agenda geral',
                      icon: Icon(Icons.calendar_month_rounded, size: 20),
                    ),
                    Tab(
                      text: 'Lista',
                      icon: Icon(Icons.view_agenda_rounded, size: 20),
                    ),
                  ],
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabMain,
                  children: [
                    _buildCadastrosTab(),
                    _FornecedoresAgendaGeralTab(
                      tenantId: widget.tenantId,
                      colFornecedores: _col,
                      onOpenFornecedor: _openHub,
                    ),
                    _FornecedoresCompromissosListaTab(
                      tenantId: widget.tenantId,
                      colFornecedores: _col,
                      onOpenFornecedor: _openHub,
                      fornecedorIdFilter: null,
                      showFornecedorLine: true,
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

  Widget _buildCadastrosTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, CPF/CNPJ ou cidade',
              prefixIcon: Icon(Icons.search_rounded, color: ThemeCleanPremium.primary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.22)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.65), width: 1.4),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _col.orderBy('nome').limit(500).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return ChurchPanelErrorBody(
                  title: 'Erro ao carregar fornecedores',
                  error: snap.error,
                  onRetry: () => setState(() {}),
                );
              }
              if (!snap.hasData) {
                return const ChurchPanelLoadingBody();
              }
              final docs = snap.data!.docs.where((d) {
                if (_q.isEmpty) return true;
                final m = d.data();
                final blob = [
                  m['nome'],
                  m['cpfCnpj'],
                  m['cidade'],
                  m['email'],
                ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
                return blob.contains(_q);
              }).toList();

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                                ),
                                child: Icon(
                                  kFornecedoresModuleIcon,
                                  size: 44,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _q.isEmpty
                                    ? 'Nenhum fornecedor cadastrado.'
                                    : 'Nenhum resultado.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                              if (_q.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Toque em «Novo cadastro» para incluir o primeiro.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 88),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final m = d.data();
                        final nome = (m['nome'] ?? '').toString().trim();
                        final status = (m['status'] ?? 'ativo').toString();
                        final statusLabel = status == 'inativo'
                            ? 'Inativo'
                            : status == 'pendente_docs'
                                ? 'Docs pendentes'
                                : 'Ativo';
                        final cidade = (m['cidade'] ?? '').toString();
                        final doc = m['cpfCnpj'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openHub(d.id),
                              borderRadius: BorderRadius.circular(22),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white,
                                      ThemeCleanPremium.primary.withValues(alpha: 0.045),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.12),
                                    width: 1.1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          gradient: LinearGradient(
                                            colors: [
                                              ThemeCleanPremium.primary,
                                              Color.lerp(ThemeCleanPremium.primary,
                                                  const Color(0xFF1E3A8A), 0.28)!,
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Icon(kFornecedoresModuleIcon,
                                            color: Colors.white, size: 26),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nome.isEmpty ? 'Sem nome' : nome,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                                letterSpacing: -0.35,
                                                color: ThemeCleanPremium.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                if (doc.toString().isNotEmpty) doc.toString(),
                                                if (cidade.isNotEmpty) cidade,
                                              ].join(' · '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: Colors.grey.shade700,
                                                height: 1.25,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: status == 'inativo'
                                              ? const Color(0xFFF1F5F9)
                                              : status == 'pendente_docs'
                                                  ? const Color(0xFFFFFBEB)
                                                  : const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: status == 'inativo'
                                                ? const Color(0xFFCBD5E1)
                                                : status == 'pendente_docs'
                                                    ? const Color(0xFFFDE68A)
                                                    : const Color(0xFF86EFAC),
                                          ),
                                        ),
                                        child: Text(
                                          statusLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                            color: status == 'inativo'
                                                ? const Color(0xFF475569)
                                                : status == 'pendente_docs'
                                                    ? const Color(0xFFB45309)
                                                    : const Color(0xFF166534),
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded,
                                          color: Colors.grey.shade400),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
  }
}

/// Lista rolável de compromissos — mesmo padrão visual premium; editar/excluir sem depender do calendário.
class _FornecedoresCompromissosListaTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> colFornecedores;
  final void Function(String fornecedorId)? onOpenFornecedor;
  final String? fornecedorIdFilter;
  final bool showFornecedorLine;

  const _FornecedoresCompromissosListaTab({
    required this.tenantId,
    required this.colFornecedores,
    this.onOpenFornecedor,
    this.fornecedorIdFilter,
    required this.showFornecedorLine,
  });

  @override
  State<_FornecedoresCompromissosListaTab> createState() =>
      _FornecedoresCompromissosListaTabState();
}

class _FornecedoresCompromissosListaTabState
    extends State<_FornecedoresCompromissosListaTab>
    with AutomaticKeepAliveClientMixin {
  /// Recria subscrições Firestore após «Tentar novamente» (ex.: índice em deploy).
  int _retryNonce = 0;

  @override
  bool get wantKeepAlive => true;

  CollectionReference<Map<String, dynamic>> get _compCol => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('fornecedor_compromissos');

  Query<Map<String, dynamic>> get _query {
    final f = (widget.fornecedorIdFilter ?? '').trim();
    if (f.isEmpty) {
      return _compCol.orderBy('dataVencimento', descending: true).limit(400);
    }
    return _compCol
        .where('fornecedorId', isEqualTo: f)
        .orderBy('dataVencimento', descending: true)
        .limit(200);
  }

  Future<void> _editar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data();
    final fid = (m['fornecedorId'] ?? '').toString().trim();
    if (fid.isEmpty) return;
    final ts = m['dataVencimento'];
    var day = DateTime.now();
    if (ts is Timestamp) {
      final dt = ts.toDate();
      day = DateTime(dt.year, dt.month, dt.day);
    }
    await showFornecedorCompromissoEditor(
      context,
      compCol: _compCol,
      fornecedorId: fid,
      day: day,
      existing: doc,
    );
    if (mounted) setState(() {});
  }

  Future<void> _excluir(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!await _confirmDeleteFornecedorCompromisso(context)) return;
    await doc.reference.delete();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pad = ThemeCleanPremium.pagePadding(context);
    return KeyedSubtree(
      key: ValueKey<int>(_retryNonce),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.colFornecedores.orderBy('nome').limit(500).snapshots(),
        builder: (context, fnSnap) {
          if (fnSnap.hasError) {
            return ChurchPanelErrorBody(
              title: 'Erro ao carregar cadastros de fornecedores',
              error: fnSnap.error,
              onRetry: () => setState(() => _retryNonce++),
            );
          }
          final nomePorId = <String, String>{};
          for (final d in fnSnap.data?.docs ?? []) {
            nomePorId[d.id] = (d.data()['nome'] ?? '').toString().trim();
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query.snapshots(),
            builder: (context, snap) {
            if (snap.hasError) {
              return ChurchPanelErrorBody(
                title: 'Erro ao carregar agendamentos',
                error: snap.error,
                onRetry: () => setState(() => _retryNonce++),
              );
            }
            if (!snap.hasData || !fnSnap.hasData) {
              return const ChurchPanelLoadingBody();
            }
            final docs = snap.data!.docs;
            final deep = Color.lerp(
                    ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.35) ??
                ThemeCleanPremium.primary;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.06),
                    Colors.white,
                  ],
                ),
              ),
              child: docs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: pad,
                        child: Text(
                          'Nenhum compromisso registado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: pad.copyWith(bottom: 24, top: 8),
                      itemCount: docs.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            ThemeCleanPremium.primary
                                                .withValues(alpha: 0.2),
                                            ThemeCleanPremium.primary
                                                .withValues(alpha: 0.06),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.view_agenda_rounded,
                                        size: 20,
                                        color: ThemeCleanPremium.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.showFornecedorLine
                                                ? 'Todos os agendamentos'
                                                : 'Agendamentos deste fornecedor',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              letterSpacing: -0.35,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          Text(
                                            'Toque num cartão para editar ou use os ícones · ordenado por data (mais recente primeiro)',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                              height: 1.25,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }
                        final d = docs[i - 1];
                        final m = d.data();
                        final fid = (m['fornecedorId'] ?? '').toString().trim();
                        final nomeFn = nomePorId[fid] ??
                            (fid.isEmpty ? 'Fornecedor' : 'Fornecedor #$fid');
                        final ts = m['dataVencimento'];
                        String when = '';
                        if (ts is Timestamp) {
                          when = _FornecedoresAgendaGeralTabState
                              ._formatCompromissoWhen(ts);
                        }
                        final titulo =
                            (m['titulo'] ?? '').toString().trim().isEmpty
                                ? '(sem descrição)'
                                : (m['titulo'] ?? '').toString().trim();
                        final valor = m['valorEstimado'];
                        final vStr = valor is num && valor.toDouble() > 0
                            ? NumberFormat.currency(
                                    locale: 'pt_BR', symbol: r'R$')
                                .format(valor.toDouble())
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _editar(d),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                ),
                                boxShadow: [
                                  ...ThemeCleanPremium.softUiCardShadow,
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.05),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        width: 6,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              ThemeCleanPremium.primary,
                                              deep,
                                            ],
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              14, 12, 6, 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (widget.showFornecedorLine &&
                                                  fid.isNotEmpty) ...[
                                                Text(
                                                  nomeFn,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 12,
                                                    color: ThemeCleanPremium
                                                        .primary,
                                                    letterSpacing: -0.1,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                              ],
                                              Text(
                                                titulo,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                  height: 1.2,
                                                  letterSpacing: -0.3,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                [
                                                  when,
                                                  if (vStr.isNotEmpty) vStr,
                                                ].join(' · '),
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (widget.showFornecedorLine &&
                                              fid.isNotEmpty &&
                                              widget.onOpenFornecedor !=
                                                  null)
                                            IconButton(
                                              tooltip: 'Abrir fornecedor',
                                              onPressed: () => widget
                                                  .onOpenFornecedor!(fid),
                                              icon: Icon(
                                                Icons.open_in_new_rounded,
                                                color: ThemeCleanPremium.primary,
                                                size: 22,
                                              ),
                                            ),
                                          IconButton(
                                            tooltip: 'Editar',
                                            onPressed: () => _editar(d),
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                              color: Color(0xFF16A34A),
                                              size: 22,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Excluir',
                                            onPressed: () => _excluir(d),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFDC2626),
                                              size: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        );
                      },
                    ),
            );
          },
        );
      },
    ),
    );
  }
}

/// Agenda agregada de todos os fornecedores/prestadores (coleção `fornecedor_compromissos`).
class _FornecedoresAgendaGeralTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> colFornecedores;
  final void Function(String fornecedorId) onOpenFornecedor;

  const _FornecedoresAgendaGeralTab({
    required this.tenantId,
    required this.colFornecedores,
    required this.onOpenFornecedor,
  });

  @override
  State<_FornecedoresAgendaGeralTab> createState() =>
      _FornecedoresAgendaGeralTabState();
}

class _FornecedoresAgendaGeralTabState extends State<_FornecedoresAgendaGeralTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _focused = DateTime.now();
  DateTime? _selected;

  CollectionReference<Map<String, dynamic>> get _compCol => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('fornecedor_compromissos');

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in docs) {
      final ts = d.data()['dataVencimento'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final k = DateFormat('yyyy-MM-dd')
          .format(DateTime(dt.year, dt.month, dt.day));
      map.putIfAbsent(k, () => []).add(d);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final ta = a.data()['dataVencimento'];
        final tb = b.data()['dataVencimento'];
        if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
        return 0;
      });
    }
    return map;
  }

  static String _formatCompromissoWhen(Timestamp ts) {
    final dt = ts.toDate();
    if (dt.hour == 0 && dt.minute == 0) {
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
    }
    return DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(dt);
  }

  bool _sameVisibleMonth(DateTime day, DateTime focusedDay) =>
      day.year == focusedDay.year && day.month == focusedDay.month;

  Future<void> _editarCompromissoAgendaGeral(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final m = doc.data();
    final fid = (m['fornecedorId'] ?? '').toString().trim();
    if (fid.isEmpty) return;
    final ts = m['dataVencimento'];
    var day = DateTime.now();
    if (ts is Timestamp) {
      final dt = ts.toDate();
      day = DateTime(dt.year, dt.month, dt.day);
    }
    await showFornecedorCompromissoEditor(
      context,
      compCol: _compCol,
      fornecedorId: fid,
      day: day,
      existing: doc,
    );
  }

  Future<void> _excluirCompromissoAgendaGeral(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!await _confirmDeleteFornecedorCompromisso(context)) return;
    await doc.reference.delete();
  }

  void _showDayAgendaGeralSheet(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Map<String, String> nomePorId,
  ) {
    final raw = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(day);
    final label =
        raw.isEmpty ? '' : '${raw[0].toUpperCase()}${raw.substring(1)}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.28,
        maxChildSize: 0.92,
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
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Nada neste dia.',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final d = items[i];
                            final m = d.data();
                            final fid = (m['fornecedorId'] ?? '').toString();
                            final nomeFn = nomePorId[fid] ??
                                (fid.isEmpty ? 'Fornecedor' : 'Fornecedor #$fid');
                            final ts = m['dataVencimento'];
                            String when = '';
                            if (ts is Timestamp) {
                              when = _formatCompromissoWhen(ts);
                            }
                            final valor = m['valorEstimado'];
                            final vStr = valor is num
                                ? NumberFormat.currency(
                                        locale: 'pt_BR', symbol: r'R$')
                                    .format(valor.toDouble())
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFF8FAFC),
                                        ThemeCleanPremium.primary
                                            .withValues(alpha: 0.06),
                                      ],
                                    ),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: fid.isEmpty
                                              ? null
                                              : () {
                                                  Navigator.pop(ctx);
                                                  widget.onOpenFornecedor(
                                                      fid);
                                                },
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  nomeFn,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                    color: ThemeCleanPremium
                                                        .primary,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  (m['titulo'] ?? '')
                                                      .toString(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  [when, if (vStr.isNotEmpty) vStr]
                                                      .join(' · '),
                                                  style: TextStyle(
                                                    color:
                                                        Colors.grey.shade800,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (fid.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Toque para abrir o cadastro',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .grey.shade600,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4, right: 4),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Editar compromisso',
                                              icon: const Icon(
                                                Icons.edit_rounded,
                                                color: Color(0xFF16A34A),
                                              ),
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                WidgetsBinding.instance
                                                    .addPostFrameCallback((_) {
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  _editarCompromissoAgendaGeral(
                                                      d);
                                                });
                                              },
                                            ),
                                            IconButton(
                                              tooltip: 'Excluir',
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Color(0xFFDC2626),
                                              ),
                                              onPressed: () async {
                                                Navigator.pop(ctx);
                                                await _excluirCompromissoAgendaGeral(
                                                    d);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SafeArea(child: SizedBox(height: 8)),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.colFornecedores.orderBy('nome').limit(500).snapshots(),
      builder: (context, fnSnap) {
        final nomePorId = <String, String>{};
        for (final d in fnSnap.data?.docs ?? []) {
          nomePorId[d.id] = (d.data()['nome'] ?? '').toString().trim();
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _compCol
              .orderBy('dataVencimento', descending: false)
              .limit(400)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return ChurchPanelErrorBody(
                title: 'Erro ao carregar agenda geral',
                error: snap.error,
                onRetry: () => setState(() {}),
              );
            }
            if (!snap.hasData || !fnSnap.hasData) {
              return const ChurchPanelLoadingBody();
            }
            final docs = snap.data!.docs;
            final byDay = _groupByDay(docs);

            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.05),
                    Colors.white,
                  ],
                ),
              ),
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: AlwaysScrollableScrollPhysics(
                  parent: kIsWeb
                      ? const ClampingScrollPhysics()
                      : const BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Agenda geral de serviços',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Vencimentos e compromissos de todos os fornecedores · toque no cartão para abrir o cadastro · use lápis ou excluir para alterar o compromisso',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      child: RepaintBoundary(
                        child: _fornecedorAgendaCalendarPremiumShell(
                          child: TableCalendar<Object?>(
                            locale: 'pt_BR',
                            startingDayOfWeek: StartingDayOfWeek.sunday,
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2035, 12, 31),
                            availableGestures:
                                AvailableGestures.horizontalSwipe,
                            focusedDay: _focused,
                            sixWeekMonthsEnforced: true,
                            rowHeight: ThemeCleanPremium.isMobile(context)
                                ? 64
                                : 60,
                            daysOfWeekHeight:
                                ThemeCleanPremium.isMobile(context) ? 26 : 22,
                            selectedDayPredicate: (d) =>
                                _selected != null && isSameDay(_selected, d),
                            eventLoader: (_) => const [],
                            calendarBuilders: CalendarBuilders(
                              markerBuilder: (context, day, events) => null,
                              defaultBuilder: (context, day, focusedDay) =>
                                  FornecedorAgendaCalendarCells.buildDayWithCompromissos(
                                context,
                                day,
                                focusedDay,
                                byDay: byDay,
                                isToday: isSameDay(day, DateTime.now()),
                                isSelected: _selected != null &&
                                    isSameDay(_selected!, day),
                                isOutside: false,
                              ),
                              outsideBuilder: (context, day, focusedDay) =>
                                  FornecedorAgendaCalendarCells.buildDayWithCompromissos(
                                context,
                                day,
                                focusedDay,
                                byDay: byDay,
                                isToday: isSameDay(day, DateTime.now()),
                                isSelected: _selected != null &&
                                    isSameDay(_selected!, day),
                                isOutside: true,
                              ),
                              todayBuilder: (context, day, focusedDay) =>
                                  FornecedorAgendaCalendarCells.buildDayWithCompromissos(
                                context,
                                day,
                                focusedDay,
                                byDay: byDay,
                                isToday: true,
                                isSelected: _selected != null &&
                                    isSameDay(_selected!, day),
                                isOutside: !_sameVisibleMonth(day, focusedDay),
                              ),
                              selectedBuilder: (context, day, focusedDay) =>
                                  FornecedorAgendaCalendarCells.buildDayWithCompromissos(
                                context,
                                day,
                                focusedDay,
                                byDay: byDay,
                                isToday: isSameDay(day, DateTime.now()),
                                isSelected: true,
                                isOutside: !_sameVisibleMonth(day, focusedDay),
                              ),
                            ),
                            onDaySelected: (sel, foc) {
                              setState(() {
                                _selected = sel;
                                _focused = foc;
                              });
                              final k = FornecedorAgendaCalendarCells.dayKey(sel);
                              final items = byDay[k] ?? [];
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _showDayAgendaGeralSheet(sel, items, nomePorId);
                              });
                            },
                            onPageChanged: (f) {
                              if (_focused.year != f.year ||
                                  _focused.month != f.month) {
                                setState(() => _focused = f);
                              }
                            },
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: ThemeCleanPremium.isMobile(context)
                                  ? 12
                                  : 11,
                              color: Colors.grey.shade800,
                            ),
                            weekendStyle: const TextStyle(
                              color: Color(0xFFBE123C),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: true,
                            cellMargin: const EdgeInsets.all(1.85),
                            cellPadding: EdgeInsets.zero,
                            markersMaxCount: 0,
                            markerSize: 0,
                            weekendTextStyle: const TextStyle(
                              color: Color(0xFFBE123C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          headerStyle: HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            headerPadding: const EdgeInsets.only(bottom: 6),
                            decoration: const BoxDecoration(),
                            titleTextStyle: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: -0.2,
                              color: Colors.grey.shade900,
                            ),
                            leftChevronIcon: Icon(
                              Icons.chevron_left_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 28,
                            ),
                            rightChevronIcon: Icon(
                              Icons.chevron_right_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: _FornecedoresAgendaListaHintBanner(
                          agendaGeral: true),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _FornecedoresAgendaFeriadosNacionaisCard(
                        focusedMonth: _focused,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: const _FornecedoresAgendaCalLegendaRodape(),
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
}

class _FornecedoresAgendaFeriadosNacionaisCard extends StatelessWidget {
  final DateTime focusedMonth;

  const _FornecedoresAgendaFeriadosNacionaisCard({
    required this.focusedMonth,
  });

  @override
  Widget build(BuildContext context) {
    final list =
        HolidayHelper.nationalHolidaysInMonth(focusedMonth.year, focusedMonth.month);
    final monthLabel =
        DateFormat("MMMM 'de' yyyy", 'pt_BR').format(focusedMonth);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded,
                    color: ThemeCleanPremium.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Feriados nacionais · $monthLabel',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (list.isEmpty)
              Text(
                'Nenhum feriado nacional neste mês.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              )
            else
              ...list.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          DateFormat('dd/MM', 'pt_BR').format(h.date),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ThemeCleanPremium.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          h.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
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
}

/// Direciona para a aba «Lista», onde está a grade/tabela sem precisar rolar o calendário.
class _FornecedoresAgendaListaHintBanner extends StatelessWidget {
  final bool agendaGeral;

  const _FornecedoresAgendaListaHintBanner({required this.agendaGeral});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.view_agenda_rounded,
                color: ThemeCleanPremium.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                agendaGeral
                    ? 'Lista completa e grade de todos os compromissos: use a aba Lista.'
                    : 'Todos os vencimentos deste fornecedor em lista: use a aba Lista.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rodapé: fins de semana e feriados (alinha ao calendário).
class _FornecedoresAgendaCalLegendaRodape extends StatelessWidget {
  const _FornecedoresAgendaCalLegendaRodape();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Legenda',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            _legRow(
              label: 'Fins de semana',
              dot: const Color(0xFFBE123C),
              text:
                  'cabeçalho do calendário e células sem compromisso com números em vermelho; com compromisso(s), número em tom claro.',
            ),
            const SizedBox(height: 8),
            _legRow(
              label: 'Feriado nacional',
              dot: FornecedorAgendaCalendarCells.kNationalHolidayDot,
              text:
                  'célula em tom rosado e ponto vermelho (lista de datas abaixo).',
            ),
          ],
        ),
      ),
    );
  }

  static Widget _legRow({
    required String label,
    required Color dot,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: '$label — ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Form (novo/editar) ───────────────────────────────────────────────────────

class _FornecedorFormSheet extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> col;
  final String? docId;

  const _FornecedorFormSheet({
    required this.tenantId,
    required this.col,
    this.docId,
  });

  @override
  State<_FornecedorFormSheet> createState() => _FornecedorFormSheetState();
}

class _FornecedorFormSheetState extends State<_FornecedorFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _cpfCnpjCtrl;
  late final TextEditingController _cepCtrl;
  late final TextEditingController _logCtrl;
  late final TextEditingController _numCtrl;
  late final TextEditingController _compCtrl;
  late final TextEditingController _bairroCtrl;
  late final TextEditingController _cidadeCtrl;
  late final TextEditingController _ufCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _waCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _obsCtrl;
  late final TextEditingController _pixChaveCtrl;
  late final TextEditingController _notaInternaCtrl;

  String _tipo = 'pj';
  String _status = 'ativo';
  String _pixTipo = 'aleatoria';
  int _avaliacao = 0;
  bool _loadingCep = false;
  bool _loadingCnpj = false;
  bool _saving = false;

  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController();
    _cpfCnpjCtrl = TextEditingController();
    _cepCtrl = TextEditingController();
    _logCtrl = TextEditingController();
    _numCtrl = TextEditingController();
    _compCtrl = TextEditingController();
    _bairroCtrl = TextEditingController();
    _cidadeCtrl = TextEditingController();
    _ufCtrl = TextEditingController();
    _telCtrl = TextEditingController();
    _waCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _obsCtrl = TextEditingController();
    _pixChaveCtrl = TextEditingController();
    _notaInternaCtrl = TextEditingController();
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    final d = await widget.col.doc(widget.docId).get();
    if (!d.exists || !mounted) return;
    final m = d.data()!;
    setState(() {
      _tipo = (m['tipoPessoa'] ?? 'pj').toString();
      _status = (m['status'] ?? 'ativo').toString();
      _nomeCtrl.text = (m['nome'] ?? '').toString();
      _cpfCnpjCtrl.text = (m['cpfCnpj'] ?? '').toString();
      _cepCtrl.text = (m['cep'] ?? '').toString();
      _logCtrl.text = (m['logradouro'] ?? '').toString();
      _numCtrl.text = (m['numero'] ?? '').toString();
      _compCtrl.text = (m['complemento'] ?? '').toString();
      _bairroCtrl.text = (m['bairro'] ?? '').toString();
      _cidadeCtrl.text = (m['cidade'] ?? '').toString();
      _ufCtrl.text = (m['uf'] ?? '').toString();
      _telCtrl.text = (m['telefone'] ?? '').toString();
      _waCtrl.text = (m['whatsapp'] ?? '').toString();
      _emailCtrl.text = (m['email'] ?? '').toString();
      _obsCtrl.text = (m['observacoes'] ?? '').toString();
      _pixChaveCtrl.text = (m['pixChave'] ?? '').toString();
      _notaInternaCtrl.text = (m['notaInterna'] ?? '').toString();
      final pt = (m['pixTipo'] ?? 'aleatoria').toString();
      _pixTipo = pt.isEmpty ? 'aleatoria' : pt;
      final av = m['avaliacao'];
      _avaliacao = av is int
          ? av.clamp(0, 5)
          : (int.tryParse('$av') ?? 0).clamp(0, 5);
    });
  }

  Future<void> _buscarCep() async {
    final r = await fetchCep(_cepCtrl.text);
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CEP não encontrado.')),
      );
      return;
    }
    setState(() {
      _logCtrl.text = r.logradouro ?? _logCtrl.text;
      _bairroCtrl.text = r.bairro ?? _bairroCtrl.text;
      _cidadeCtrl.text = r.localidade ?? _cidadeCtrl.text;
      _ufCtrl.text = r.uf ?? _ufCtrl.text;
    });
  }

  Future<void> _buscarCnpj() async {
    setState(() => _loadingCnpj = true);
    final r = await fetchCnpjBrasilApi(_cpfCnpjCtrl.text);
    if (!mounted) return;
    setState(() => _loadingCnpj = false);
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.rawError ?? 'Falha na consulta CNPJ.')),
      );
      return;
    }
    setState(() {
      if ((r.razaoSocial ?? '').isNotEmpty) _nomeCtrl.text = r.razaoSocial!;
      _logCtrl.text = r.logradouro ?? _logCtrl.text;
      _numCtrl.text = r.numero ?? _numCtrl.text;
      _compCtrl.text = r.complemento ?? _compCtrl.text;
      _bairroCtrl.text = r.bairro ?? _bairroCtrl.text;
      _cidadeCtrl.text = r.municipio ?? _cidadeCtrl.text;
      _ufCtrl.text = r.uf ?? _ufCtrl.text;
      if ((r.cep ?? '').isNotEmpty) _cepCtrl.text = r.cep!;
      _telCtrl.text = r.telefone ?? _telCtrl.text;
      _emailCtrl.text = r.email ?? _emailCtrl.text;
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final payload = <String, dynamic>{
        'nome': _nomeCtrl.text.trim(),
        'tipoPessoa': _tipo,
        'cpfCnpj': _cpfCnpjCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'cep': _cepCtrl.text.trim(),
        'logradouro': _logCtrl.text.trim(),
        'numero': _numCtrl.text.trim(),
        'complemento': _compCtrl.text.trim(),
        'bairro': _bairroCtrl.text.trim(),
        'cidade': _cidadeCtrl.text.trim(),
        'uf': _ufCtrl.text.trim().toUpperCase(),
        'telefone': _telCtrl.text.trim(),
        'whatsapp': _waCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'email': _emailCtrl.text.trim(),
        'observacoes': _obsCtrl.text.trim(),
        'pixChave': _pixChaveCtrl.text.trim(),
        'pixTipo': _pixTipo,
        'notaInterna': _notaInternaCtrl.text.trim(),
        'avaliacao': _avaliacao,
        'status': _status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_isEdit) {
        await widget.col.doc(widget.docId).update(payload);
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        await widget.col.add(payload);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Cadastro salvo.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _cpfCnpjCtrl.dispose();
    _cepCtrl.dispose();
    _logCtrl.dispose();
    _numCtrl.dispose();
    _compCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _ufCtrl.dispose();
    _telCtrl.dispose();
    _waCtrl.dispose();
    _emailCtrl.dispose();
    _obsCtrl.dispose();
    _pixChaveCtrl.dispose();
    _notaInternaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusLg)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    _isEdit ? 'Editar fornecedor' : 'Novo fornecedor',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'pj', label: Text('PJ (CNPJ)'), icon: Icon(Icons.business_rounded)),
                        ButtonSegment(value: 'pf', label: Text('PF (CPF)'), icon: Icon(Icons.person_rounded)),
                      ],
                      selected: {_tipo},
                      onSelectionChanged: (s) => setState(() => _tipo = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cpfCnpjCtrl,
                      decoration: InputDecoration(
                        labelText: _tipo == 'pj' ? 'CNPJ' : 'CPF',
                        border: const OutlineInputBorder(),
                        suffixIcon: _tipo == 'pj'
                            ? IconButton(
                                icon: _loadingCnpj
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.cloud_download_rounded),
                                tooltip: 'Buscar dados (BrasilAPI)',
                                onPressed: _loadingCnpj ? null : _buscarCnpj,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Razão social / nome completo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cepCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CEP',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            maxLength: 8,
                            onEditingComplete: _buscarCep,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FilledButton.tonal(
                            onPressed: _loadingCep ? null : () async {
                              setState(() => _loadingCep = true);
                              await _buscarCep();
                              if (mounted) setState(() => _loadingCep = false);
                            },
                            child: _loadingCep
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Buscar CEP'),
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _logCtrl,
                      decoration: const InputDecoration(labelText: 'Logradouro', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _numCtrl,
                            decoration: const InputDecoration(labelText: 'Nº', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _compCtrl,
                            decoration: const InputDecoration(labelText: 'Complemento', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _bairroCtrl,
                      decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _cidadeCtrl,
                            decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: TextFormField(
                            controller: _ufCtrl,
                            decoration: const InputDecoration(labelText: 'UF', border: OutlineInputBorder()),
                            maxLength: 2,
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _telCtrl,
                      decoration: const InputDecoration(labelText: 'Telefone', border: OutlineInputBorder()),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _waCtrl,
                            decoration: const InputDecoration(
                              labelText: 'WhatsApp (só números)',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Abrir WhatsApp',
                          icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                          onPressed: () async {
                            final d = _waCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                            if (d.length < 10) return;
                            final u = Uri.parse('https://wa.me/55$d');
                            if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
                          },
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pagamento (PIX)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _pixTipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de chave PIX',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                        DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                        DropdownMenuItem(value: 'email', child: Text('E-mail')),
                        DropdownMenuItem(value: 'telefone', child: Text('Telefone')),
                        DropdownMenuItem(value: 'aleatoria', child: Text('Chave aleatória')),
                      ],
                      onChanged: (v) => setState(() => _pixTipo = v ?? 'aleatoria'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _pixChaveCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Chave PIX',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Avaliação interna',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(5, (i) {
                        final n = i + 1;
                        final on = n <= _avaliacao;
                        return IconButton(
                          tooltip: '$n estrela(s)',
                          onPressed: () => setState(() {
                            _avaliacao = _avaliacao == n ? 0 : n;
                          }),
                          icon: Icon(
                            on ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: on ? const Color(0xFFCA8A04) : Colors.grey.shade400,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    TextFormField(
                      controller: _notaInternaCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notas internas (só equipe)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'ativo', child: Text('Ativo')),
                        DropdownMenuItem(value: 'pendente_docs', child: Text('Pendente de documentação')),
                        DropdownMenuItem(value: 'inativo', child: Text('Inativo')),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'ativo'),
                    ),
                    TextFormField(
                      controller: _obsCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _salvar,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Salvando…' : 'Salvar'),
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
}

// ─── Hub (detalhe) ────────────────────────────────────────────────────────────

class FornecedorHubPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String fornecedorId;
  final bool? podeVerFinanceiro;
  final bool? podeVerFornecedores;
  final List<String>? permissions;

  const FornecedorHubPage({
    super.key,
    required this.tenantId,
    required this.role,
    required this.fornecedorId,
    this.podeVerFinanceiro,
    this.podeVerFornecedores,
    this.permissions,
  });

  @override
  State<FornecedorHubPage> createState() => _FornecedorHubPageState();
}

class _FornecedorHubPageState extends State<FornecedorHubPage> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> get _fornecedorRef => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('fornecedores')
      .doc(widget.fornecedorId);

  CollectionReference<Map<String, dynamic>> get _financeCol => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('finance');

  CollectionReference<Map<String, dynamic>> get _compCol => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('fornecedor_compromissos');

  Future<void> _novaComTipo(String presetTipo) async {
    final doc = await _fornecedorRef.get();
    if (!doc.exists || !mounted) return;
    final nome = (doc.data()?['nome'] ?? '').toString();
    final ok = await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: widget.tenantId,
      presetFornecedorId: widget.fornecedorId,
      presetFornecedorNome: nome,
      lockFornecedor: true,
      panelRole: widget.role,
      presetNovoTipo: presetTipo,
    );
    if (mounted && ok) setState(() {});
  }

  Future<void> _novaDespesa() => _novaComTipo('saida');

  Future<void> _novaReceita() => _novaComTipo('entrada');

  Future<void> _editarLancamento(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final ok = await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: widget.tenantId,
      existingDoc: d,
      presetFornecedorId: widget.fornecedorId,
      lockFornecedor: true,
      panelRole: widget.role,
    );
    if (mounted && ok) setState(() {});
  }

  Future<void> _excluirLancamento(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text(
          'Tem certeza que deseja excluir este lançamento? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await excluirLancamentoFinanceiroComAuditoria(d, widget.tenantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lançamento excluído.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  Future<void> _emitirRecibo(Map<String, dynamic> m, String financeDocId) async {
    final doc = await _fornecedorRef.get();
    if (!doc.exists || !mounted) return;
    final fd = doc.data()!;
    final nomeForn = (fd['nome'] ?? '').toString();
    final cj = (fd['cpfCnpj'] ?? '').toString();
    final end = [
      fd['logradouro'],
      fd['numero'],
      fd['bairro'],
      fd['cidade'],
      fd['uf'],
    ].whereType<Object>().map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(', ');
    final valor = (m['amount'] ?? m['valor'] ?? 0);
    final v = valor is num ? valor.toDouble() : double.tryParse('$valor') ?? 0;
    final desc = (m['descricao'] ?? '').toString();
    final ts = m['createdAt'];
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    final branding = await loadReportPdfBranding(widget.tenantId);
    if (!mounted) return;
    final bytes = await buildFornecedorReciboPdf(
      branding: branding,
      fornecedorNome: nomeForn,
      fornecedorCpfCnpj: cj.isEmpty ? null : cj,
      fornecedorEndereco: end.isEmpty ? null : end,
      valor: v,
      referente: desc.isEmpty ? 'Pagamento / serviço' : desc,
      dataPagamento: dt,
    );
    if (!context.mounted) return;
    await showPdfActions(context, bytes: bytes, filename: 'recibo_fornecedor.pdf');
    await _financeCol.doc(financeDocId).update({
      'reciboEmitidoAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _fornecedorRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Fornecedor')),
            body: const Center(child: Text('Registro não encontrado.')),
          );
        }
        final nome = (snap.data!.data()?['nome'] ?? 'Fornecedor').toString();
        return Scaffold(
          backgroundColor: ThemeCleanPremium.surfaceVariant,
          appBar: AppBar(
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    ThemeCleanPremium.primary,
                    Color.lerp(ThemeCleanPremium.primary, const Color(0xFF1E3A8A), 0.38)!,
                  ],
                ),
              ),
            ),
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(kFornecedoresModuleIcon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nome,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
              indicatorColor: Colors.white,
              indicatorWeight: 3.2,
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              tabs: const [
                Tab(
                  text: 'Cadastro',
                  icon: Icon(kFornecedoresModuleIcon, size: 20),
                ),
                Tab(
                  text: 'Financeiro',
                  icon: Icon(Icons.payments_rounded, size: 20),
                ),
                Tab(
                  text: 'Agenda',
                  icon: Icon(Icons.calendar_month_rounded, size: 20),
                ),
                Tab(
                  text: 'Lista',
                  icon: Icon(Icons.view_agenda_rounded, size: 20),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              _CadastroTab(
                fornecedorRef: _fornecedorRef,
                tenantId: widget.tenantId,
              ),
              _FinanceiroTab(
                tenantId: widget.tenantId,
                fornecedorId: widget.fornecedorId,
                financeCol: _financeCol,
                onNovaDespesa: _novaDespesa,
                onNovaReceita: _novaReceita,
                onEditar: _editarLancamento,
                onExcluir: _excluirLancamento,
                onRecibo: _emitirRecibo,
              ),
              _AgendaTab(
                tenantId: widget.tenantId,
                compCol: _compCol,
                fornecedorId: widget.fornecedorId,
              ),
              _FornecedoresCompromissosListaTab(
                tenantId: widget.tenantId,
                colFornecedores: FirebaseFirestore.instance
                    .collection('igrejas')
                    .doc(widget.tenantId)
                    .collection('fornecedores'),
                onOpenFornecedor: null,
                fornecedorIdFilter: widget.fornecedorId,
                showFornecedorLine: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CadastroTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> fornecedorRef;
  final String tenantId;

  const _CadastroTab({required this.fornecedorRef, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: fornecedorRef.snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        if (m == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final end = [
          m['logradouro'],
          m['numero'],
          m['bairro'],
          m['cidade'],
          m['uf'],
          m['cep'],
        ].whereType<Object>().map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(', ');
        Future<void> openWa(String raw) async {
          final d = raw.replaceAll(RegExp(r'\D'), '');
          if (d.length < 10) return;
          var dd = d;
          if (dd.length == 10 && !dd.startsWith('55')) dd = '55$dd';
          final uri = Uri.parse('https://wa.me/$dd');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }

        final wa = (m['whatsapp'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        return ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => _FornecedorFormSheet(
                    tenantId: tenantId,
                    col: fornecedorRef.parent,
                    docId: fornecedorRef.id,
                  ),
                );
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Editar dados cadastrais', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (wa.length >= 10) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366), width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => openWa(wa),
                icon: const Icon(Icons.chat_rounded,
                    color: Color(0xFF25D366), size: 22),
                label: const Text('WhatsApp do fornecedor', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(height: 16),
            _infoTile(Icons.contact_page_rounded, 'Documento', (m['cpfCnpj'] ?? '').toString()),
            _infoTile(Icons.place_rounded, 'Endereço', end.isEmpty ? '—' : end),
            _infoTile(Icons.phone_rounded, 'Telefone', (m['telefone'] ?? '').toString()),
            _infoTile(Icons.chat_rounded, 'WhatsApp', (m['whatsapp'] ?? '').toString()),
            _infoTile(Icons.email_rounded, 'E-mail', (m['email'] ?? '').toString()),
            _infoTile(
              Icons.pix_rounded,
              'PIX',
              () {
                final ch = (m['pixChave'] ?? '').toString().trim();
                final tp = (m['pixTipo'] ?? '').toString();
                if (ch.isEmpty) return '—';
                final t = tp.isEmpty ? '' : ' ($tp)';
                return '$ch$t';
              }(),
            ),
            if (((m['notaInterna'] ?? '').toString().trim()).isNotEmpty)
              _infoTile(
                Icons.note_alt_rounded,
                'Notas internas',
                (m['notaInterna'] ?? '').toString(),
              ),
            if ((m['avaliacao'] is int && (m['avaliacao'] as int) > 0) ||
                (int.tryParse('${m['avaliacao']}') ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading:
                        const Icon(Icons.star_rounded, color: Color(0xFFCA8A04)),
                    title: const Text(
                      'Avaliação interna',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    subtitle: Row(
                      children: List.generate(5, (i) {
                        final n = i + 1;
                        final av = m['avaliacao'] is int
                            ? m['avaliacao'] as int
                            : int.tryParse('${m['avaliacao']}') ?? 0;
                        return Icon(
                          n <= av ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: const Color(0xFFCA8A04),
                          size: 22,
                        );
                      }),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _infoTile(IconData ic, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(ic, color: ThemeCleanPremium.primary),
          title: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          subtitle: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _FinanceiroTab extends StatelessWidget {
  final String tenantId;
  final String fornecedorId;
  final CollectionReference<Map<String, dynamic>> financeCol;
  final VoidCallback onNovaDespesa;
  final VoidCallback onNovaReceita;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) onEditar;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) onExcluir;
  final Future<void> Function(Map<String, dynamic> m, String id) onRecibo;

  const _FinanceiroTab({
    required this.tenantId,
    required this.fornecedorId,
    required this.financeCol,
    required this.onNovaDespesa,
    required this.onNovaReceita,
    required this.onEditar,
    required this.onExcluir,
    required this.onRecibo,
  });

  @override
  Widget build(BuildContext context) {
    final q = financeCol
        .where('fornecedorId', isEqualTo: fornecedorId)
        .orderBy('createdAt', descending: true)
        .limit(120);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE2E2),
                    foregroundColor: const Color(0xFFB91C1C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: onNovaDespesa,
                  icon: const Icon(Icons.trending_down_rounded),
                  label: const Text('Despesa', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDCEEFC),
                    foregroundColor: const Color(0xFF1D4ED8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: onNovaReceita,
                  icon: const Icon(Icons.trending_up_rounded),
                  label: const Text('Receita / estorno', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Erro: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Nenhum lançamento vinculado ainda.'));
              }
              double totalSaida = 0, totalEntrada = 0;
              for (final d in docs) {
                final m = d.data();
                final tipo = (m['type'] ?? '').toString().toLowerCase();
                final valor = (m['amount'] ?? m['valor'] ?? 0);
                final v = valor is num ? valor.toDouble() : 0.0;
                if (tipo == 'saida') totalSaida += v;
                if (tipo == 'entrada') totalEntrada += v;
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _chipResumo('Saídas', totalSaida, const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
                        const SizedBox(width: 8),
                        _chipResumo('Entradas', totalEntrada, const Color(0xFFDCEEFC), const Color(0xFF1D4ED8)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final m = d.data();
                        final tipo = (m['type'] ?? '').toString().toLowerCase();
                        final valor = (m['amount'] ?? m['valor'] ?? 0);
                        final v = valor is num ? valor.toDouble() : 0.0;
                        final ts = m['createdAt'];
                        String dataStr = '';
                        if (ts is Timestamp) {
                          dataStr = DateFormat('dd/MM/yyyy').format(ts.toDate());
                        }
                        final isSaida = tipo == 'saida';
                        final cor = isSaida ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8);
                        final emitiuRecibo = m['reciboEmitidoAt'] != null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white,
                            elevation: 0,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: cor.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: CircleAvatar(
                              backgroundColor: cor.withValues(alpha: 0.12),
                              child: Icon(
                              isSaida ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: cor,
                            ),
                            ),
                            title: Text(
                              '${isSaida ? 'Despesa' : 'Receita'} · R\$ ${v.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${m['descricao'] ?? ''}\n$dataStr · ${m['categoria'] ?? ''}'
                              '${emitiuRecibo ? '\nRecibo PDF gerado' : ''}',
                            ),
                            isThreeLine: true,
                            onTap: () => onEditar(d),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              tooltip: 'Opções',
                              onSelected: (v) async {
                                if (v == 'editar') await onEditar(d);
                                if (v == 'excluir') await onExcluir(d);
                                if (v == 'recibo') await onRecibo(m, d.id);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'editar',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Editar (comprovante, conta…)'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'excluir',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFB91C1C)),
                                      SizedBox(width: 8),
                                      Text('Excluir', style: TextStyle(color: Color(0xFFB91C1C))),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'recibo',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_as_pdf_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Emitir recibo PDF'),
                                    ],
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
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chipResumo(String label, double v, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.85))),
            Text(
              NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> compCol;
  final String fornecedorId;

  const _AgendaTab({
    required this.tenantId,
    required this.compCol,
    required this.fornecedorId,
  });

  @override
  State<_AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<_AgendaTab> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in docs) {
      final ts = d.data()['dataVencimento'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final k = DateFormat('yyyy-MM-dd')
          .format(DateTime(dt.year, dt.month, dt.day));
      map.putIfAbsent(k, () => []).add(d);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final ta = a.data()['dataVencimento'];
        final tb = b.data()['dataVencimento'];
        if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
        return 0;
      });
    }
    return map;
  }

  Future<void> _openWa(String raw) async {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return;
    var dd = d;
    if (dd.length == 10 && !dd.startsWith('55')) dd = '55$dd';
    final uri = Uri.parse('https://wa.me/$dd');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Exibe data; se não for meia-noite “pura”, inclui horário.
  static String _formatCompromissoWhen(Timestamp ts) {
    final dt = ts.toDate();
    if (dt.hour == 0 && dt.minute == 0) {
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(dt);
    }
    return DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(dt);
  }

  bool _sameVisibleMonthAgendaFornecedor(
          DateTime day, DateTime focusedDay) =>
      day.year == focusedDay.year && day.month == focusedDay.month;

  Future<void> _addNaData(DateTime day) async {
    await showFornecedorCompromissoEditor(
      context,
      compCol: widget.compCol,
      fornecedorId: widget.fornecedorId,
      day: day,
      existing: null,
    );
  }

  Future<void> _editarCompromissoFornecedor(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ts = doc.data()['dataVencimento'];
    var day = DateTime.now();
    if (ts is Timestamp) {
      final dt = ts.toDate();
      day = DateTime(dt.year, dt.month, dt.day);
    }
    await showFornecedorCompromissoEditor(
      context,
      compCol: widget.compCol,
      fornecedorId: widget.fornecedorId,
      day: day,
      existing: doc,
    );
  }

  Future<void> _excluirCompromissoFornecedor(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!await _confirmDeleteFornecedorCompromisso(context)) return;
    await doc.reference.delete();
  }

  void _showDayAgendaSheet(
    DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    String waDigits,
  ) {
    final raw = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(day);
    final label =
        raw.isEmpty ? '' : '${raw[0].toUpperCase()}${raw.substring(1)}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.28,
        maxChildSize: 0.92,
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
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (waDigits.length >= 10)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openWa(waDigits);
                          },
                          icon: const Icon(Icons.chat_rounded,
                              color: Colors.white, size: 18),
                          label: const Text('WhatsApp',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Nada neste dia. Toque em «Registrar neste dia».',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final d = items[i];
                            final m = d.data();
                            final ts = m['dataVencimento'];
                            String when = '';
                            if (ts is Timestamp) {
                              when = _formatCompromissoWhen(ts);
                            }
                            final valor = m['valorEstimado'];
                            final vStr = valor is num
                                ? NumberFormat.currency(
                                        locale: 'pt_BR', symbol: r'R$')
                                    .format(valor.toDouble())
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFF8FAFC),
                                      ThemeCleanPremium.primary
                                          .withValues(alpha: 0.06),
                                    ],
                                  ),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (m['titulo'] ?? '').toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              [when, if (vStr.isNotEmpty) vStr]
                                                  .join(' · '),
                                              style: TextStyle(
                                                color: Colors.grey.shade800,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, right: 4),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Editar',
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                              color: Color(0xFF16A34A),
                                            ),
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                if (!context.mounted) return;
                                                _editarCompromissoFornecedor(d);
                                              });
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'Excluir',
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFDC2626),
                                            ),
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await _excluirCompromissoFornecedor(
                                                  d);
                                            },
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
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _addNaData(day);
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Registrar neste dia',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fornecedorRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('fornecedores')
        .doc(widget.fornecedorId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: fornecedorRef.snapshots(),
      builder: (context, fornSnap) {
        final waFornecedor = (fornSnap.data?.data()?['whatsapp'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.compCol
              .where('fornecedorId', isEqualTo: widget.fornecedorId)
              .orderBy('dataVencimento', descending: false)
              .limit(80)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            final byDay = _groupByDay(docs);

            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.05),
                    Colors.white,
                  ],
                ),
              ),
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: AlwaysScrollableScrollPhysics(
                  parent: kIsWeb
                      ? const ClampingScrollPhysics()
                      : const BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Agenda de vencimentos',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  'Mesmo calendário da agenda geral: dia colorido = compromisso(s); rosa = feriado nacional. Toque no dia para editar ou excluir.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (waFornecedor.length >= 10)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              onPressed: () => _openWa(waFornecedor),
                              icon: const Icon(Icons.chat_rounded,
                                  color: Colors.white, size: 18),
                              label: const Text('WhatsApp',
                                  style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: _fornecedorAgendaCalendarPremiumShell(
                        child: TableCalendar<Object?>(
                          locale: 'pt_BR',
                          startingDayOfWeek: StartingDayOfWeek.sunday,
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          availableGestures:
                              AvailableGestures.horizontalSwipe,
                          focusedDay: _focused,
                          sixWeekMonthsEnforced: true,
                          rowHeight: ThemeCleanPremium.isMobile(context)
                              ? 72
                              : 64,
                          daysOfWeekHeight:
                              ThemeCleanPremium.isMobile(context) ? 28 : 22,
                          selectedDayPredicate: (d) =>
                              _selected != null && isSameDay(_selected, d),
                          eventLoader: (_) => const [],
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, events) => null,
                            defaultBuilder: (context, day, focusedDay) =>
                                FornecedorAgendaCalendarCells
                                    .buildDayWithCompromissos(
                              context,
                              day,
                              focusedDay,
                              byDay: byDay,
                              isToday: isSameDay(day, DateTime.now()),
                              isSelected: _selected != null &&
                                  isSameDay(_selected!, day),
                              isOutside: false,
                            ),
                            outsideBuilder: (context, day, focusedDay) =>
                                FornecedorAgendaCalendarCells
                                    .buildDayWithCompromissos(
                              context,
                              day,
                              focusedDay,
                              byDay: byDay,
                              isToday: isSameDay(day, DateTime.now()),
                              isSelected: _selected != null &&
                                  isSameDay(_selected!, day),
                              isOutside: true,
                            ),
                            todayBuilder: (context, day, focusedDay) =>
                                FornecedorAgendaCalendarCells
                                    .buildDayWithCompromissos(
                              context,
                              day,
                              focusedDay,
                              byDay: byDay,
                              isToday: true,
                              isSelected: _selected != null &&
                                  isSameDay(_selected!, day),
                              isOutside: !_sameVisibleMonthAgendaFornecedor(
                                  day, focusedDay),
                            ),
                            selectedBuilder: (context, day, focusedDay) =>
                                FornecedorAgendaCalendarCells
                                    .buildDayWithCompromissos(
                              context,
                              day,
                              focusedDay,
                              byDay: byDay,
                              isToday: isSameDay(day, DateTime.now()),
                              isSelected: true,
                              isOutside: !_sameVisibleMonthAgendaFornecedor(
                                  day, focusedDay),
                            ),
                          ),
                          onDaySelected: (sel, foc) {
                            setState(() {
                              _selected = sel;
                              _focused = foc;
                            });
                            final k = FornecedorAgendaCalendarCells.dayKey(sel);
                            final items = byDay[k] ?? [];
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _showDayAgendaSheet(sel, items, waFornecedor);
                            });
                          },
                          onPageChanged: (f) => setState(() => _focused = f),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: ThemeCleanPremium.isMobile(context)
                                  ? 12
                                  : 11,
                              color: Colors.grey.shade800,
                            ),
                            weekendStyle: const TextStyle(
                              color: Color(0xFFBE123C),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: true,
                            cellMargin: const EdgeInsets.all(1.85),
                            cellPadding: EdgeInsets.zero,
                            markersMaxCount: 0,
                            markerSize: 0,
                            weekendTextStyle: const TextStyle(
                              color: Color(0xFFBE123C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          headerStyle: HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            headerPadding: const EdgeInsets.only(bottom: 6),
                            decoration: const BoxDecoration(),
                            titleTextStyle: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: -0.2,
                              color: Colors.grey.shade900,
                            ),
                            leftChevronIcon: Icon(
                              Icons.chevron_left_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 28,
                            ),
                            rightChevronIcon: Icon(
                              Icons.chevron_right_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: _FornecedoresAgendaListaHintBanner(
                          agendaGeral: false),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _FornecedoresAgendaFeriadosNacionaisCard(
                        focusedMonth: _focused,
                      ),
                    ),
                  ),
                  if (_selected != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          onPressed: () => _addNaData(_selected!),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            'Novo vencimento em ${DateFormat('dd/MM/yyyy').format(_selected!)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      child: const _FornecedoresAgendaCalLegendaRodape(),
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
}
