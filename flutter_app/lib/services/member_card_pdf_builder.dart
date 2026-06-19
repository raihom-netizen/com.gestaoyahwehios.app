import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/carteirinha_consulta_url.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/member_card_load_service.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_a4_cut_guides.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pdf_fonts.dart';
import 'package:gestao_yahweh/ui/pdf/carteirinha_pvc_marks.dart';
import 'package:gestao_yahweh/ui/pdf/member_card_cnh_pdf_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_cnh_data.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;
import 'package:gestao_yahweh/utils/carteirinha_pdf_image_resize.dart';
import 'package:gestao_yahweh/utils/carteirinha_pdf_signature_enhance.dart';
import 'package:gestao_yahweh/utils/pdf_save_isolate.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Layout de impressão da carteirinha em lote.
enum MemberCardPdfLayout {
  /// Várias frentes/versos por folha A4 com linhas de recorte.
  a4GridCut,

  /// Tamanho real CNH digital — uma carteira por página com marcas de corte.
  realSize,
}

/// Dados resolvidos de um membro para montar frente + verso no PDF.
class MemberCardPdfSlice {
  const MemberCardPdfSlice({
    required this.memberId,
    required this.view,
    required this.member,
    this.photoBytes,
    this.signatureBytes,
  });

  final String memberId;
  final MemberCardCnhViewData view;
  final Map<String, dynamic> member;
  final Uint8List? photoBytes;
  final Uint8List? signatureBytes;
}

abstract final class MemberCardPdfBuilder {
  MemberCardPdfBuilder._();

  static const int _gridCols = 2;
  static const int _gridRows = 3;
  static const int _cardsPerA4 = _gridCols * _gridRows;

  static Future<Uint8List?> _photoBytesForMember(Map<String, dynamic> member) {
    final url = imageUrlFromMap(member);
    if (url.isEmpty) return Future<Uint8List?>.value(null);
    return ImageHelper.getBytesFromUrlOrNull(
      url,
      timeout: const Duration(seconds: 8),
    ).timeout(const Duration(seconds: 9), onTimeout: () => null);
  }

