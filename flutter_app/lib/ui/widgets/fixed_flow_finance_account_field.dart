import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/services/finance_accounts_service.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'finance_bank_brand_thumb.dart';

/// Seletor de banco/caixa para despesas e receitas fixas (cadastro Financeiro).
class FixedFlowFinanceAccountField extends StatefulWidget {
  const FixedFlowFinanceAccountField({
    super.key,
    required this.uid,
    required this.selectedAccountId,
    required this.onChanged,
    this.decorationBuilder,
  });

  final String uid;
  final String? selectedAccountId;
  final ValueChanged<String?> onChanged;
  final InputDecoration Function(BuildContext context, {required Widget prefixIcon})?
      decorationBuilder;

  @override
  State<FixedFlowFinanceAccountField> createState() =>
      _FixedFlowFinanceAccountFieldState();
}

class _FixedFlowFinanceAccountFieldState
    extends State<FixedFlowFinanceAccountField> {
  // Carrega via listOnce (one-shot, confiável no web) em vez de streamAccounts
  // (que no web vinha VAZIO no 1º frame → "Nenhuma conta cadastrada" mesmo
  // com contas existentes). Igual ao form de lançamento.
  List<FinanceAccount> _accounts = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FinanceAccountsService().listOnce(widget.uid);
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAccountId = widget.selectedAccountId;
    final onChanged = widget.onChanged;
    final decorationBuilder = widget.decorationBuilder;
    {
        final accounts = _accounts;
        final ids = accounts.map((a) => a.id).toSet();
        // Conta obrigatória: se nada válido selecionado, cai no PRIMEIRO banco
        // (e avisa o pai no próximo frame para sincronizar).
        final String? value =
            selectedAccountId != null && ids.contains(selectedAccountId)
                ? selectedAccountId
                : (accounts.isNotEmpty ? accounts.first.id : null);
        if (value != null &&
            value != selectedAccountId &&
            accounts.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onChanged(value);
          });
        }
        final prefix = Icon(
          Icons.account_balance_rounded,
          color: AppColors.primary.withValues(alpha: 0.88),
        );
        final deco = decorationBuilder?.call(context, prefixIcon: prefix) ??
            InputDecoration(
              labelText: 'Banco ou caixa',
              filled: true,
              fillColor: context.appInputFill,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: prefix,
            );

        if (!_loaded && accounts.isEmpty) {
          return InputDecorator(
            decoration: deco.copyWith(labelText: 'Banco ou caixa'),
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (accounts.isEmpty) {
          return InputDecorator(
            decoration: deco.copyWith(
              labelText: 'Banco ou caixa',
              helperText:
                  'Cadastre bancos em Financeiro → Bancos e cartões.',
            ),
            child: Text(
              'Nenhuma conta cadastrada',
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        return DropdownButtonFormField<String?>(
          key: ValueKey('fixed_acc_${value ?? 'none'}'),
          isExpanded: true,
          initialValue: value,
          decoration: deco.copyWith(
            labelText: 'Banco ou caixa',
            helperText: 'Padrão do cadastro de bancos, se definido.',
          ),
          items: [
            // Conta obrigatória — sem opção "Sem conta vinculada".
            ...accounts.map((a) {
              return DropdownMenuItem<String?>(
                value: a.id,
                child: Row(
                  children: [
                    FinanceBankBrandThumb(preset: a.preset, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: onChanged,
        );
    }
  }
}
