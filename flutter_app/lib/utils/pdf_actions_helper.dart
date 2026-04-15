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
          automaticallyImplyLeading: false,
          title: const Text('Visualizar PDF'),
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: Colors.white),
              label: const Text(
                'Voltar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(Icons.close_rounded,
                    size: 20, color: Colors.white.withValues(alpha: 0.95)),
                label: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Pinça ou Ctrl+scroll para reduzir ou ampliar. Arraste para mover. Imprimir e partilhar na barra inferior.',
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
