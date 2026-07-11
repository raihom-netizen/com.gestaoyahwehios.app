import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/cert_digital_signature_format.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';

/// Dados para o selo compacto «certificado digital» (estilo Adobe Reader).
class PdfDigitalStampInput {
  const PdfDigitalStampInput({
    required this.signerName,
    this.signerCpfDigits = '',
    this.churchName = '',
    this.churchTaxIdDigits = '',
    this.dadosLine = '',
    this.compact = true,
  });

  final String signerName;
  final String signerCpfDigits;
  final String churchName;
  final String churchTaxIdDigits;
  final String dadosLine;
  final bool compact;

  factory PdfDigitalStampInput.now({
    required String signerName,
    String? signerCpfDigits,
    String? churchName,
    Map<String, dynamic>? churchData,
    DateTime? when,
    bool compact = true,
  }) {
    final tax = churchTaxIdDigitsFromMap(churchData);
    return PdfDigitalStampInput(
      signerName: signerName,
      signerCpfDigits: _digitsOnly(signerCpfDigits ?? ''),
      churchName: (churchName ?? churchTaxIdChurchNameFromMap(churchData)).trim(),
      churchTaxIdDigits: tax,
      dadosLine: formatCertificadoDigitalDadosLinha(when ?? DateTime.now()),
      compact: compact,
    );
  }
}

String churchTaxIdChurchNameFromMap(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return '';
  for (final k in ['name', 'nome', 'razaoSocial', 'nomeIgreja']) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

String churchTaxIdDigitsFromMap(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return '';
  for (final k in [
    'cnpj',
    'CNPJ',
    'cnpjCpf',
    'cpfCnpj',
    'documento',
    'cnpj_igreja',
    'inscricao',
  ]) {
    final d = _digitsOnly((data[k] ?? '').toString());
    if (d.length >= 11) return d;
  }
  return '';
}

String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

const String _kSignedByPrefix = 'Assinado de forma digital por';
const int _kWrapMax = 34;

List<String> _wrapWords(String text, int maxChars) {
  final t = text.trim();
  if (t.isEmpty) return [];
  if (t.length <= maxChars) return [t];
  final words = t.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  final lines = <String>[];
  var buf = '';
  for (final w in words) {
    if (buf.isEmpty) {
      buf = w;
    } else if ('$buf $w'.length <= maxChars) {
      buf = '$buf $w';
    } else {
      lines.add(buf);
      buf = w.length <= maxChars ? w : w.substring(0, maxChars);
    }
  }
  if (buf.isNotEmpty) lines.add(buf);
  return lines.isEmpty ? [t] : lines;
}

List<String> _rightColumnLines(PdfDigitalStampInput input) {
  final nome = input.signerName.trim();
  final cpf = _digitsOnly(input.signerCpfDigits);
  final parts =
      nome.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) {
    return [
      ..._wrapWords(_kSignedByPrefix, _kWrapMax),
      if (cpf.isNotEmpty) 'CPF:$cpf',
    ];
  }
  if (parts.length == 1) {
    final p0 = parts.first.toUpperCase();
    return [
      ..._wrapWords('$_kSignedByPrefix $p0', _kWrapMax),
      if (cpf.isNotEmpty) '$p0:$cpf',
    ];
  }
  final given =
      parts.sublist(0, parts.length - 1).map((e) => e.toUpperCase()).join(' ');
  final last = parts.last.toUpperCase();
  return [
    ..._wrapWords('$_kSignedByPrefix $given', _kWrapMax),
    cpf.isNotEmpty ? '$last:$cpf' : last,
  ];
}

List<String> _leftColumnLines(PdfDigitalStampInput input) {
  final church = input.churchName.trim();
  final tax = _digitsOnly(input.churchTaxIdDigits);
  if (church.isNotEmpty) {
    final wrapped = _wrapWords(church.toUpperCase(), _kWrapMax);
    if (tax.isEmpty) return wrapped;
    if (wrapped.isEmpty) return ['$tax'];
    final last = wrapped.removeLast();
    return [...wrapped, '$last:$tax'];
  }
  final nome = input.signerName.trim().toUpperCase();
  final cpf = _digitsOnly(input.signerCpfDigits);
  if (nome.isEmpty) return const [];
  if (cpf.isNotEmpty) return ['$nome:$cpf'];
  return _wrapWords(nome, _kWrapMax);
}

List<String> digitalStampLeftColumnLines(PdfDigitalStampInput input) =>
    _leftColumnLines(input);

List<String> digitalStampRightColumnLines(PdfDigitalStampInput input) =>
    _rightColumnLines(input);

/// Selo horizontal compacto — acima da linha de assinatura (não usa imagem raster).
pw.Widget pdfDigitalCertificateStampBlock(
  PdfDigitalStampInput input, {
  double maxWidth = 248,
}) {
  final left = _leftColumnLines(input);
  final right = _rightColumnLines(input);
  final dados = input.dadosLine.trim().isNotEmpty
      ? input.dadosLine.trim()
      : formatCertificadoDigitalDadosLinha(DateTime.now());
  final leftSize = input.compact ? 6.4 : 7.2;
  final rightSize = input.compact ? 5.2 : 5.9;
  final dadosSize = input.compact ? 5.0 : 5.6;
  final pad = input.compact ? 5.0 : 7.0;

  pw.Widget col(List<String> lines, double size, pw.FontWeight weight) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (final line in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 0.4),
            child: pw.Text(
              pdfSafeText(line),
              style: pw.TextStyle(
                fontSize: size,
                fontWeight: weight,
                lineSpacing: 1.05,
                color: PdfColors.black,
                font: pw.Font.helvetica(),
              ),
              maxLines: 3,
            ),
          ),
      ],
    );
  }

  return pw.Container(
    width: maxWidth,
    padding: pw.EdgeInsets.symmetric(horizontal: pad, vertical: pad - 1),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF8FAFC),
      borderRadius: pw.BorderRadius.circular(4),
      border: pw.Border.all(
        color: PdfColor.fromInt(0xFFE2E8F0),
        width: 0.65,
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 5,
          child: col(left, leftSize, pw.FontWeight.bold),
        ),
        pw.SizedBox(width: input.compact ? 6 : 8),
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              col(right, rightSize, pw.FontWeight.normal),
              pw.SizedBox(height: 1),
              pw.Text(
                pdfSafeText(dados),
                style: pw.TextStyle(
                  fontSize: dadosSize,
                  color: PdfColors.grey800,
                  font: pw.Font.helvetica(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Variante centrada (cartas / coluna única de assinatura).
List<pw.Widget> pdfDigitalCertificateStampAboveLineWidgets(
  PdfDigitalStampInput input, {
  double maxWidth = 248,
}) {
  return [
    pw.Center(
      child: pdfDigitalCertificateStampBlock(input, maxWidth: maxWidth),
    ),
    pw.SizedBox(height: input.compact ? 5 : 7),
  ];
}
