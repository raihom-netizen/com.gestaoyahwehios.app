import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show PdfPreview;

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Visualizador do comprovante **ainda não enviado** (bytes em memória).
///
/// O «olho» dos lançamentos já gravados abre por URL; o anexo recém-escolhido
/// não tinha como ser conferido antes de salvar — o gestor não sabia sequer se
/// o anexo tinha pegado. Mesmo comportamento do Controle Total.
Future<void> showPendingReceiptViewer(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  required bool isPdf,
}) async {
  if (bytes.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    fileName.isEmpty ? 'Comprovante' : fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SizedBox(
              width: double.infinity,
              child: isPdf
                  ? PdfPreview(
                      build: (PdfPageFormat _) => Future.value(bytes),
                      allowPrinting: false,
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      initialPageFormat: PdfPageFormat.a4,
                    )
                  : InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Cartão do anexo escolhido: miniatura + nome/tamanho + «olho» + remover.
class FinancePendingReceiptCard extends StatelessWidget {
  const FinancePendingReceiptCard({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.isPdf,
    this.onRemove,
  });

  final Uint8List bytes;
  final String fileName;
  final bool isPdf;
  final VoidCallback? onRemove;

  static String formatBytes(int n) {
    if (n < 1000) return '$n bytes';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cor = ThemeCleanPremium.primary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 54,
              height: 54,
              child: isPdf
                  ? Container(
                      color: cor.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: cor,
                        size: 28,
                      ),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName.isEmpty ? 'Comprovante' : fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Anexado · ${formatBytes(bytes.length)} · envia ao salvar',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Ver anexo',
            onPressed: () => showPendingReceiptViewer(
              context,
              bytes: bytes,
              fileName: fileName,
              isPdf: isPdf,
            ),
            icon: Icon(Icons.visibility_rounded, color: cor),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remover anexo',
              onPressed: onRemove,
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFFEF4444),
              ),
            ),
        ],
      ),
    );
  }
}
