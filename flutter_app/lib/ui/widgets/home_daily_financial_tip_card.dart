import 'package:flutter/material.dart';

import 'package:gestao_yahweh/services/financial_tips_catalog_service.dart';
import 'package:gestao_yahweh/ui/pages/financial_tips_fullscreen_page.dart';
import 'package:gestao_yahweh/ui/widgets/finance_tip_modern_card.dart';

/// Card "Dica financeira do dia" — rotativo por dia, visível para TODOS os
/// membros no Início (independente do módulo Financeiro, que é restrito).
///
/// Lê `app_config/financial_tips_home` (publicado pelo Painel Master) e cai no
/// catálogo bíblico local quando não há seleção. A dica muda a cada dia.
class HomeDailyFinancialTipCard extends StatefulWidget {
  const HomeDailyFinancialTipCard({super.key});

  @override
  State<HomeDailyFinancialTipCard> createState() =>
      _HomeDailyFinancialTipCardState();
}

class _HomeDailyFinancialTipCardState extends State<HomeDailyFinancialTipCard> {
  // Stream criado UMA vez (não a cada build) — antes recriar a cada rebuild da
  // dashboard fazia o StreamBuilder resetar e o card PISCAR/SUMIR.
  late final Stream<HomeTipsCatalogSnapshot> _stream =
      FinancialTipsCatalogService.watchHomeTips().asBroadcastStream();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HomeTipsCatalogSnapshot>(
      stream: _stream,
      builder: (context, snap) {
        final data = snap.data;
        // Fallback local (catálogo bíblico, sempre disponível) — o card NUNCA
        // some por erro de rede/permissão ou emissão vazia transitória.
        var tips = data?.tips ?? const <FinancialTipDisplayItem>[];
        if (tips.isEmpty) {
          tips = FinancialTipsCatalogService.biblicalCatalog();
        }
        if (tips.isEmpty) return const SizedBox.shrink();
        final preview = FinancialTipsCatalogService.partitionForHome(
          tips,
          config: data?.config,
        );
        final tipOfDay = preview.tipOfDay;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE9EDF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF14B8A6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dica financeira do dia',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sabedoria bíblica para suas finanças · Hoje',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FinanceTipModernCard(
                tip: tipOfDay,
                index: 0,
                isTipOfDay: true,
                showFullText: true,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FinancialTipsFullscreenPage(
                        tips: tips,
                        config: data?.config,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_rounded, size: 20),
                  label: const Text('Veja mais',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF0B1B4B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No módulo Dicas você vê só os últimos 3 dias.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
