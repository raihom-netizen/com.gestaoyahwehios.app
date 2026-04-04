import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Página pública aberta pelo QR do certificado (hash `#/certificado-validar`).
class PublicCertificadoConsultaPage extends StatelessWidget {
  final String tenantId;
  final String memberId;
  final String certTipoId;
  final String issuedKey;

  const PublicCertificadoConsultaPage({
    super.key,
    required this.tenantId,
    required this.memberId,
    required this.certTipoId,
    required this.issuedKey,
  });

  @override
  Widget build(BuildContext context) {
    final ok = tenantId.isNotEmpty && memberId.isNotEmpty;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Autenticidade do certificado'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 52,
                        color: ThemeCleanPremium.primary
                            .withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        ok
                            ? 'Registro eletrônico — Gestão YAHWEH'
                            : 'Parâmetros incompletos',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        ok
                            ? 'Este QR confirma que o certificado foi emitido por uma igreja '
                                'que utiliza o sistema Gestão YAHWEH. Para conferência integral '
                                '(dados do evento, assinaturas e arquivo original), dirija-se à '
                                'secretaria da sua igreja com este código.'
                            : 'O link está incompleto ou foi cortado. Peça um novo QR à secretaria.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (ok) ...[
                        const SizedBox(height: 22),
                        _row(context, 'Igreja (ID)', tenantId),
                        _row(context, 'Membro (ID)', memberId),
                        if (certTipoId.isNotEmpty)
                          _row(context, 'Tipo', certTipoId),
                        if (issuedKey.isNotEmpty)
                          _row(context, 'Emissão (referência)', issuedKey),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _row(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            v,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
