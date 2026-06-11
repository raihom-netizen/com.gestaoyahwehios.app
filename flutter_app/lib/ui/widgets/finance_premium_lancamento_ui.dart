import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';

/// UI premium de lançamentos — clonado do Controle Total, cores YAHWEH.
abstract final class FinancePremiumLancamentoUi {
  FinancePremiumLancamentoUi._();

  static const Color receitaGreen = Color(0xFF15803D);
  static const Color receitaGreenLight = Color(0xFF22C55E);
  static const Color despesaRed = Color(0xFFB91C1C);
  static const Color despesaRedLight = Color(0xFFEF4444);
  static const Color transferPurple = Color(0xFF4F46E5);

  static List<Color> gradientForTipo(String tipo) {
    return switch (tipo) {
      'entrada' => const [
          Color(0xFF14532D),
          Color(0xFF15803D),
          Color(0xFF22C55E),
          ThemeCleanPremium.primary,
        ],
      'saida' => const [
          Color(0xFF7F1D1D),
          Color(0xFFB91C1C),
          Color(0xFFEF4444),
          Color(0xFFEA580C),
        ],
      _ => const [
          Color(0xFF312E81),
          Color(0xFF4F46E5),
          Color(0xFF6366F1),
          ThemeCleanPremium.primary,
        ],
    };
  }

  static Color accentForTipo(String tipo) => switch (tipo) {
        'entrada' => receitaGreen,
        'saida' => despesaRed,
        _ => transferPurple,
      };
}

/// AppBar gradiente — tela de lançamento (Controle Total).
PreferredSizeWidget financePremiumLancamentoAppBar({
  required String title,
  required VoidCallback onBack,
  required List<Color> gradientColors,
  List<Widget>? actions,
}) {
  return AppBar(
    toolbarHeight: 56,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    leading: IconButton(
      tooltip: 'Voltar',
      onPressed: onBack,
      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    flexibleSpace: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.2,
      ),
    ),
    centerTitle: true,
    actions: actions,
    iconTheme: const IconThemeData(color: Colors.white),
    foregroundColor: Colors.white,
  );
}

/// Receita / Despesa / Transferência — toggle premium.
class FinancePremiumTipoToggle extends StatelessWidget {
  const FinancePremiumTipoToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showTransfer = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool showTransfer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.08),
            ThemeCleanPremium.primaryLight.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          _chip(
            label: 'Receita',
            value: 'entrada',
            icon: Icons.arrow_downward_rounded,
            colors: const [
              FinancePremiumLancamentoUi.receitaGreen,
              FinancePremiumLancamentoUi.receitaGreenLight,
            ],
          ),
          _chip(
            label: 'Despesa',
            value: 'saida',
            icon: Icons.arrow_upward_rounded,
            colors: const [
              FinancePremiumLancamentoUi.despesaRed,
              FinancePremiumLancamentoUi.despesaRedLight,
            ],
          ),
          if (showTransfer)
            _chip(
              label: 'Transf.',
              value: 'transferencia',
              icon: Icons.swap_horiz_rounded,
              colors: const [
                FinancePremiumLancamentoUi.transferPurple,
                Color(0xFF818CF8),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
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

/// Campo valor R$ grande — estilo Controle Total.
class FinancePremiumAmountField extends StatelessWidget {
  const FinancePremiumAmountField({
    super.key,
    required this.controller,
    required this.isReceita,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isReceita;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final fontSize = narrow ? 30.0 : 34.0;
    final accent = isReceita
        ? FinancePremiumLancamentoUi.receitaGreen
        : FinancePremiumLancamentoUi.despesaRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valor',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isReceita
                  ? [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]
                  : [const Color(0xFFFFEBEE), const Color(0xFFFFF3E0)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [BrCurrencyInputFormatter()],
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => onSubmitted?.call(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: isReceita ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              prefixText: 'R\$ ',
              prefixStyle: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
              border: InputBorder.none,
              hintText: '0,00',
              hintStyle: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tile tocável (data, conta) — Controle Total.
class FinancePremiumFieldTile extends StatelessWidget {
  const FinancePremiumFieldTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.10), Colors.white],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, Color.lerp(accent, ThemeCleanPremium.primary, 0.35)!],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accent.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: accent.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration financePremiumDropdownDecoration({
  required String label,
  IconData? prefixIcon,
  Color accent = ThemeCleanPremium.primary,
}) {
  return InputDecoration(
    filled: true,
    fillColor: Colors.white,
    labelText: label,
    labelStyle: TextStyle(
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade700,
      fontSize: 13,
    ),
    prefixIcon: prefixIcon != null
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(prefixIcon, color: accent, size: 22),
          )
        : null,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.22)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent.withValues(alpha: 0.18)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

/// Rodapé Cancelar + Confirmar — formulário financeiro.
class FinancePremiumFormFooterActions extends StatelessWidget {
  const FinancePremiumFormFooterActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.saveIcon = Icons.check_rounded,
    this.accent = ThemeCleanPremium.primary,
    this.isBusy = false,
  });

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final IconData saveIcon;
  final Color accent;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 400;
        final cancel = OutlinedButton(
          onPressed: isBusy ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withValues(alpha: 0.38), width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded, size: 20),
              SizedBox(width: 8),
              Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
        );

        final save = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isBusy
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [accent, Color.lerp(accent, ThemeCleanPremium.primaryLight, 0.35)!],
            ),
            boxShadow: isBusy
                ? null
                : [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: FilledButton(
            onPressed: isBusy ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isBusy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                else
                  Icon(saveIcon, size: 21),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    saveLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cancel, const SizedBox(height: 10), save],
          );
        }
        return Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: save),
          ],
        );
      },
    );
  }
}

