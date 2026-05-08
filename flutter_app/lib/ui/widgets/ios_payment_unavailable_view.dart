import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_constants.dart';
import '../../data/planos_oficiais.dart';
import '../../services/plan_price_service.dart';
import '../theme_clean_premium.dart';
import 'app_shell.dart';

/// Tela de "Atualizar plano" exibida em iOS sob o gate `exibir_pagamento_ios`.
///
/// Estrategia (Apple Guideline 3.1.3 — Multiplatform Service / Reader):
///   1. Mostrar a lista de planos com precos (apenas informativo).
///   2. Botao unico "Atualizar plano" abre o navegador externo (Safari) na
///      pagina publica de planos do site (gestaoyahweh.com.br/planos), onde
///      o usuario completa a compra (PIX/cartao) via gateway externo.
///   3. O webhook do Mercado Pago atualiza o status no Firestore. O app
///      detecta via snapshot listener (ja implementado em RenewPlanPage) e
///      libera o plano automaticamente — sem nenhuma compra digital ocorrer
///      dentro do binario do app iOS.
///
/// E o mesmo padrao usado por outros apps SaaS aprovados na App Store
/// (ex.: Spotify, Netflix, Kindle e o competidor "enuves").
class IosPaymentUnavailableView extends StatefulWidget {
  /// Quando `true`, omite a AppBar (uso embutido em outro Scaffold/Shell).
  final bool embedded;

  const IosPaymentUnavailableView({
    super.key,
    this.embedded = false,
  });

  @override
  State<IosPaymentUnavailableView> createState() =>
      _IosPaymentUnavailableViewState();
}

class _IosPaymentUnavailableViewState extends State<IosPaymentUnavailableView> {
  Map<String, EffectivePlanConfig>? _configs;
  bool _opening = false;
  bool _annual = false;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    try {
      final cfg = await PlanPriceService.getEffectivePlanConfigs();
      if (mounted) setState(() => _configs = cfg);
    } catch (_) {
      // Mantem precos default de [planosOficiais].
    }
  }

  String _money(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  /// URL externa do site publico onde o usuario pode contratar/atualizar o
  /// plano. Inclui `email` quando o usuario esta autenticado, para o site
  /// pre-preencher o cadastro/login e amarrar o pagamento ao tenant correto.
  Uri _buildExternalUrl() {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    final params = <String, String>{
      'utm_source': 'app_ios',
      'utm_medium': 'manage_subscription',
      if (email.isNotEmpty) 'email': email,
    };
    return Uri.parse('${AppConstants.publicWebBaseUrl}/planos')
        .replace(queryParameters: params);
  }

  Future<void> _openExternalPlans() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final uri = _buildExternalUrl();
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Nao foi possivel abrir o navegador. Acesse gestaoyahweh.com.br/planos manualmente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Nao foi possivel abrir o navegador. Acesse gestaoyahweh.com.br/planos manualmente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _buildPlanCard(BuildContext context, PlanoOficial p) {
    final cs = Theme.of(context).colorScheme;
    final cfg = _configs?[p.id];
    final monthly = cfg?.monthlyPrice ?? p.monthlyPrice;
    final annual = cfg?.annualPrice ?? p.annualPrice;
    final priceLabel = _annual
        ? (annual != null
            ? '${_money(annual)} / ano'
            : (p.note ?? 'Sob consulta'))
        : (monthly != null
            ? '${_money(monthly)} / mes'
            : (p.note ?? 'Sob consulta'));
    final hint = _annual && monthly != null
        ? 'equivalente a ${_money(monthly)} / mes'
        : (!_annual && annual != null
            ? 'anual: ${_money(annual)} (12 por 10)'
            : null);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.featured ? cs.primary : const Color(0xFFE5EAF3),
          width: p.featured ? 1.6 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (p.featured)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Recomendado',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.members,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            priceLabel,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: p.featured ? cs.primary : const Color(0xFF1E293B),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final body = SafeArea(
      child: AppShell(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabecalho
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Atualizar plano',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Veja os planos disponiveis e finalize a contratacao no '
                    'nosso site. Depois do pagamento o plano eh ativado '
                    'automaticamente neste app.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Toggle Mensal / Anual
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _CycleChip(
                            label: 'Mensal',
                            selected: !_annual,
                            onTap: () => setState(() => _annual = false),
                          ),
                        ),
                        Expanded(
                          child: _CycleChip(
                            label: 'Anual (12 por 10)',
                            selected: _annual,
                            onTap: () => setState(() => _annual = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Lista de planos
                  LayoutBuilder(
                    builder: (context, c) {
                      final isWide = c.maxWidth >= 560;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final p in planosOficiais)
                            SizedBox(
                              width: isWide
                                  ? (c.maxWidth - 12) / 2
                                  : double.infinity,
                              child: _buildPlanCard(context, p),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  // Botao principal: abre Safari externo
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _opening ? null : _openExternalPlans,
                      icon: _opening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.open_in_new_rounded),
                      label: Text(
                        _opening
                            ? 'Abrindo navegador...'
                            : 'Atualizar plano no site',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Voce sera redirecionado para gestaoyahweh.com.br',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Card explicativo
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 20,
                          color: Color(0xFF475569),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Apos confirmar o pagamento no site, o novo plano '
                            'eh ativado automaticamente neste app — pode ser '
                            'preciso reabrir o aplicativo.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botao voltar (opcional)
                  Builder(
                    builder: (ctx) {
                      final canPop = Navigator.of(ctx).canPop();
                      if (!canPop || widget.embedded) {
                        return const SizedBox.shrink();
                      }
                      return SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Voltar ao painel'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atualizar plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}

class _CycleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CycleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : cs.primary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
