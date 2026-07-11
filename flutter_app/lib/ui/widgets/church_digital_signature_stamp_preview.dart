import 'package:flutter/material.dart';
import 'package:gestao_yahweh/utils/cert_digital_signature_format.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';

/// Pré-visualização Flutter do selo «Assinado de forma digital…» (padrão Cartas).
class ChurchDigitalSignatureStampPreview extends StatelessWidget {
  const ChurchDigitalSignatureStampPreview({
    super.key,
    required this.signerName,
    this.signerCpfDigits = '',
    required this.churchName,
    this.churchTaxIdDigits = '',
    this.churchData,
    this.cargo = '',
    this.dadosLine,
    this.maxWidth = 248,
    this.lineWidth = 220,
    this.lineColor,
    this.nameColor,
    this.compact = true,
  });

  final String signerName;
  final String signerCpfDigits;
  final String churchName;
  final String churchTaxIdDigits;
  final Map<String, dynamic>? churchData;
  final String cargo;
  final String? dadosLine;
  final double maxWidth;
  final double lineWidth;
  final Color? lineColor;
  final Color? nameColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tax = churchTaxIdDigits.trim().isNotEmpty
        ? churchTaxIdDigits.replaceAll(RegExp(r'\D'), '')
        : churchTaxIdDigitsFromMap(churchData);
    final stamp = PdfDigitalStampInput(
      signerName: signerName,
      signerCpfDigits: signerCpfDigits.replaceAll(RegExp(r'\D'), ''),
      churchName: churchName,
      churchTaxIdDigits: tax,
      dadosLine: dadosLine ?? formatCertificadoDigitalDadosLinha(DateTime.now()),
      compact: compact,
    );
    final left = digitalStampLeftColumnLines(stamp);
    final right = digitalStampRightColumnLines(stamp);
    final dados = (dadosLine ?? stamp.dadosLine).trim().isNotEmpty
        ? (dadosLine ?? stamp.dadosLine).trim()
        : formatCertificadoDigitalDadosLinha(DateTime.now());
    final frame = lineColor ?? const Color(0xFF5C3D1E);
    final nomeTint = nameColor ?? frame;
    final pad = compact ? 5.0 : 7.0;
    final leftSize = compact ? 6.2 : 7.0;
    final rightSize = compact ? 5.0 : 5.8;
    final dadosSize = compact ? 4.8 : 5.4;

    Widget col(List<String> lines, double size, FontWeight weight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 0.4),
              child: Text(
                line,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: weight,
                  height: 1.05,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: maxWidth,
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad - 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: col(left, leftSize, FontWeight.w700)),
                SizedBox(width: compact ? 6 : 8),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      col(right, rightSize, FontWeight.w400),
                      const SizedBox(height: 1),
                      Text(
                        dados,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dadosSize,
                          color: Colors.grey.shade800,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 5 : 7),
          Container(
            width: lineWidth,
            height: 1.2,
            decoration: BoxDecoration(
              color: frame.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          SizedBox(height: compact ? 5 : 7),
          Text(
            signerName.trim(),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 8.6 : 10.3,
              fontWeight: FontWeight.w700,
              color: nomeTint,
              height: 1.12,
            ),
          ),
          if (cargo.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              cargo.trim(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 6.8 : 7.8,
                fontWeight: FontWeight.w700,
                color: nomeTint.withValues(alpha: 0.88),
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
