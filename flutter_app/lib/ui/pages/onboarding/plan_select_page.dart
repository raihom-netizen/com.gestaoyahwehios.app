import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/models/plan.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:google_fonts/google_fonts.dart';

import 'signup_gestor_page.dart';

/// Seleção de plano trial — `/onboarding/plano`.
class PlanSelectPage extends StatefulWidget {
  const PlanSelectPage({super.key});

  @override
  State<PlanSelectPage> createState() => _PlanSelectPageState();
}

class _PlanSelectPageState extends State<PlanSelectPage> {
  final _membersCtrl = TextEditingController(text: '100');
  String _selectedPlanId = planosOficiais.first.id;
  Map<String, EffectivePlanConfig>? _configs;
  StreamSubscription<Map<String, EffectivePlanConfig>>? _configsSub;

  List<PlanoOficial> get _plans {
    return planosOficiais.map((base) {
      final cfg = _configs?[base.id];
      return cfg?.toPlanoOficial() ?? base;
    }).toList();
  }

  PlanoOficial get _selected =>
      _plans.firstWhere((p) => p.id == _selectedPlanId);

  void _autoSelectByMembers() {
    final n =
        int.tryParse(_membersCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 100;
    PlanoOficial chosen = _plans.first;
    for (final p in _plans) {
      if (n <= p.maxMembers) {
        chosen = p;
        break;
      }
      chosen = p;
    }
    if (chosen.id != _selectedPlanId) {
      setState(() => _selectedPlanId = chosen.id);
    }
  }

  Plan _selectedAsLegacyPlan() {
    final p = _selected;
    return Plan(
      id: p.id,
      name: p.name,
      maxMembers: p.maxMembers,
      monthlyPrice: p.monthlyPrice ?? 0,
    );
  }

  String _money(double v) =>
      'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  void initState() {
    super.initState();
    _membersCtrl.addListener(_autoSelectByMembers);
    _configsSub = PlanPriceService.watchEffectivePlanConfigs().listen((c) {
      if (mounted) setState(() => _configs = c);
    });
  }

  @override
  void dispose() {
    _configsSub?.cancel();
    _membersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideOrganizationSignup) {
      return const IosOrganizationSignupWebPage();
    }

    return ChurchWisdomLoginBackdrop(
      appBar: ChurchWisdomLoginAppBar(
        onBack: () => Navigator.of(context).pop(),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ThemeCleanPremium.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const YahwehSaasPricingHeroBanner(
                    title: 'Escolha seu plano',
                    subtitle:
                        'Comece com 30 dias grátis. Selecione o plano ideal '
                        'para o tamanho da sua igreja — você pode trocar depois.',
                    badge: 'Trial 30 dias · Mercado Pago',
                  ),
                  const SizedBox(height: 16),
                  YahwehSaasVisualShell.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _membersCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantidade estimada de membros',
                            prefixIcon: Icon(Icons.groups_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            border: Border.all(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            'Selecionado: ${_selected.name}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ..._plans.map((p) {
                          final selected = p.id == _selectedPlanId;
                          final price = p.monthlyPrice;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd,
                                ),
                                onTap: () =>
                                    setState(() => _selectedPlanId = p.id),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusMd,
                                    ),
                                    border: Border.all(
                                      color: selected
                                          ? ThemeCleanPremium.primary
                                          : const Color(0xFFE5EAF3),
                                      width: selected ? 1.6 : 1,
                                    ),
                                    color: selected
                                        ? ThemeCleanPremium.primary
                                            .withValues(alpha: 0.04)
                                        : Colors.white,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.workspace_premium_rounded,
                                        color: selected
                                            ? ThemeCleanPremium.primary
                                            : ThemeCleanPremium.onSurfaceVariant,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              price == null
                                                  ? p.members
                                                  : '${p.members} • ${_money(price)} / mês',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: ThemeCleanPremium
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (p.featured)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE9F2FF),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            'Popular',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                        YahwehSaasVisualShell.primaryButton(
                          label: 'Continuar',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SignupGestorPage(
                                  selectedPlan: _selectedAsLegacyPlan(),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        YahwehSaasVisualShell.securityFooter(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
