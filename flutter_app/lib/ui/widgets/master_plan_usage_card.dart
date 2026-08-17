import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/saas_plan_limits.dart';

class MasterPlanUsageCard extends StatelessWidget {
  const MasterPlanUsageCard({super.key, required this.plan, required this.memberCount});

  final String plan;
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    final cap = SaasPlanLimits.memberCapForTier(plan);
    final used = memberCount ?? 0;
    final remaining = cap == null ? null : cap - used;
    final rem = remaining ?? 0;
    final nearLimit = remaining != null && remaining <= 5;
    final overLimit = remaining != null && remaining < 0;
    final color = overLimit ? const Color(0xFFB91C1C) : nearLimit ? const Color(0xFFB45309) : const Color(0xFF047857);
    final title = overLimit ? 'Limite ultrapassado' : nearLimit ? 'Upgrade recomendado' : 'Plano dentro do limite';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(overLimit ? Icons.error_rounded : nearLimit ? Icons.warning_amber_rounded : Icons.verified_rounded, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15))),
            Flexible(child: Text(SaasPlanLimits.labelForTier(plan), textAlign: TextAlign.end, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text(memberCount == null ? 'Membros: carregando...' : cap == null ? 'Membros utilizados: $used · Plano ilimitado' : 'Membros: $used / $cap · Restam ${rem < 0 ? 0 : rem}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (cap != null) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 8, value: (used / cap).clamp(0.0, 1.0), backgroundColor: color.withValues(alpha: 0.12), color: color)),
          ],
          if (nearLimit || overLimit) ...[
            const SizedBox(height: 8),
            Text(overLimit ? 'A igreja precisa mudar de plano para continuar crescendo.' : 'Faltam apenas ${rem < 0 ? 0 : rem} membros para atingir o limite. Igreja e Masters devem ser alertados.', style: TextStyle(fontSize: 12, color: color, height: 1.3)),
          ],
        ],
      ),
    );
  }
}
