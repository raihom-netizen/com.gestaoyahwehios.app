import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/member_card_pdf_builder.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Resultado da geração de um PDF único com várias carteirinhas (local, sem Cloud Function).
class MemberCardPdfExportResult {
  const MemberCardPdfExportResult({
    this.pdfBytes,
    required this.memberCount,
    required this.requestedCount,
    required this.failCount,
    required this.layout,
    this.errorMessage,
  });

  final Uint8List? pdfBytes;
  final int memberCount;
  final int requestedCount;
  final int failCount;
  final MemberCardPdfLayout layout;
  final String? errorMessage;

  bool get ok => pdfBytes != null && pdfBytes!.isNotEmpty && memberCount > 0;
}

/// Exportação PDF em lote — montagem local (CNH digital) num único arquivo.
abstract final class MemberCardPdfExportService {
  MemberCardPdfExportService._();

  static ReportPdfBranding _fallbackBranding(
    Map<String, dynamic> tenant,
  ) {
    final name =
        (tenant['name'] ?? tenant['nome'] ?? tenant['titulo'] ?? 'Igreja')
            .toString()
            .trim();
    return ReportPdfBranding(
      churchName: name.isEmpty ? 'Igreja' : name,
      logoBytes: null,
      accent: ReportPdfBranding.defaultAccent,
    );
  }

  static Future<MemberCardPdfExportResult> generateBatchPdf({
    required String churchId,
    required List<String> memberIds,
    required MemberCardPdfLayout layout,
    Map<String, Map<String, dynamic>> memberSeedById = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    final ids = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return MemberCardPdfExportResult(
        pdfBytes: null,
        memberCount: 0,
        requestedCount: 0,
        failCount: 0,
        layout: layout,
        errorMessage: 'Nenhum membro selecionado.',
      );
    }

    final resolvedId = ChurchRepository.churchId(churchId);
    if (resolvedId.isEmpty) {
      return MemberCardPdfExportResult(
        pdfBytes: null,
        memberCount: 0,
        requestedCount: ids.length,
        failCount: ids.length,
        layout: layout,
        errorMessage: 'Igreja não identificada (path igrejas/{churchId}).',
      );
    }

    Map<String, dynamic> tenant = {'id': resolvedId};
    try {
      final loaded = await ChurchRepository.loadChurchData(
        seedTenantId: resolvedId,
      ).timeout(const Duration(seconds: 10));
      if (loaded.data.isNotEmpty) {
        tenant = Map<String, dynamic>.from(loaded.data);
      }
    } catch (_) {}

    List<MemberCardPdfSlice> slices;
    try {
      slices = await MemberCardPdfBuilder.resolveSlices(
        churchId: resolvedId,
        tenant: tenant,
        memberIds: ids,
        memberSeedById: memberSeedById,
        onProgress: onProgress,
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException(
          'Tempo esgotado ao preparar os membros para o PDF.',
        ),
      );
    } catch (e, st) {
      debugPrint('MemberCardPdfExportService.resolveSlices: $e\n$st');
      return MemberCardPdfExportResult(
        pdfBytes: null,
        memberCount: 0,
        requestedCount: ids.length,
        failCount: ids.length,
        layout: layout,
        errorMessage: e.toString(),
      );
    }

    if (slices.isEmpty) {
      return MemberCardPdfExportResult(
        pdfBytes: null,
        memberCount: 0,
        requestedCount: ids.length,
        failCount: ids.length,
        layout: layout,
        errorMessage:
            'Nenhum membro carregado. Abra a lista de Membros e tente de novo.',
      );
    }

    ReportPdfBranding branding;
    try {
      branding = await loadReportPdfBranding(resolvedId).timeout(
        const Duration(seconds: 8),
        onTimeout: () => _fallbackBranding(tenant),
      );
    } catch (_) {
      branding = _fallbackBranding(tenant);
    }

    Uint8List? pdfBytes;
    String? buildError;
    try {
      pdfBytes = await MemberCardPdfBuilder.buildPdf(
        churchId: resolvedId,
        tenant: tenant,
        slices: slices,
        layout: layout,
        branding: branding,
      );
    } catch (e, st) {
      buildError = e.toString();
      debugPrint('MemberCardPdfExportService.buildPdf: $e\n$st');
    }

    if (pdfBytes == null || pdfBytes.isEmpty) {
      return MemberCardPdfExportResult(
        pdfBytes: null,
        memberCount: slices.length,
        requestedCount: ids.length,
        failCount: ids.length - slices.length,
        layout: layout,
        errorMessage: buildError ??
            'Falha ao montar o arquivo PDF (layout CNH digital).',
      );
    }

    return MemberCardPdfExportResult(
      pdfBytes: pdfBytes,
      memberCount: slices.length,
      requestedCount: ids.length,
      failCount: ids.length - slices.length,
      layout: layout,
    );
  }
}
