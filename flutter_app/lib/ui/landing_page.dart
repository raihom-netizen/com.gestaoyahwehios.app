import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_yahweh_brand_logo.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';

// ✅ Evita o erro do "R$"
String money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Página de Planos em `/planos` — mesma fonte do Master: `config/plans/items` + [planosOficiais].
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  Map<String, EffectivePlanConfig>? _configs;
  StreamSubscription<Map<String, EffectivePlanConfig>>? _configsSub;

  @override
  void initState() {
    super.initState();
    _configsSub = PlanPriceService.watchEffectivePlanConfigs().listen((c) {
      if (mounted) setState(() => _configs = c);
    });
  }

  @override
  void dispose() {
    _configsSub?.cancel();
    _configsSub = null;
    super.dispose();
  }

  Widget _pill(String text, {bool featured = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: featured ? const Color(0xFFE9F2FF) : const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: featured ? const Color(0xFFBBD6FF) : const Color(0xFFE3E7EF)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: featured ? const Color(0xFF1D4ED8) : const Color(0xFF344054),
        ),
      ),
    );
  }

  Widget _planCard(
    BuildContext context,
    PlanoOficial p, {
    required double? annualPrice,
  }) {
    final border = p.featured
        ? ThemeCleanPremium.primaryLight
        : const Color(0xFFE6EAF2);

    return Container(
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: border),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (p.featured) _pill('Recomendado', featured: true),
            ],
          ),
          const SizedBox(height: 10),
          _pill(p.members),
          const SizedBox(height: 14),
          Text(
            p.monthlyPrice == null
                ? (p.note ?? 'Valor a combinar')
                : '${money(p.monthlyPrice!)} / mês',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          if (p.monthlyPrice != null && annualPrice != null)
            Text(
              'Anual: ${money(annualPrice)} · pague 10 meses e use 12',
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: ThemeCleanPremium.minTouchTarget,
            child: FilledButton(
              onPressed: () {
                Navigator.pushNamed(context, '/atualizar-plano');
              },
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
              ),
              child: const Text('Abrir checkout de licença'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: ThemeCleanPremium.minTouchTarget,
            child: OutlinedButton(
              onPressed: () {
                if (IosPaymentsGate.hideOrganizationSignup) {
                  unawaited(IosPaymentsGate.openOrganizationSignupExternally());
                } else {
                  Navigator.pushNamed(context, '/signup');
                }
              },
              child: Text(
                IosPaymentsGate.hideOrganizationSignup
                    ? 'Cadastrar no site'
                    : 'Criar conta da igreja',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '• Membros e cadastro\n'
            '• Escalas e notificações\n'
            '• Mural / notícias\n'
            '• Admin do sistema',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475467), height: 1.35),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            surfaceTintColor: Colors.transparent,
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            shadowColor: const Color(0x14000000),
            title: Row(
              children: [
                GestaoYahwehBrandLogo(height: 32, showHeroGlow: false),
                const SizedBox(width: 10),
                const Text('Gestão YAHWEH',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
                child: const Text('Home'),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                child: const Text('Cadastro'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/igreja/login'),
                  child: const Text('Entrar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceLg,
                  vertical: ThemeCleanPremium.spaceMd),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const YahwehSaasPricingHeroBanner(
                        title: 'Checkout Gestão YAHWEH',
                        subtitle:
                            'Plano e pagamento em fluxo direto.\n'
                            'Android e Web finalizam dentro do app/site; '
                            'iPhone segue para Safari conforme regra Apple.',
                        badge: 'Planos oficiais · Mercado Pago',
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _pill('12 meses pagando 10', featured: true),
                          _pill('Teste grátis 30 dias', featured: true),
                          _pill('Cancelamento fácil', featured: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final columns = w >= 1050 ? 3 : (w >= 700 ? 2 : 1);

                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final base in planosOficiais)
                            Builder(
                              builder: (context) {
                                final cfg = _configs?[base.id];
                                final p = cfg?.toPlanoOficial() ?? base;
                                final ann = cfg?.annualPrice ?? p.annualPrice;
                                return SizedBox(
                                  width: columns == 1
                                      ? w
                                      : (w - (16 * (columns - 1))) / columns,
                                  child: _planCard(context, p, annualPrice: ann),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      ThemeCleanPremium.spaceLg,
                      0,
                      ThemeCleanPremium.spaceLg,
                      ThemeCleanPremium.spaceXl),
                  child: Container(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                    decoration: ThemeCleanPremium.premiumSurfaceCard,
                    child: Row(
                      children: [
                        const Icon(Icons.verified_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Plano anual: pague 12 meses como 10. Economia de 2 mensalidades no pagamento anual.',
                            style: TextStyle(
                                color: Color(0xFF475467),
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonal(
                          onPressed: () {
                            if (IosPaymentsGate.hideOrganizationSignup) {
                              unawaited(IosPaymentsGate
                                  .openOrganizationSignupExternally());
                            } else {
                              Navigator.pushNamed(context, '/signup');
                            }
                          },
                          child: Text(
                            IosPaymentsGate.hideOrganizationSignup
                                ? 'Cadastrar no site'
                                : 'Começar agora',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
