import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_theme_context.dart';
import 'package:gestao_yahweh/ui/widgets/modern_module_ui.dart';

import 'package:gestao_yahweh/services/financial_tips_catalog_service.dart';
import 'package:gestao_yahweh/services/financial_tips_home_sync_service.dart';
import 'package:gestao_yahweh/ui/widgets/finance_tip_modern_card.dart';

/// Módulo Dicas: últimos 3 dias + botão voltar (Início ou pop).
class FinancialTipsFullscreenPage extends StatelessWidget {
  const FinancialTipsFullscreenPage({
    super.key,
    required this.tips,
    this.config,
    this.onReturn,
    this.embeddedInShell = false,
  });

  final List<FinancialTipDisplayItem> tips;
  final FinancialTipsHomeConfig? config;
  final VoidCallback? onReturn;
  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    final entries = FinancialTipsCatalogService.recentTipDays(
      tips,
      config,
      days: FinancialTipsCatalogService.kModuleHistoryDays,
    );

    void handleReturn() {
      if (onReturn != null) {
        onReturn!();
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          'Últimos ${FinancialTipsCatalogService.kModuleHistoryDays} dias — '
          'cada dia traz uma dica diferente, alternando conforme a programação do app.',
          style: TextStyle(
            color: context.appTextPrimary,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
        SizedBox(height: 16),
        ...entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        entry.isToday
                            ? Icons.wb_sunny_rounded
                            : Icons.history_rounded,
                        size: 18,
                        color: entry.isToday
                            ? const Color(0xFFD97706)
                            : Colors.grey.shade600,
                      ),
                      SizedBox(width: 8),
                      Text(
                        entry.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: entry.isToday
                              ? const Color(0xFF0B1B4B)
                              : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                FinanceTipModernCard(
                  tip: entry.tip,
                  index: 0,
                  isTipOfDay: entry.isToday,
                  showFullText: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (embeddedInShell) {
      return Container(
        color: const Color(0xFFF0F4FF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TipsModuleTopBar(onReturn: handleReturn),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1B4B),
        foregroundColor: Colors.white,
        title: Text(
          'Dicas Financeiras',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: handleReturn,
        ),
      ),
      body: body,
    );
  }
}

class _TipsModuleTopBar extends StatelessWidget {
  const _TipsModuleTopBar({required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1B4B),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: 'Voltar ao Início',
                onPressed: onReturn,
              ),
              Expanded(
                child: Text(
                  'Dicas Financeiras',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
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

Future<void> openFinancialTipsFullscreen(
  BuildContext context, {
  required List<FinancialTipDisplayItem> tips,
  FinancialTipsHomeConfig? config,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FinancialTipsFullscreenPage(
        tips: tips,
        config: config,
      ),
    ),
  );
}
