import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Apple Guideline 3.1.1 — no app iOS nativo não há cadastro de igreja/organização.
/// Apenas login com conta existente; nova licença/cadastro no site (Safari).
class IosOrganizationSignupWebPage extends StatefulWidget {
  const IosOrganizationSignupWebPage({super.key});

  @override
  State<IosOrganizationSignupWebPage> createState() =>
      _IosOrganizationSignupWebPageState();
}

class _IosOrganizationSignupWebPageState
    extends State<IosOrganizationSignupWebPage> {
  bool _opening = false;

  Future<void> _openSignupSite() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final ok = await IosPaymentsGate.openOrganizationSignupExternally();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível abrir o navegador. Acesse gestaoyahweh.com.br/signup',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta e licença'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/igreja/login',
                (_) => false,
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: ThemeCleanPremium.pagePadding(context),
              child: ListView(
                children: [
                  Icon(
                    Icons.phone_iphone_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cadastro no site',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No iPhone e iPad este aplicativo é apenas para quem já '
                    'possui conta de gestão da igreja — entre com Google, Apple '
                    'ou e-mail e senha já cadastrados.\n\n'
                    'Para abrir uma nova igreja no sistema, contratar plano ou '
                    'iniciar o teste gratuito, use o site gestaoyahweh.com.br '
                    'no Safari (fora do app).',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade800,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _opening ? null : _openSignupSite,
                    icon: _opening
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.open_in_browser_rounded),
                    label: Text(
                      _opening
                          ? 'Abrindo navegador…'
                          : 'Abrir cadastro e planos no site',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        ThemeCleanPremium.minTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _opening
                        ? null
                        : () {
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/igreja/login',
                              (_) => false,
                            );
                          },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Já tenho conta — entrar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        ThemeCleanPremium.minTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
