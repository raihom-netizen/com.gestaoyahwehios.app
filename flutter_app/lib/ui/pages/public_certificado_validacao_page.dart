import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/services/certificate_emitido_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Site público: `/#/validar?cid={uuid}` — confirma certificado registado em Firestore.
class PublicCertificadoValidacaoPage extends StatelessWidget {
  final String certificadoId;

  const PublicCertificadoValidacaoPage({
    super.key,
    required this.certificadoId,
  });

  @override
  Widget build(BuildContext context) {
    final cid = certificadoId.trim();
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Validar certificado'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: cid.isEmpty
            ? _invalidBody(context, 'Código de validação em falta.')
            : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: CertificateEmitidoService.getPublic(cid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final doc = snap.data;
                  if (doc == null || !doc.exists || doc.data() == null) {
                    return _invalidBody(
                      context,
                      'Não encontrámos um certificado com este código. '
                      'Verifique o link ou contacte a secretaria da sua igreja.',
                    );
                  }
                  final d = doc.data()!;
                  final nome = (d['nomeMembro'] ?? '').toString().trim();
                  final nome2 = (d['nomeMembroLinha2'] ?? '').toString().trim();
                  final evento = (d['tipoCertificadoNome'] ?? d['titulo'] ?? '')
                      .toString()
                      .trim();
                  final issuedStr = (d['issuedDateStr'] ?? '').toString().trim();
                  final ts = d['dataEmissao'];
                  String dataTxt = issuedStr;
                  if (dataTxt.isEmpty && ts is Timestamp) {
                    dataTxt = DateFormat('dd/MM/yyyy', 'pt_BR')
                        .format(ts.toDate());
                  }
                  if (dataTxt.isEmpty) {
                    dataTxt = '—';
                  }
                  return SingleChildScrollView(
                    padding: ThemeCleanPremium.pagePadding(context),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 56,
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.9),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Certificado válido',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Este documento consta nos registos electrónicos '
                                  'da plataforma Gestão YAHWEH.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Colors.grey.shade700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                _certificadoValRow(
                                    'Nome(s)',
                                    nome.isEmpty
                                        ? '—'
                                        : (nome2.isEmpty
                                            ? nome
                                            : '$nome e $nome2')),
                                _certificadoValRow(
                                    'Evento / tipo', evento.isEmpty ? '—' : evento),
                                _certificadoValRow('Data de emissão', dataTxt),
                                const SizedBox(height: 16),
                                Text(
                                  'Para cópia oficial ou conferência completa, '
                                  'dirija-se à secretaria da sua igreja.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    height: 1.35,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _invalidBody(BuildContext context, String msg) {
    return Padding(
      padding: ThemeCleanPremium.pagePadding(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _certificadoValRow(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          v,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
