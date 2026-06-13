import 'dart:typed_data';

import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/utils/cert_digital_signature_format.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Dados do signatário + igreja para selo digital compacto (padrão certificado).
class PdfDigitalSignatory {
  const PdfDigitalSignatory({
    required this.signerName,
    this.cpfDigits = '',
    this.role = '',
    this.churchName = '',
    this.churchDoc = '',
  });

  final String signerName;
  final String cpfDigits;
  final String role;
  final String churchName;
  final String churchDoc;

  factory PdfDigitalSignatory.fromEntry(
    ChurchSignatoryEntry entry, {
    required String churchName,
    String churchDoc = '',
  }) {
    return PdfDigitalSignatory(
      signerName: entry.nome.trim(),
      cpfDigits: (entry.cpfDigits ?? '').replaceAll(RegExp(r'\D'), ''),
      role: entry.cargo.trim(),
      churchName: churchName.trim(),
      churchDoc: churchDoc.replaceAll(RegExp(r'\D'), ''),
    );
  }

  factory PdfDigitalSignatory.fromMaps({
    required String signerName,
    String cpfRaw = '',
    String role = '',
    required String churchName,
    String churchDoc = '',
  }) {
    return PdfDigitalSignatory(
      signerName: signerName.trim(),
      cpfDigits: cpfRaw.replaceAll(RegExp(r'\D'), ''),
      role: role.trim(),
      churchName: churchName.trim(),
      churchDoc: churchDoc.replaceAll(RegExp(r'\D'), ''),
    );
  }
}

const String kPdfAssinadoDigitalPor = 'Assinado de forma digital por';

String _pdfDocDigitsOnly(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length <= 14) return d;
  return d.substring(d.length - 14);
}

String _pdfFormatCpfDisplay(String digits) {
  final d = _pdfDocDigitsOnly(digits);
  if (d.length != 11) return d;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

String pdfDigitalStampLeftLine(PdfDigitalSignatory s) {
  final name = s.signerName.trim();
  if (name.isEmpty) return '';
  final doc = _pdfDocDigitsOnly(s.cpfDigits);
  final upper = name.toUpperCase();
  if (doc.isEmpty) return upper;
  return '$upper:$doc';
}

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
      buf = w;
    }
  }
  if (buf.isNotEmpty) lines.add(buf);
  return lines.isEmpty ? [t] : lines;
}

List<String> pdfDigitalStampRightLines(PdfDigitalSignatory s) {
  final name = s.signerName.trim();
  final doc = _pdfDocDigitsOnly(s.cpfDigits);
  const max = 34;
  if (name.isEmpty) {
    return _wrapWords(kPdfAssinadoDigitalPor, max);
  }
  final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.length == 1) {
    final p0 = parts.first.toUpperCase();
    return <String>[
      ..._wrapWords('$kPdfAssinadoDigitalPor $p0', max),
      if (doc.isNotEmpty) '$p0:$doc' else p0,
    ];
  }
  final given =
      parts.sublist(0, parts.length - 1).map((e) => e.toUpperCase()).join(' ');
  final last = parts.last.toUpperCase();
  return <String>[
    ..._wrapWords('$kPdfAssinadoDigitalPor $given', max),
    if (doc.isNotEmpty) '$last:$doc' else last,
  ];
}