/// Chip de filtro — gradiente colorido quando selecionado (mobile-first).
class FinancePremiumFilterChip extends StatelessWidget {
  const FinancePremiumFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final minH = compact ? 40.0 : ThemeCleanPremium.minTouchTarget;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: minH),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      Color.lerp(accent, ThemeCleanPremium.primaryLight, 0.4)!,
                    ],
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 0 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 16 : 18,
                color: selected ? Colors.white : accent.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 11.5 : 13,
                  color: selected ? Colors.white : const Color(0xFF334155),
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmento colorido — vínculo, situação, tipo de conta (área de toque ≥ 48px).
class FinancePremiumColorSegment<T> extends StatelessWidget {
  const FinancePremiumColorSegment({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.options,
    this.scrollable = true,
  });

  final T selected;
  final ValueChanged<T> onChanged;
  final List<({
    T value,
    String label,
    IconData icon,
    List<Color> colors,
  })> options;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 380;
    final children = options.map((opt) {
      final isSel = selected == opt.value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(opt.value),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              constraints: BoxConstraints(
                minHeight: ThemeCleanPremium.minTouchTarget,
                minWidth: narrow ? 96 : 0,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: narrow ? 10 : 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: isSel
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: opt.colors,
                      )
                    : null,
                color: isSel ? null : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSel
                      ? opt.colors.first.withValues(alpha: 0.5)
                      : const Color(0xFFCBD5E1),
                  width: isSel ? 0 : 1.3,
                ),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                          color: opt.colors.first.withValues(alpha: 0.32),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    opt.icon,
                    size: 18,
                    color: isSel ? Colors.white : opt.colors.first,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      opt.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: narrow ? 12 : 13.5,
                        color: isSel ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();

    if (scrollable || narrow) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      );
    }
    return Row(children: children);
  }
}

/// Vínculo: nenhum / fornecedor / membro.
class FinancePremiumVinculoToggle extends StatelessWidget {
  const FinancePremiumVinculoToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.includeNenhum = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool includeNenhum;

  @override
  Widget build(BuildContext context) {
    final opts = <({
      String value,
      String label,
      IconData icon,
      List<Color> colors,
    })>[
      if (includeNenhum)
        (
          value: 'nenhum',
          label: 'Nenhum',
          icon: Icons.link_off_rounded,
          colors: const [Color(0xFF64748B), Color(0xFF94A3B8)],
        ),
      (
        value: 'fornecedor',
        label: 'Fornecedor',
        icon: Icons.handshake_rounded,
        colors: const [Color(0xFF0D9488), Color(0xFF2DD4BF)],
      ),
      (
        value: 'membro',
        label: 'Membro',
        icon: Icons.person_rounded,
        colors: const [Color(0xFF2563EB), Color(0xFF60A5FA)],
      ),
    ];
    return FinancePremiumColorSegment<String>(
      selected: selected,
      onChanged: onChanged,
      options: opts,
    );
  }
}

/// Situação receita (recebido/pendente) ou despesa (pago/pendente).
class FinancePremiumSituacaoToggle extends StatelessWidget {
  const FinancePremiumSituacaoToggle({
    super.key,
    required this.confirmed,
    required this.onChanged,
    this.isReceita = true,
  });

  final bool confirmed;
  final ValueChanged<bool> onChanged;
  final bool isReceita;

  @override
  Widget build(BuildContext context) {
    return FinancePremiumColorSegment<bool>(
      selected: confirmed,
      onChanged: onChanged,
      scrollable: false,
      options: [
        (
          value: true,
          label: isReceita ? 'Recebido' : 'Pago',
          icon: Icons.check_circle_rounded,
          colors: const [
            FinancePremiumLancamentoUi.receitaGreen,
            FinancePremiumLancamentoUi.receitaGreenLight,
          ],
        ),
        (
          value: false,
          label: 'Pendente',
          icon: Icons.schedule_rounded,
          colors: const [Color(0xFFD97706), Color(0xFFFBBF24)],
        ),
      ],
    );
  }
}

