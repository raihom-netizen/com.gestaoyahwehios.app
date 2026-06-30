import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_module_icon_badge.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:google_fonts/google_fonts.dart';

/// Boas-vindas / trial — fluxo legado de onboarding (`/onboarding`).
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideOrganizationSignup) {
      return const IosOrganizationSignupWebPage();
    }

    return ChurchWisdomLoginBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ThemeCleanPremium.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      YahwehSaasVisualShell.brandEmblem(size: 44, glow: false),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Gestão YAHWEH',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          'Trial 30 dias',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  YahwehSaasVisualShell.hero(
                    title: 'Sistema moderno para sua igreja',
                    subtitle:
                        'Escalas, membros, avisos e financeiro — tudo organizado '
                        'com visual profissional e acesso por CPF.',
                    logoSize: 88,
                  ),
                  const SizedBox(height: 16),
                  YahwehSaasVisualShell.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _MiniFeature(
                          moduleKey: 'membro',
                          title: 'Membros',
                          subtitle: 'Cadastro e aniversariantes',
                        ),
                        const SizedBox(height: 10),
                        const _MiniFeature(
                          moduleKey: 'escala',
                          title: 'Escalas',
                          subtitle: 'Organização e avisos',
                        ),
                        const SizedBox(height: 10),
                        const _MiniFeature(
                          moduleKey: 'evento',
                          title: 'Dashboard',
                          subtitle: 'KPIs e gráficos',
                        ),
                        const SizedBox(height: 18),
                        YahwehSaasVisualShell.primaryButton(
                          label: 'Começar agora',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () =>
                              Navigator.pushNamed(context, '/onboarding/plano'),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/igreja/login'),
                            child: const Text('Já tenho conta'),
                          ),
                        ),
                        Text(
                          'Você cria o 1º gestor e já começa no trial. '
                          'Depois dá pra integrar pagamento (Mercado Pago).',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.35,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
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

class _MiniFeature extends StatelessWidget {
  const _MiniFeature({
    required this.moduleKey,
    required this.title,
    required this.subtitle,
  });

  final String moduleKey;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        YahwehModuleIconBadge(moduleKey: moduleKey, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
