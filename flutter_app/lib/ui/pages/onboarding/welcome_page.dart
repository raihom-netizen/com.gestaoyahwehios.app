import 'package:flutter/material.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import 'plan_select_page.dart';
import '../auth/login_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // background suave
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withOpacity(0.10),
                    Colors.white,
                    cs.secondary.withOpacity(0.08),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: AppShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.church, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Gestão YAHWEH',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE5EAF3)),
                        ),
                        child: const Text('Trial 30 dias', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // HERO
                  SectionCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Sistema moderno para sua igreja,\nsem complicação.',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Escalas, membros, avisos e financeiro — tudo organizado '
                                'com visual profissional e acesso por CPF.',
                                style: TextStyle(height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          height: 120,
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary.withOpacity(0.18),
                                cs.primary.withOpacity(0.06),
                              ],
                            ),
                          ),
                          child: Icon(Icons.dashboard_customize, size: 54, color: cs.primary),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // benefícios rápidos
                  Row(
                    children: const [
                      Expanded(child: _MiniFeature(icon: Icons.groups, title: 'Membros', subtitle: 'Cadastro e aniversariantes')),
                      SizedBox(width: 10),
                      Expanded(child: _MiniFeature(icon: Icons.event_available, title: 'Escalas', subtitle: 'Organização e avisos')),
                      SizedBox(width: 10),
                      Expanded(child: _MiniFeature(icon: Icons.bar_chart, title: 'Dashboard', subtitle: 'KPIs e gráficos')),
                    ],
                  ),

                  const Spacer(),

                  PrimaryButton(
                    text: 'Começar agora',
                    icon: Icons.arrow_forward,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlanSelectPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text('Já tenho conta'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Você cria o 1º gestor e já começa no trial. Depois dá pra integrar pagamento (Mercado Pago).',
                    style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF5E6B85)),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _MiniFeature({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF5E6B85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
