import 'package:flutter/material.dart';

import 'ios_license_reader_blocked_view.dart';

/// Compat: rotas iOS `/planos`, `/pagamento`, `/atualizar-plano` — ecrã neutro
/// sem checkout, preços ou links de vendas (Apple Guideline 3.1.1).
class IosPaymentUnavailableView extends StatelessWidget {
  final bool embedded;

  const IosPaymentUnavailableView({
    super.key,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    return IosLicenseReaderBlockedView(
      variant: IosLicenseBlockedVariant.planManagement,
      showBackButton: !embedded,
    );
  }
}
