import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: SafeArea(
          child: Column(
            children: [
              // Cabeçalho compacto: Voltar + título + Cancelar (sem duplicar Voltar).
              Container(
                color: ThemeCleanPremium.primary,
                padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: Colors.white,
                    ),
                    const Expanded(
                      child: Text(
                        'Visualizar PDF',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded,
                          size: 20, color: Colors.white),
                      label: const Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Dica fina de uma linha (não rouba espaço do PDF).
              Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Pinça/scroll para ampliar · arraste para mover',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // PDF ocupa TODO o espaço restante (tela cheia de verdade).
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 800.0;
                    return PdfPreview.builder(
                      build: (PdfPageFormat format) async => bytes,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      pdfFileName: filename,
                      useActions: false,
                      pagesBuilder: (context, pages) {
                        return LayoutBuilder(
                          builder: (context, inner) {
                            final innerW = inner.maxWidth.isFinite
                                ? inner.maxWidth
                                : maxW;
                            return InteractiveViewer(
                              minScale: 0.35,
                              maxScale: 5.0,
                              constrained: false,
                              boundaryMargin: const EdgeInsets.all(120),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: innerW),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var i = 0; i < pages.length; i++) ...[
                                          if (i > 0) const SizedBox(height: 12),
                                          Material(
                                            color: Colors.white,
                                            elevation: 2,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            clipBehavior: Clip.antiAlias,
                                            child: Image(
                                              image: pages[i].image,
                                              width: math.min(
                                                math.max(32, innerW - 24),
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
                    );
                  },
                ),
              ),
              // Barra inferior compacta: Imprimir + Baixar/Partilhar.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await Printing.layoutPdf(
                          onLayout: (_) async => bytes,
                          name: filename,
                        );
                      },
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Imprimir'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Printing.sharePdf(
                          bytes: bytes,
                          filename: filename,
                        );
                      },
                      icon: Icon(
                        kIsWeb
                            ? Icons.download_rounded
                            : Icons.share_rounded,
                      ),
                      label: Text(kIsWeb ? 'Baixar PDF' : 'Partilhar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
