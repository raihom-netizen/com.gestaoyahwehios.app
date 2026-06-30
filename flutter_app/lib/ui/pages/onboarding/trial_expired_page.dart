import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';

class TrialExpiredPage extends StatelessWidget {
  const TrialExpiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final iosReader = IosPaymentsGate.hideInAppPlanPurchaseUi;
    return ChurchWisdomLoginBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  YahwehSaasVisualShell.hero(
                    title: 'Período de experiência encerrado',
                    subtitle: iosReader
                        ? 'Contrate um plano no painel web.'
                        : 'Ative um plano para continuar usando o Gestão YAHWEH.',
                  ),
                  const SizedBox(height: 16),
                  YahwehSaasVisualShell.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          iosReader
                              ? 'Entre em contato com o administrador da sua igreja ou acesse o painel web para contratar um plano. Após a ativação no servidor, entre novamente neste aplicativo.'
                              : 'Escolha um plano abaixo para liberar todos os módulos, armazenamento e notificações.',
                          style: const TextStyle(height: 1.45, fontSize: 14),
                        ),
                        if (!iosReader) ...[
                          const SizedBox(height: 16),
                          YahwehSaasVisualShell.primaryButton(
                            label: 'Escolher plano',
                            icon: Icons.workspace_premium_rounded,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RenewPlanPage(),
                                ),
                              );
                            },
                          ),
                        ],
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
