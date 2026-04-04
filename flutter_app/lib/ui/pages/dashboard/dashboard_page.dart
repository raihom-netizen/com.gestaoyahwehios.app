import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/subscription_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/section_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          TextButton.icon(
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sair'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppShell(
        child: FutureBuilder(
          future: SubscriptionService().getCurrentForMyChurch(),
          builder: (context, snap) {
            final sub = snap.data;
            final isTrial = sub?.status == 'TRIAL';
            final end = sub?.trialEndsAt;
            final daysLeft = (isTrial && end != null)
                ? end.difference(DateTime.now()).inDays
                : null;

            return ListView(
              children: [
                const SizedBox(height: 8),
                SectionCard(
                  child: Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.person, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Olá, ${user?.displayName ?? user?.email ?? 'usuário'}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF5E6B85)),
                            ),
                          ],
                        ),
                      ),
                      if (isTrial && end != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            daysLeft != null && daysLeft >= 0
                                ? 'Trial: ${daysLeft + 1} dia(s)'
                                : 'Trial até ${_formatDate(end)}',
                            style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Cards de KPI (placeholder moderno)
                Row(
                  children: const [
                    Expanded(child: _KpiCard(title: 'Membros', value: '—', icon: Icons.groups)),
                    SizedBox(width: 10),
                    Expanded(child: _KpiCard(title: 'Escalas', value: '—', icon: Icons.event_available)),
                    SizedBox(width: 10),
                    Expanded(child: _KpiCard(title: 'Avisos', value: '—', icon: Icons.campaign)),
                  ],
                ),

                const SizedBox(height: 12),

                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Próximos passos (base pronta)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
                      Text('• Conectar telas reais de Membros, Escalas e Avisos\n• Integrar Mercado Pago para ativação automática de planos\n• Montar dashboard com KPIs reais (Firestore)',
                          style: TextStyle(height: 1.35)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({required this.title, required this.value, required this.icon});

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
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF5E6B85))),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