/// Tipo de conta bancária: corrente / poupança / caixa.
class FinancePremiumContaTipoToggle extends StatelessWidget {
  const FinancePremiumContaTipoToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return FinancePremiumColorSegment<String>(
      selected: selected,
      onChanged: onChanged,
      options: const [
        (
          value: 'corrente',
          label: 'Corrente',
          icon: Icons.credit_card_rounded,
          colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
        ),
        (
          value: 'poupanca',
          label: 'Poupança',
          icon: Icons.savings_rounded,
          colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
        ),
        (
          value: 'caixa',
          label: 'Caixa',
          icon: Icons.payments_rounded,
          colors: [Color(0xFF059669), Color(0xFF34D399)],
        ),
      ],
    );
  }
}

/// Badge de status em cards de lançamento.
class FinancePremiumStatusPill extends StatelessWidget {
  const FinancePremiumStatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.colors,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          colors.first.withValues(alpha: 0.18),
          colors.last.withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.first.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.first),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: colors.first,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de vínculo (membro / fornecedor) no card.
class FinancePremiumVinculoPill extends StatelessWidget {
  const FinancePremiumVinculoPill({
    super.key,
    required this.label,
    required this.isMembro,
  });

  final String label;
  final bool isMembro;

  @override
  Widget build(BuildContext context) {
    final colors = isMembro
        ? const [Color(0xFF2563EB), Color(0xFF60A5FA)]
        : const [Color(0xFF0D9488), Color(0xFF2DD4BF)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.first.withValues(alpha: 0.14),
            colors.last.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.first.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMembro ? Icons.person_rounded : Icons.handshake_rounded,
            size: 13,
            color: colors.first,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: colors.first,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transferência entre contas — visual premium com fluxo origem → destino.
class FinancePremiumTransferAccountsSection extends StatelessWidget {
  const FinancePremiumTransferAccountsSection({
    super.key,
    required this.contas,
    required this.origemId,
    required this.destinoId,
    required this.onOrigemChanged,
    required this.onDestinoChanged,
    this.accent = FinancePremiumLancamentoUi.transferPurple,
  });

  final List<({String id, String nome})> contas;
  final String? origemId;
  final String? destinoId;
  final ValueChanged<String?> onOrigemChanged;
  final ValueChanged<String?> onDestinoChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _transferTile(
          label: 'Conta de origem',
          hint: 'De onde sai o valor',
          icon: Icons.account_balance_wallet_rounded,
          value: origemId,
          accent: const Color(0xFFDC2626),
          onChanged: onOrigemChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(child: Divider(color: accent.withValues(alpha: 0.25))),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, const Color(0xFF818CF8)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.swap_vert_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              Expanded(child: Divider(color: accent.withValues(alpha: 0.25))),
            ],
          ),
        ),
        _transferTile(
          label: 'Conta de destino',
          hint: 'Para onde entra o valor',
          icon: Icons.account_balance_rounded,
          value: destinoId,
          accent: FinancePremiumLancamentoUi.receitaGreen,
          onChanged: onDestinoChanged,
        ),
      ],
    );
  }

  Widget _transferTile({
    required String label,
    required String hint,
    required IconData icon,
    required String? value,
    required Color accent,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: DropdownButtonFormField<String>(
        value: value != null && contas.any((e) => e.id == value) ? value : null,
        decoration: financePremiumDropdownDecoration(
          label: label,
          prefixIcon: icon,
          accent: accent,
        ),
        hint: Text(hint),
        isExpanded: true,
        items: contas
            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nome)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// Botão de ação compacto — editar, excluir, comprovante (≥ 48px).
class FinancePremiumIconAction extends StatelessWidget {
  const FinancePremiumIconAction({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: ThemeCleanPremium.minTouchTarget,
              minHeight: ThemeCleanPremium.minTouchTarget,
            ),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.32)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.14),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// Filtros de situação — pendente, recebido, a pagar, etc.
class FinancePremiumExtraStatusFilters extends StatelessWidget {
  const FinancePremiumExtraStatusFilters({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  static const _items = [
    ('todos', 'Todos', Icons.apps_rounded, Color(0xFF64748B)),
    ('pendente_aprovacao', 'Pend. aprovação', Icons.gavel_rounded, Color(0xFFEA580C)),
    ('nao_conciliados', 'Conciliar', Icons.sync_problem_rounded, Color(0xFFF59E0B)),
    ('a_pagar', 'A pagar', Icons.schedule_rounded, Color(0xFFDC2626)),
    ('pagos', 'Pagos', Icons.check_circle_rounded, Color(0xFF059669)),
    ('a_receber', 'A receber', Icons.hourglass_top_rounded, Color(0xFF2563EB)),
    ('recebidos', 'Recebidos', Icons.payments_rounded, Color(0xFF16A34A)),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FinancePremiumFilterChip(
                label: item.$2,
                icon: item.$3,
                accent: item.$4,
                selected: selected == item.$1,
                onTap: () => onChanged(item.$1),
                compact: true,
              ),
            ),
        ],
      ),
    );
  }
}

/// Card secção do formulário.
class FinancePremiumSectionCard extends StatelessWidget {
  const FinancePremiumSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = ThemeCleanPremium.primary,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
