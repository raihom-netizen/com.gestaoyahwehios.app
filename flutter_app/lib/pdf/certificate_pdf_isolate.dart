import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:gestao_yahweh/pdf/certificate_pdf_builder.dart';

/// Entrada serializável para [Isolate.run] (apenas tipos transferíveis).
Map<String, dynamic> certificatePdfInputToMap(CertificatePdfInput input) {
  return <String, dynamic>{
    'titulo': input.titulo,
    'subtitulo': input.subtitulo,
    'texto': input.texto,
    'nomeMembro': input.nomeMembro,
    'cpfFormatado': input.cpfFormatado,
    'nomeIgreja': input.nomeIgreja,
    'local': input.local,
    'issuedDate': input.issuedDate,
    'layoutId': input.layoutId,
    'fontStyleId': input.fontStyleId,
    'colorPrimaryArgb': input.colorPrimaryArgb,
    'colorTextArgb': input.colorTextArgb,
    'pastorManual': input.pastorManual,
    'cargoManual': input.cargoManual,
    'logoBytes': input.logoBytes,
    'fontMontserratBytes': input.fontMontserratBytes,
    'fontGreatVibesBytes': input.fontGreatVibesBytes,
    'fontUnifrakturBytes': input.fontUnifrakturBytes,
    'qrValidationUrl': input.qrValidationUrl,
    'backgroundTemplateBytes': input.backgroundTemplateBytes,
    'visualTemplateId': input.visualTemplateId,
    'useLuxuryPdfFonts': input.useLuxuryPdfFonts,
    'fontCinzelDecorativeBytes': input.fontCinzelDecorativeBytes,
    'fontPinyonScriptBytes': input.fontPinyonScriptBytes,
    'fontLibreBaskervilleBytes': input.fontLibreBaskervilleBytes,
    'signatories': <dynamic>[
      for (final s in input.signatories)
        <String, dynamic>{
          'nome': s.nome,
          'cargo': s.cargo,
          if (s.signatureImageBytes != null)
            'signatureImageBytes': s.signatureImageBytes,
        },
    ],
  };
}

CertificatePdfInput _certificatePdfInputFromMap(Map<String, dynamic> m) {
  final sigRaw = m['signatories'] as List<dynamic>? ?? const [];
  return CertificatePdfInput(
    titulo: (m['titulo'] as String?) ?? '',
    subtitulo: (m['subtitulo'] as String?) ?? '',
    texto: (m['texto'] as String?) ?? '',
    nomeMembro: (m['nomeMembro'] as String?) ?? '',
    cpfFormatado: (m['cpfFormatado'] as String?) ?? '',
    nomeIgreja: (m['nomeIgreja'] as String?) ?? '',
    local: (m['local'] as String?) ?? '',
    issuedDate: (m['issuedDate'] as String?) ?? '',
    layoutId: (m['layoutId'] as String?) ?? 'gala_luxo',
    fontStyleId: (m['fontStyleId'] as String?) ?? 'moderna',
    colorPrimaryArgb: (m['colorPrimaryArgb'] as int?) ?? 0xFF2563EB,
    colorTextArgb: (m['colorTextArgb'] as int?) ?? 0xFF1E1E1E,
    pastorManual: (m['pastorManual'] as String?) ?? '',
    cargoManual: (m['cargoManual'] as String?) ?? '',
    logoBytes: m['logoBytes'] is Uint8List ? m['logoBytes'] as Uint8List : null,
    fontMontserratBytes: m['fontMontserratBytes'] is Uint8List
        ? m['fontMontserratBytes'] as Uint8List
        : null,
    fontGreatVibesBytes: m['fontGreatVibesBytes'] is Uint8List
        ? m['fontGreatVibesBytes'] as Uint8List
        : null,
    fontUnifrakturBytes: m['fontUnifrakturBytes'] is Uint8List
        ? m['fontUnifrakturBytes'] as Uint8List
        : null,
    qrValidationUrl: (m['qrValidationUrl'] as String?) ?? '',
    backgroundTemplateBytes: m['backgroundTemplateBytes'] is Uint8List
        ? m['backgroundTemplateBytes'] as Uint8List
        : null,
    visualTemplateId: (m['visualTemplateId'] as String?) ?? 'classico_dourado',
    useLuxuryPdfFonts: m['useLuxuryPdfFonts'] is bool
        ? m['useLuxuryPdfFonts'] as bool
        : true,
    fontCinzelDecorativeBytes: m['fontCinzelDecorativeBytes'] is Uint8List
        ? m['fontCinzelDecorativeBytes'] as Uint8List
        : null,
    fontPinyonScriptBytes: m['fontPinyonScriptBytes'] is Uint8List
        ? m['fontPinyonScriptBytes'] as Uint8List
        : null,
    fontLibreBaskervilleBytes: m['fontLibreBaskervilleBytes'] is Uint8List
        ? m['fontLibreBaskervilleBytes'] as Uint8List
        : null,
    signatories: [
      for (final raw in sigRaw)
        if (raw is Map)
          CertSignatoryPdfData(
            nome: (raw['nome'] as String?) ?? '',
            cargo: (raw['cargo'] as String?) ?? '',
            signatureImageBytes: raw['signatureImageBytes'] is Uint8List
                ? raw['signatureImageBytes'] as Uint8List
                : null,
          ),
    ],
  );
}

/// Processamento pesado do PDF fora da thread da UI ([Isolate.run]).
Future<Uint8List> _gerarPdfIsolate(Map<String, dynamic> dados) async {
  final input = _certificatePdfInputFromMap(dados);
  return buildCertificatePdfBytes(input);
}

/// Gera bytes do certificado em isolate (mobile/desktop) ou na main (web).
Future<Uint8List> runGeraPdfCertificadoIsolate(Map<String, dynamic> dados) async {
  if (kIsWeb) {
    return _gerarPdfIsolate(dados);
  }
  return Isolate.run(() => _gerarPdfIsolate(dados));
}

Future<Uint8List> _gerarPdfGalaMultiIsolate(List<Map<String, dynamic>> maps) async {
  final inputs = <CertificatePdfInput>[
    for (final m in maps) _certificatePdfInputFromMap(m),
  ];
  return buildCertificateGalaLuxoMultiPdfBytes(inputs);
}

/// Várias páginas Gala Luxo num único PDF — [Isolate.run] fora da web.
Future<Uint8List> runGeraPdfCertificadoGalaMultiIsolate(
  List<Map<String, dynamic>> maps,
) async {
  if (maps.isEmpty) {
    throw ArgumentError('Lista de mapas de certificado vazia');
  }
  if (kIsWeb) {
    return _gerarPdfGalaMultiIsolate(maps);
  }
  return Isolate.run(() => _gerarPdfGalaMultiIsolate(maps));
}
