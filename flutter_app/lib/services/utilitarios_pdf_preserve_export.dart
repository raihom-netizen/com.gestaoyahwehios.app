import 'dart:typed_data';

import 'package:gestao_yahweh/services/utilitarios_local_service.dart';

/// Edição nativa no PDF original — stub: devolve bytes originais até Syncfusion voltar.
class UtilitariosPdfPreserveExport {
  UtilitariosPdfPreserveExport._();

  static Future<Uint8List> export({
    required Uint8List originalPdf,
    required List<List<UtilPdfPageAnnotation>> annotationsByPage,
  }) async {
    final hasAny = annotationsByPage.any((p) => p.isNotEmpty);
    if (!hasAny) return originalPdf;
    // Fallback seguro: preserva PDF sem rasterizar quando motor nativo indisponível.
    return originalPdf;
  }
}
