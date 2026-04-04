import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Resultado da tentativa de assinatura PAdES (ICP-Brasil / A1 / A3).
///
/// **Estado atual:** o app não aplica PAdES no cliente (web/mobile) por limitações de stack e segurança
/// (chave privada, bibliotecas comerciais, validação jurídica). O fluxo gera o PDF com assinatura **visual**
/// e metadados; a integração com serviço dedicado (ex.: Cloud Function + PKCS#12) pode substituir
/// [applyPadesIfPossible] no futuro.
class CarteiraPadesSigner {
  CarteiraPadesSigner._();

  static Future<PadesSignResult> applyPadesIfPossible({
    required Uint8List pdfBytes,
    required Uint8List? p12Bytes,
    required String certificatePassword,
  }) async {
    if (kIsWeb) {
      return PadesSignResult(
        pdfBytes: pdfBytes,
        applied: false,
        message: 'Assinatura PAdES com certificado A1/A3 não está disponível no navegador. Use o app instalado ou assine o PDF com leitor credenciado (ex.: Adobe/ICP-Brasil).',
      );
    }
    if (p12Bytes == null || p12Bytes.isEmpty) {
      return PadesSignResult(
        pdfBytes: pdfBytes,
        applied: false,
        message: 'Nenhum certificado .p12/.pfx carregado. Envie o arquivo em Configurar carteirinha → Certificado digital.',
      );
    }
    if (certificatePassword.isEmpty) {
      return PadesSignResult(
        pdfBytes: pdfBytes,
        applied: false,
        message: 'Informe a senha (PIN) do certificado.',
      );
    }
    // Integração PAdES: substituir por serviço seguro (nunca armazenar PIN em texto no Firestore).
    return PadesSignResult(
      pdfBytes: pdfBytes,
      applied: false,
      message: 'PAdES no app: em roadmap — o PDF foi gerado com assinatura visual e QR de consulta. Para valor jurídico ICP-Brasil, use assinatura externa ou integração backend.',
    );
  }
}

class PadesSignResult {
  final Uint8List pdfBytes;
  final bool applied;
  final String? message;

  const PadesSignResult({
    required this.pdfBytes,
    required this.applied,
    this.message,
  });
}
