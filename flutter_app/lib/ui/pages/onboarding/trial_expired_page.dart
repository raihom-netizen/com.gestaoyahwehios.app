import 'package:flutter/material.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import '../plans/renew_plan_page.dart';

class TrialExpiredPage extends StatelessWidget {
  const TrialExpiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AppShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              const Text('Seu trial expirou', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              const Text('Para continuar usando o Gestão YAHWEH, ative um plano.',
                  style: TextStyle(height: 1.35)),

              const SizedBox(height: 14),
              const SectionCard(
                child: Text(
                  'Nesta base você já tem o fluxo completo. O botão abaixo ativa o plano em modo DEMO '
                  '(sem pagamento) apenas para validar o sistema. Depois, você integra Mercado Pago e webhooks.',
                  style: TextStyle(height: 1.35),
                ),
              ),

              const Spacer(),
              PrimaryButton(
                text: 'Escolher plano',
                icon: Icons.workspace_premium,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RenewPlanPage()),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
