import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import '../plans/renew_plan_page.dart';

class TrialExpiredPage extends StatelessWidget {
  const TrialExpiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final iosReader = IosPaymentsGate.shouldHidePayments;
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
              SectionCard(
                child: Text(
                  iosReader
                      ? 'Veja os planos disponiveis e finalize a contratacao no nosso site. Apos o pagamento o plano eh ativado automaticamente neste app.'
                      : 'Nesta base você já tem o fluxo completo. O botão abaixo ativa o plano em modo DEMO (sem pagamento) apenas para validar o sistema. Depois, você integra Mercado Pago e webhooks.',
                  style: const TextStyle(height: 1.35),
                ),
              ),

              const Spacer(),
              PrimaryButton(
                text: iosReader ? 'Atualizar plano' : 'Escolher plano',
                icon: Icons.workspace_premium,
                onPressed: () {
                  if (iosReader && IosPaymentsGate.isIosNative) {
                    IosPaymentsGate.openUpgradePlansExternally(
                        source: 'trial_expired_page');
                    return;
                  }
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