/// Selo compacto estilo certificado digital (duas colunas, ~30 pt de altura).
pw.Widget pdfDigitalCertificateStampBox({
  required PdfDigitalSignatory signatory,
  DateTime? signedAt,
  String? dadosLine,
  bool compact = true,
  double maxWidth = 228,
}) {
  final left = pdfDigitalStampLeftLine(signatory);
  final right = pdfDigitalStampRightLines(signatory);
  final dados = (dadosLine ?? '').trim().isNotEmpty
      ? dadosLine!.trim()
      : formatCertificadoDigitalDadosLinha(signedAt ?? DateTime.now());
  final leftSize = compact ? 6.4 : 7.2;
  final rightSize = compact ? 5.0 : 5.6;
  final dadosSize = compact ? 4.8 : 5.4;
  final church = signatory.churchName.trim();

  return pw.Container(
    width: maxWidth,
    padding: pw.EdgeInsets.symmetric(
      horizontal: compact ? 6 : 8,
      vertical: compact ? 4 : 5,
    ),
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFFFF7F7),
      border: pw.Border.all(
        color: const PdfColor.fromInt(0xFFE8B4B8),
        width: 0.65,
      ),
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              if (left.isNotEmpty)
                pw.Text(
                  pdfSafeText(left),
                  style: pw.TextStyle(
                    fontSize: leftSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                    lineSpacing: 1.05,
                    font: pw.Font.helvetica(),
                  ),
                  maxLines: 3,
                ),
              if (church.isNotEmpty) ...[
                pw.SizedBox(height: 1.5),
                pw.Text(
                  pdfSafeText(church.toUpperCase()),
                  style: pw.TextStyle(
                    fontSize: compact ? 4.6 : 5.2,
                    color: PdfColors.grey800,
                    lineSpacing: 1.05,
                    font: pw.Font.helvetica(),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: compact ? 4 : 6),
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              for (final line in right) ...[
                pw.Text(
                  pdfSafeText(line),
                  style: pw.TextStyle(
                    fontSize: rightSize,
                    color: PdfColors.black,
                    lineSpacing: 1.06,
                    font: pw.Font.helvetica(),
                  ),
                  maxLines: 2,
                ),
                pw.SizedBox(height: 0.4),
              ],
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

/// Coluna de assinatura ofício: selo digital acima da linha + nome + cargo.
pw.Widget pdfOfficialSignatureColumn({
  required PdfDigitalSignatory signatory,
  required PdfColor accent,
  DateTime? signedAt,
  String? dadosLine,
  Uint8List? rasterSignatureBytes,
  bool useDigitalCertificate = false,
  bool reserveManualSpace = false,
  bool compact = true,
  double maxWidth = 248,
}) {
  final lineW = maxWidth * 0.8;
  final frame = PdfColor(accent.red, accent.green, accent.blue, 0.72);
  final hasRaster = !useDigitalCertificate &&
      rasterSignatureBytes != null &&
      rasterSignatureBytes.length > 24;

  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      if (useDigitalCertificate) ...[
        pdfDigitalCertificateStampBox(
          signatory: signatory,
          signedAt: signedAt,
          dadosLine: dadosLine,
          compact: compact,
          maxWidth: maxWidth,
        ),
        pw.SizedBox(height: compact ? 4 : 5),
      ] else if (hasRaster) ...[
        pw.SizedBox(
          width: lineW,
          height: compact ? 22 : 26,
          child: pw.Image(
            pw.MemoryImage(rasterSignatureBytes),
            fit: pw.BoxFit.contain,
          ),
        ),
        pw.SizedBox(height: 4),
      ] else if (reserveManualSpace) ...[
        pw.Container(
          width: 120,
          height: 16,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: PdfColor.fromInt(0xFF94A3B8),
                width: 0.85,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
      ] else ...[
        pw.SizedBox(height: compact ? 14 : 18),
      ],
      pw.SizedBox(
        width: lineW,
        child: pw.Container(
          height: 1.05,
          decoration: pw.BoxDecoration(
            color: frame,
            borderRadius: pw.BorderRadius.circular(1),
          ),
        ),
      ),
      pw.SizedBox(height: compact ? 5 : 6),
      pw.Text(
        pdfSafeText(signatory.signerName),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: compact ? 8.6 : 10,
          fontWeight: pw.FontWeight.bold,
          color: accent,
          font: pw.Font.helvetica(),
        ),
        maxLines: 3,
      ),
      if (signatory.role.trim().isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          pdfSafeText(signatory.role.trim()),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: compact ? 7.4 : 8.2,
            color: PdfColors.grey800,
            font: pw.Font.helvetica(),
          ),
          maxLines: 2,
        ),
      ],
      if (signatory.churchName.trim().isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          pdfSafeText(signatory.churchName.trim().toUpperCase()),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: compact ? 6.8 : 7.6,
            color: PdfColors.grey700,
            font: pw.Font.helvetica(),
          ),
          maxLines: 3,
        ),
      ],
    ],
  );
}
