import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/ui/widgets/modern_module_ui.dart';
import 'package:gestao_yahweh/ui/widgets/multi_date_month_picker_dialog.dart';

/// Ícone e gradiente padrão WISDOMAPP para exportação PDF.
abstract final class ModernPdfUi {
  ModernPdfUi._();

  static const IconData icon = Icons.picture_as_pdf_rounded;

  static const List<Color> actionGradient = [
    Color(0xFFF97316),
    Color(0xFFEA580C),
  ];

  static const List<Color> headerGradient = AppColors.logoGradient;

  static Widget iconBadge({
    double size = 40,
    Color? background,
    List<Color>? gradient,
    Color iconColor = Colors.white,
  }) {
    final g = gradient ?? actionGradient;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: background == null ? LinearGradient(colors: g) : null,
        color: background,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: g.last.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: iconColor, size: size * 0.52),
    );
  }
}

/// Resultado do diálogo de período para PDF.
class ModernPdfPeriodResult {
  const ModernPdfPeriodResult({
    required this.start,
    required this.end,
    required this.usarPadraoGoias,
  });

  final DateTime start;
  final DateTime end;
  final bool usarPadraoGoias;
}

/// Diálogo moderno WISDOMAPP: período + opção padrão Goiás → Gerar PDF.
Future<ModernPdfPeriodResult?> showModernPdfPeriodDialog(
  BuildContext context, {
  required DateTime initialStart,
  required DateTime initialEnd,
  bool initialUsarPadraoGoias = true,
  String title = 'Relatório de produtividade',
  String subtitle = 'Escolha o período para ver sua produtividade:',
  String generateLabel = 'Gerar PDF',
  bool showPadraoGoias = true,
}) async {
  DateTime dataInicio = initialStart;
  DateTime dataFim = initialEnd;
  bool usarPadraoGoias = initialUsarPadraoGoias;

  return showDialog<ModernPdfPeriodResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> pickStart() async {
          final d = await pickSingleDateWithHolidayCalendar(
            context: ctx,
            initialDate: dataInicio,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          if (d != null) setState(() => dataInicio = d);
        }

        Future<void> pickEnd() async {
          final d = await pickSingleDateWithHolidayCalendar(
            context: ctx,
            initialDate: dataFim,
            firstDate: dataInicio,
            lastDate: DateTime(2030),
          );
          if (d != null) setState(() => dataFim = d);
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: ModernPdfUi.headerGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
                          tooltip: ModernModuleUI.previewRetornarLabel,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            ModernPdfUi.icon,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, c) {
                              final narrow = c.maxWidth < 340;
                              final startField = _ModernPdfDateField(
                                label: 'Data inicial',
                                date: dataInicio,
                                onTap: pickStart,
                              );
                              final endField = _ModernPdfDateField(
                                label: 'Data final',
                                date: dataFim,
                                onTap: pickEnd,
                              );
                              if (narrow) {
                                return Column(
                                  children: [
                                    startField,
                                    SizedBox(height: 10),
                                    endField,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: startField),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 28, 10, 0),
                                    child: Text(
                                      'até',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: context.appTextSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: endField),
                                ],
                              );
                            },
                          ),
                          if (showPadraoGoias) ...[
                            SizedBox(height: 16),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(
                                  () => usarPadraoGoias = !usarPadraoGoias,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: usarPadraoGoias
                                          ? AppColors.primary.withValues(alpha: 0.35)
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Checkbox(
                                          value: usarPadraoGoias,
                                          onChanged: (v) => setState(
                                            () => usarPadraoGoias = v ?? true,
                                          ),
                                          activeColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Usar padrão Estado de Goiás',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                                color: context.appTextPrimary,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'O mês encerra à meia-noite (00:00 do dia seguinte): até 23:59 no último dia; o trecho após 00:00 do 1º entra no mês seguinte. Padrão particular: desmarque.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.35,
                                                color: context.appTextSecondary,
                                                fontWeight: FontWeight.w500,
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
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                            color: context.appTextSecondary,
                          ),
                          label: Text(
                            ModernModuleUI.previewRetornarLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(
                              ctx,
                              ModernPdfPeriodResult(
                                start: dataInicio,
                                end: dataFim,
                                usarPadraoGoias: usarPadraoGoias,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: ModernPdfUi.actionGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: ModernPdfUi.actionGradient.last
                                        .withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ModernPdfUi.iconBadge(size: 28),
                                  SizedBox(width: 10),
                                  Text(
                                    generateLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
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
        );
      },
    ),
  );
}

/// Botão laranja WISDOMAPP — padrão único «Exportar PDF» em todo o sistema.
class ModernPdfExportButton extends StatelessWidget {
  const ModernPdfExportButton({
    super.key,
    required this.onPressed,
    this.label = 'Exportar PDF',
    this.subtitle,
    this.loading = false,
    this.enabled = true,
    this.expand = true,
    this.compact = false,
    this.minimumHeight = 48,
  });

  final VoidCallback? onPressed;
  final String label;
  final String? subtitle;
  final bool loading;
  final bool enabled;
  final bool expand;
  final bool compact;
  final double minimumHeight;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading && onPressed != null;
    final radius = compact ? 14.0 : 16.0;

    Widget child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onPressed : null,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: ModernPdfUi.actionGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: active ? null : context.appChipIdleBg,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ModernPdfUi.actionGradient.last
                          .withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 16,
                vertical: compact ? 10 : 12,
              ),
              child: Row(
                mainAxisAlignment:
                    expand ? MainAxisAlignment.center : MainAxisAlignment.start,
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else if (compact)
                    Icon(
                      ModernPdfUi.icon,
                      color: active ? Colors.white : context.appChipIdleLabel,
                      size: 20,
                    )
                  else
                    ModernPdfUi.iconBadge(size: 32),
                  SizedBox(width: compact ? 8 : 12),
                  if (subtitle != null &&
                      subtitle!.trim().isNotEmpty &&
                      !compact)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  active ? Colors.white : context.appChipIdleLabel,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? Colors.white.withValues(alpha: 0.92)
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: expand ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 13 : 14,
                          letterSpacing: 0.1,
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

    if (expand) {
      child = SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}

class _ModernPdfDateField extends StatelessWidget {
  const _ModernPdfDateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: ModernModuleUI.formFieldDecoration(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.95),
                      AppColors.accent.withValues(alpha: 0.95),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.appTextSecondary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      DateFormat('dd/MM/yyyy').format(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.appTextMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
