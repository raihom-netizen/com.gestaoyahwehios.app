import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

// ✅ Evita o erro do "R$"
String money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
String annualLabel(double monthly) => 'Anual: ${money(monthly * 10)} (12 por 10)';

class PlanTier {
  final String name;
  final String members;
  final double? monthlyPrice;
  final bool featured;

  const PlanTier({
    required this.name,
    required this.members,
    required this.monthlyPrice,
    this.featured = false,
  });
}

// ✅ Planos oficiais (SaaS)
const planTiers = <PlanTier>[
  PlanTier(name: 'Plano Inicial', members: 'Até 100 membros', monthlyPrice: 49.90),
  PlanTier(name: 'Plano Essencial', members: '100 a 150 membros', monthlyPrice: 59.90, featured: true),
  PlanTier(name: 'Plano Intermediario', members: '150 a 250 membros', monthlyPrice: 69.90),
  PlanTier(name: 'Plano Avancado', members: '250 a 350 membros', monthlyPrice: 89.90),
  PlanTier(name: 'Plano Profissional', members: '350 a 400 membros', monthlyPrice: 99.90),
  PlanTier(name: 'Plano Premium', members: '400 a 500 membros', monthlyPrice: 169.90),
  PlanTier(name: 'Plano Premium Plus', members: '500 a 600 membros', monthlyPrice: 189.90),
  PlanTier(name: 'Plano Corporativo', members: 'Acima de 600 membros', monthlyPrice: null),
];

/// ✅ Página de Planos (visual mais moderno)
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  Widget _pill(String text, {bool featured = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: featured ? const Color(0xFFE9F2FF) : const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: featured ? const Color(0xFFBBD6FF) : const Color(0xFFE3E7EF)),
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

  Widget _planCard(BuildContext context, PlanTier p) {
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
            p.monthlyPrice == null ? 'Valor a combinar' : '${money(p.monthlyPrice!)} / mês',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          if (p.monthlyPrice != null)
            Text(
              annualLabel(p.monthlyPrice!),
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: ThemeCleanPremium.minTouchTarget,
            child: FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
              ),
              child: const Text('Iniciar teste grátis'),
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
            title: const Text('Gestão YAHWEH',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false),
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
                  child: Container(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusLg),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ThemeCleanPremium.primaryLight,
                          ThemeCleanPremium.primary,
                        ],
                      ),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Planos Gestão YAHWEH',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Simples, completo e do seu jeito.\nEscolha o plano ideal conforme a quantidade de membros da sua igreja.',
                          style: TextStyle(fontSize: 14, color: Color(0xFFEAF2FF), height: 1.3),
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
                          for (final p in planTiers)
                            SizedBox(
                              width: columns == 1 ? w : (w - (16 * (columns - 1))) / columns,
                              child: _planCard(context, p),
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
                            style: TextStyle(color: Color(0xFF475467), fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonal(
                          onPressed: () => Navigator.pushNamed(context, '/signup'),
                          child: const Text('Começar agora'),
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
