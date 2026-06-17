import 'dart:typed_data';

import 'package:gestao_yahweh/services/church_server_pdf_service.dart';
import 'package:http/http.dart' as http;

/// Resultado da geração de PDFs de carteirinha (Cloud Function + download).
class MemberCardPdfExportResult {
  const MemberCardPdfExportResult({
    required this.pdfsByMemberId,
    required this.ok,
    required this.fail,
  });

  final Map<String, Uint8List> pdfsByMemberId;
  final int ok;
  final int fail;
}

/// Exportação PDF em lote — `gerarCarteirinhaPdf` (servidor) com paralelismo limitado.
abstract final class MemberCardPdfExportService {
  MemberCardPdfExportService._();

  static const int _parallel = 3;

  static Future<MemberCardPdfExportResult> generatePdfs({
    required String tenantId,
    required List<String> memberIds,
    void Function(int done, int total, String memberId)? onProgress,
  }) async {
    final ids = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return const MemberCardPdfExportResult(
        pdfsByMemberId: {},
        ok: 0,
        fail: 0,
      );
    }

    final out = <String, Uint8List>{};
    var ok = 0;
    var fail = 0;
    var done = 0;
    final total = ids.length;

    for (var i = 0; i < ids.length; i += _parallel) {
      final end = (i + _parallel < ids.length) ? i + _parallel : ids.length;
      final chunk = ids.sublist(i, end);
      await Future.wait(
        chunk.map((memberId) async {
          try {
            final res = await ChurchServerPdfService.gerarCarteirinha(
              tenantId: tenantId,
              memberId: memberId,
            );
            final url = res.downloadUrl.trim();
            if (!res.ok || url.isEmpty) {
              fail++;
              return;
            }
            final bytes = await _downloadPdfBytes(url);
            if (bytes == null || bytes.isEmpty) {
              fail++;
              return;
            }
            out[memberId] = bytes;
            ok++;
          } catch (_) {
            fail++;
          } finally {
            done++;
            onProgress?.call(done, total, memberId);
          }
        }),
      );
    }

    return MemberCardPdfExportResult(
      pdfsByMemberId: out,
      ok: ok,
      fail: fail,
    );
  }

  static Future<Uint8List?> _downloadPdfBytes(String url) async {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    return res.bodyBytes;
  }
}
