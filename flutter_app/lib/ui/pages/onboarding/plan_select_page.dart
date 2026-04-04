import 'package:flutter/material.dart';
import '../../../models/plan.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import 'signup_gestor_page.dart';

class PlanSelectPage extends StatefulWidget {
  const PlanSelectPage({super.key});

  @override
  State<PlanSelectPage> createState() => _PlanSelectPageState();
}

class _PlanSelectPageState extends State<PlanSelectPage> {
  final _membersCtrl = TextEditingController(text: '60');
  String _selectedPlanId = 'p60';

  final List<Plan> _plans = const [
    Plan(id: 'p60', name: 'Plano 60', maxMembers: 60, monthlyPrice: 79.90),
    Plan(id: 'p150', name: 'Plano 150', maxMembers: 150, monthlyPrice: 129.90),
    Plan(id: 'p300', name: 'Plano 300', maxMembers: 300, monthlyPrice: 199.90),
    Plan(id: 'p600', name: 'Plano 600', maxMembers: 600, monthlyPrice: 299.90),
  ];

  void _autoSelectByMembers() {
    final n = int.tryParse(_membersCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 60;
    Plan chosen = _plans.first;
    for (final p in _plans) {
      if (n <= p.maxMembers) { chosen = p; break; }
      chosen = p;
    }
    setState(() => _selectedPlanId = chosen.id);
  }

  Plan get _selected => _plans.firstWhere((p) => p.id == _selectedPlanId);

  @override
  void initState() {
    super.initState();
    _membersCtrl.addListener(_autoSelectByMembers);
  }

  @override
  void dispose() {
    _membersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Escolha seu plano')),
      body: AppShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Comece com 30 dias grátis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text('Selecione o plano ideal para o tamanho da sua igreja. '
                      'Você pode trocar depois.'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _membersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade estimada de membros',
                      prefixIcon: Icon(Icons.groups),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Selecionado: ${_selected.name}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                )
              ],
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView.separated(
                itemCount: _plans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = _plans[i];
                  final selected = p.id == _selectedPlanId;
                  final price = p.monthlyPrice.toStringAsFixed(2).replaceAll('.', ',');

                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _selectedPlanId = p.id),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? cs.primary : const Color(0xFFE5EAF3),
                          width: selected ? 1.6 : 1.0,
                        ),
                        color: Colors.white,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: selected ? cs.primary : cs.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              selected ? Icons.check : Icons.workspace_premium,
                              color: selected ? Colors.white : cs.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text('Até ${p.maxMembers} membros • R\$ $price / mês',
                                    style: const TextStyle(color: Color(0xFF5E6B85))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.arrow_forward_ios, size: 16, color: cs.primary.withOpacity(0.65)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            PrimaryButton(
              text: 'Continuar',
              icon: Icons.arrow_forward,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SignupGestorPage(selectedPlan: _selected),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
