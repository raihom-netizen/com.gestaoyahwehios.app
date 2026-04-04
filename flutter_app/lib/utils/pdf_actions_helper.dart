import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Abre tela cheia com pré-visualização do PDF (pinch/zoom), impressão e compartilhamento.
/// Usado em carteirinha, relatórios, certificados e demais PDFs do sistema.
Future<void> showPdfActions(
  BuildContext context, {
  required Uint8List bytes,
  required String filename,
}) async {
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        appBar: AppBar(
          backgroundColor: ThemeCleanPremium.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Visualizar PDF'),
          leading: IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.close_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Use dois dedos para ampliar ou mover o documento. Imprimir e compartilhar ficam na barra inferior.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: PdfPreview.builder(
                build: (PdfPageFormat format) async => bytes,
                allowPrinting: true,
                allowSharing: true,
                canChangePageFormat: false,
                canChangeOrientation: false,
                pdfFileName: filename,
                useActions: true,
                pagesBuilder: (context, pages) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
                      return InteractiveViewer(
                        minScale: 0.35,
                        maxScale: 5.0,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(120),
                        child: SingleChildScrollView(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxW),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < pages.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 12),
                                    Material(
                                      color: Colors.white,
                                      elevation: 2,
                                      borderRadius: BorderRadius.circular(8),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image(
                                        image: pages[i].image,
                                        width: math.min(
                                          math.max(32, maxW - 24),
                                          pages[i].width.toDouble(),
                                        ),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