  static Future<Uint8List?> _signatureBytesForMember(
    Map<String, dynamic> member,
  ) async {
    final url =
        (member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    try {
      final raw = await ImageHelper.getBytesFromUrlOrNull(
        url,
        timeout: const Duration(seconds: 8),
      ).timeout(const Duration(seconds: 9), onTimeout: () => null);
      if (raw == null || raw.length < 33) return null;
      return kIsWeb
          ? carteirinhaPdfSignaturePipelineSync(raw)
          : await compute(carteirinhaPdfSignaturePipelineForCompute, raw);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _resizeForEmbed(Uint8List? raw, {int maxSide = 220}) {
    if (raw == null || raw.length < 33) return null;
    return carteirinhaPdfResizeBytesForEmbed({'b': raw, 'm': maxSide, 'q': 72});
  }

  static pw.ImageProvider? _img(Uint8List? b) {
    if (b == null || b.length < 33) return null;
    return pw.MemoryImage(b);
  }

  static bool _memberSigned(Map<String, dynamic> member) {
    if (member['carteirinhaAssinadaEm'] != null) return true;
    if ((member['carteirinhaAssinadaPorNome'] ?? '').toString().trim().isNotEmpty) {
      return true;
    }
    return (member['carteirinhaAssinaturaUrl'] ?? '').toString().trim().isNotEmpty;
  }

  /// Monta slices usando dados já carregados na lista (evita N leituras Firestore).
  static Future<List<MemberCardPdfSlice>> resolveSlices({
    required String churchId,
    required Map<String, dynamic> tenant,
    required List<String> memberIds,
    Map<String, Map<String, dynamic>> memberSeedById = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    final title = (tenant['nome'] ?? tenant['name'] ?? tenant['titulo'] ?? '')
        .toString()
        .trim();
    final subtitle = (tenant['cidade'] ?? tenant['city'] ?? '').toString();
    final ids = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return const [];

    final members = <String, Map<String, dynamic>>{};
    final missing = <String>[];
    for (final id in ids) {
      final seed = memberSeedById[id] ?? const <String, dynamic>{};
      if (seed.isNotEmpty) {
        members[id] = Map<String, dynamic>.from(seed);
      } else {
        missing.add(id);
      }
    }

    const memberLoadParallel = 6;
    for (var i = 0; i < missing.length; i += memberLoadParallel) {
      final chunk = missing.sublist(
        i,
        math.min(i + memberLoadParallel, missing.length),
      );
      final loaded = await Future.wait(
        chunk.map((id) async {
          try {
            final payload = await MemberCardLoadService.load(
              MemberCardLoadRequest(
                churchIdHint: churchId,
                memberId: id,
              ),
            ).timeout(const Duration(seconds: 12));
            return MapEntry(id, payload);
          } catch (_) {
            return MapEntry<String, MemberCardLoadPayload?>(id, null);
          }
        }),
      );
      for (final entry in loaded) {
        final payload = entry.value;
        if (payload == null) continue;
        members[entry.key] = Map<String, dynamic>.from(payload.member);
        tenant.putIfAbsent('id', () => payload.igrejaDocId);
      }
    }

    final total = ids.length;
    var progress = members.length.clamp(0, total);
    onProgress?.call(progress, total);

    final photoById = <String, Uint8List?>{};
    final sigById = <String, Uint8List?>{};

    final photoParallel = YahwehPerformanceV4.memberCardPdfPhotoParallel;
    for (var i = 0; i < ids.length; i += photoParallel) {
      final chunk = ids.sublist(i, math.min(i + photoParallel, ids.length));
      await Future.wait(
        chunk.map((id) async {
          final member = members[id];
          if (member == null) return;
          try {
            final photoRaw = await _photoBytesForMember(member);
            photoById[id] = _resizeForEmbed(photoRaw, maxSide: 240);
          } catch (_) {
            photoById[id] = null;
          }
          if (_memberSigned(member)) {
            try {
              final sigRaw = await _signatureBytesForMember(member);
              sigById[id] = _resizeForEmbed(sigRaw, maxSide: 180);
            } catch (_) {
              sigById[id] = null;
            }
          }
        }),
      );
      progress = math.min(total, progress + chunk.length);
      onProgress?.call(progress, total);
    }

    final out = <MemberCardPdfSlice>[];
    for (final id in ids) {
      final member = members[id];
      if (member == null || member.isEmpty) continue;
      try {
        final view = MemberCardCnhViewData.fromMaps(
          tenantId: churchId,
          memberId: id,
          member: member,
          tenant: tenant,
          churchTitle: title.isEmpty ? 'Igreja' : title,
          churchSubtitle: subtitle,
          qrPayload: CarteirinhaConsultaUrl.validationUrl(churchId, id),
        );
        out.add(
          MemberCardPdfSlice(
            memberId: id,
            view: view,
            member: member,
            photoBytes: photoById[id],
            signatureBytes: sigById[id],
          ),
        );
      } catch (e, st) {
        debugPrint('MemberCardPdfBuilder slice $id: $e\n$st');
      }
    }
    return out;
  }

  static pw.Widget _cnhCard(
    MemberCardPdfSlice s, {
    pw.ImageProvider? logo,
  }) {
    return MemberCardCnhPdfWidget(
      data: s.view,
      photoImage: _img(s.photoBytes),
      logoImage: logo,
      signatureImage: _img(s.signatureBytes),
    );
  }

  static pw.Widget _grid({
    required List<pw.Widget> cards,
    required int cols,
    required int rows,
  }) {
    final cw = MemberCardCnhPdfWidget.cardWidthPt;
    final ch = MemberCardCnhPdfWidget.cardHeightPt;
    final pageW = PdfPageFormat.a4.width - 28;
    final pageH = PdfPageFormat.a4.height - 28;
    final gapX = math.max(4.0, (pageW - cols * cw) / (cols + 1));
    final gapY = math.max(4.0, (pageH - rows * ch) / (rows + 1));

    final rowsWidgets = <pw.Widget>[];
    for (var r = 0; r < rows; r++) {
      final rowChildren = <pw.Widget>[];
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        rowChildren.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: c == 0 ? gapX : gapX / 2,
              right: c == cols - 1 ? gapX : gapX / 2,
              top: r == 0 ? gapY : gapY / 2,
              bottom: r == rows - 1 ? gapY : gapY / 2,
            ),
            child: idx < cards.length
                ? cards[idx]
                : pw.SizedBox(width: cw, height: ch),
          ),
        );
      }
      rowsWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowChildren,
        ),
      );
    }
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: rowsWidgets,
    );
  }

  static void _addGridPages({
    required pw.Document doc,
    required List<pw.Widget> cards,
    required String sectionTitle,
  }) {
    for (var i = 0; i < cards.length; i += _cardsPerA4) {
      final end = math.min(i + _cardsPerA4, cards.length);
      final chunk = cards.sublist(i, end);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(14),
          build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (i == 0)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  sectionTitle,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
            pw.Expanded(
              child: CarteirinhaA4CutGuides.overlayOnGrid(
                cols: _gridCols,
                rows: _gridRows,
                child: _grid(cards: chunk, cols: _gridCols, rows: _gridRows),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Folha ${(i ~/ _cardsPerA4) + 1} · recorte nas linhas pontilhadas',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
      );
    }
  }

  static Future<Uint8List> buildPdf({
    required String churchId,
    required Map<String, dynamic> tenant,
    required List<MemberCardPdfSlice> slices,
    required MemberCardPdfLayout layout,
    required ReportPdfBranding branding,
  }) async {
    if (slices.isEmpty) {
      throw StateError('Nenhum membro para gerar PDF.');
    }

    final theme = await CarteirinhaPdfFonts.loadThemeData();
    final doc = theme != null ? pw.Document(theme: theme) : pw.Document();
    final logoBytes = _resizeForEmbed(branding.logoBytes, maxSide: 120);
    final logo = _img(logoBytes);
    final accent = branding.accent;
    final churchName = branding.churchName.isNotEmpty
        ? branding.churchName
        : (tenant['nome'] ?? tenant['name'] ?? 'Igreja').toString();

    final emitted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.SizedBox(
                width: 56,
                height: 56,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Carteirinhas de Membro',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              churchName,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '${slices.length} membro(s) · '
              '${layout == MemberCardPdfLayout.a4GridCut ? 'A4 CNH digital (2×3)' : 'Tamanho real CNH digital'}',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.Text(
              'Emitido em $emitted',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.Spacer(),
            pw.Text(
              'Gestão YAHWEH — carteira membro padrão CNH digital com QR de validação.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ],
        ),
      ),
    );

    final cards = slices
        .map((s) => _cnhCard(s, logo: logo))
        .toList();

    switch (layout) {
      case MemberCardPdfLayout.a4GridCut:
        _addGridPages(
          doc: doc,
          cards: cards,
          sectionTitle: 'CNH DIGITAL — imprima e recorte',
        );
        break;
      case MemberCardPdfLayout.realSize:
        for (final card in cards) {
          doc.addPage(
            pw.Page(
              pageFormat: CarteirinhaPvcMarks.cnhPageFormat(),
              build: (ctx) => CarteirinhaPvcMarks.wrapCnhWithCropMarks(card),
            ),
          );
        }
        break;
    }

    return savePdfDocumentOffUiThread(doc).timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Montagem do PDF demorou demais. Tente menos membros ou conexão mais estável.',
      ),
    );
  }
}
