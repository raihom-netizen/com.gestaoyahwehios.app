import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:gestao_yahweh/utils/finance_fatura_transaction_sort.dart';

/// Seletor de ordenação compartilhado nas grids de lançamentos do Financeiro.
class FinanceTransactionSortBar extends StatelessWidget {
  const FinanceTransactionSortBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final FinanceFaturaTxSortMode value;
  final ValueChanged<FinanceFaturaTxSortMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: context.appPanelDecoration(
        radius: 14,
        borderColor: context.appChipIdleBorder,
      ),
      child: Row(
        children: [
          Icon(Icons.sort_rounded, size: 18, color: context.appTextMuted),
          SizedBox(width: 8),
          if (!compact)
            Text(
              'Ordenar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          if (!compact) SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FinanceFaturaTxSortMode>(
                value: value,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final m in FinanceFaturaTxSortMode.values)
                    DropdownMenuItem(
                      value: m,
                      child:
                          Text(m.label, style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
