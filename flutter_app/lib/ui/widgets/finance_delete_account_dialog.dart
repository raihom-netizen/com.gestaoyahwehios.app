import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_theme_context.dart';

import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';

/// Escolha do usuário ao excluir um banco/cartão com lançamentos.
enum FinanceDeleteAccountChoice { cancel, transfer, deleteAll }

/// Pergunta moderna ao excluir banco/cartão: mostra quantos lançamentos há e
/// oferece **Transferir para outro banco** ou **Remover tudo** (ou Cancelar).
///
/// [canTransfer] só habilita a opção de transferir quando existe outro banco
/// de destino e há lançamentos vinculados.
Future<FinanceDeleteAccountChoice> showConfirmDeleteFinanceAccountDialog(
  BuildContext context, {
  required FinanceAccount account,
  required int linkedTransactionsCount,
  bool canTransfer = false,
}) async {
  final name = account.displayName;
  final hasTx = linkedTransactionsCount > 0;
  final countLabel = linkedTransactionsCount == 1
      ? '1 lançamento neste banco'
      : '$linkedTransactionsCount lançamentos neste banco';
  final showTransfer = hasTx && canTransfer;

  final result = await showDialog<FinanceDeleteAccountChoice>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: Icon(Icons.account_balance_wallet_rounded,
          color: AppColors.error, size: 42),
      iconPadding: const EdgeInsets.only(top: 20),
      title: Text(
        'Excluir «$name»?',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: Color(0xFF991B1B),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTx) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded,
                      color: AppColors.error, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              showTransfer
                  ? 'O que deseja fazer com esses lançamentos?'
                  : 'Ao remover, TODOS esses lançamentos serão apagados '
                      'permanentemente (não há outro banco para transferir).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: context.appTextSecondary,
              ),
            ),
          ] else
            Text(
              'Este banco não tem lançamentos. Apenas o cadastro será removido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              ),
            ),
          const SizedBox(height: 16),
          if (showTransfer) ...[
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, FinanceDeleteAccountChoice.transfer),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Transferir para outro banco',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pop(ctx, FinanceDeleteAccountChoice.deleteAll),
            icon: Icon(Icons.delete_forever_rounded, color: AppColors.error),
            label: Text(
              hasTx ? 'Remover banco e lançamentos' : 'Remover banco',
              style: TextStyle(
                  fontWeight: FontWeight.w900, color: AppColors.error),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, FinanceDeleteAccountChoice.cancel),
            child: Text('Cancelar',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.appTextSecondary)),
          ),
        ],
      ),
      actionsPadding: EdgeInsets.zero,
      actions: const [],
    ),
  );
  return result ?? FinanceDeleteAccountChoice.cancel;
}
