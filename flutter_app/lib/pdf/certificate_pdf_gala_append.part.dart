part of 'certificate_pdf_builder.dart';

/// Uma página Gala Luxo (vetores no PDF: gradientes e [Border] — escalam na impressão laser).
void _appendGalaLuxoCertificatePage(
  pw.Document doc,
  CertificatePdfInput input,
) {
  final nomeMembroLinha2Efetiva =
      _nomeCasamentoLinha2EfetivaParaDestaque(input);

  final textHex = _hexRgb(input.colorTextArgb);
  final pdfTextCor = PdfColor.fromHex(textHex);

  pw.ImageProvider? logoImage;
  if (input.logoBytes != null && input.logoBytes!.length > 32) {
    logoImage = pw.MemoryImage(input.logoBytes!);
  }

  final signatoryImageProviders = <pw.ImageProvider?>[
    for (final s in input.signatories)
      (s.signatureImageBytes != null && s.signatureImageBytes!.length > 32)
          ? pw.MemoryImage(s.signatureImageBytes!)
          : null,
  ];

  const signatoryBlockWidth = 140.0;

  pw.Widget buildSignatoryBlock(int i, PdfColor accent, PdfColor accentClaro) {
    if (i >= input.signatories.length) return pw.SizedBox();
    final s = input.signatories[i];
    final img = i < signatoryImageProviders.length
        ? signatoryImageProviders[i]
        : null;
    return pw.Container(
      width: signatoryBlockWidth,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (img != null)
            pw.Container(
              width: 118,
              height: 46,
              margin: const pw.EdgeInsets.only(bottom: 6),
              alignment: pw.Alignment.center,
              child: pw.Image(img, fit: pw.BoxFit.contain),
            ),
          if (img != null) pw.SizedBox(height: 4),
          pw.Container(width: 120, height: 1, color: accent),
          pw.SizedBox(height: 8),
          pw.Text(
            s.nome,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            s.cargo,
            style: pw.TextStyle(
              fontSize: 10,
              color: accentClaro,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  pw.Widget buildFooterSignatures(PdfColor accent, PdfColor accentClaro) {
    if (input.signatories.isNotEmpty) {
      final count = input.signatories.length;
      final blocks = List<pw.Widget>.generate(
          count, (i) => buildSignatoryBlock(i, accent, accentClaro));
      if (count == 1) {
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [blocks[0]],
        );
      }
      // [Wrap] podia empilhar blocos fora da área visível em alguns motores; fileira explícita.
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: blocks,
      );
    }
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 140, height: 1, color: accent),
        pw.SizedBox(height: 8),
        pw.Text(
          input.pastorManual,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: accent,
          ),
        ),
        pw.Text(
          input.cargoManual,
          style: pw.TextStyle(fontSize: 10, color: accentClaro),
        ),
      ],
    );
  }

  final isClassica = input.fontStyleId == 'classica';
  final isGotica = input.fontStyleId == 'gotica';

  pw.Font? montserrat;
  pw.Font? greatVibes;
  if (input.fontMontserratBytes != null &&
      input.fontMontserratBytes!.isNotEmpty) {
    montserrat = pw.Font.ttf(
      ByteData.view(input.fontMontserratBytes!.buffer),
    );
  }
  if (input.fontGreatVibesBytes != null &&
      input.fontGreatVibesBytes!.isNotEmpty) {
    try {
      greatVibes = pw.Font.ttf(
        ByteData.view(input.fontGreatVibesBytes!.buffer),
      );
    } catch (_) {}
  }

  pw.Font? fontForTitle() {
    if (isGotica) return montserrat ?? pw.Font.timesBold();
    if (isClassica) return pw.Font.timesBold();
    return montserrat;
  }

  pw.Font? fontForName() {
    if (isClassica) return greatVibes ?? pw.Font.timesItalic();
    if (isGotica) return greatVibes ?? montserrat ?? pw.Font.timesBold();
    return montserrat;
  }

  pw.Font? fontForBody() {
    if (isClassica) return pw.Font.times();
    if (isGotica) return montserrat ?? pw.Font.times();
    return montserrat ?? pw.Font.times();
  }

  pw.Font? fontForBodyBold() {
    if (isClassica) return pw.Font.timesBold();
    if (isGotica) return montserrat ?? pw.Font.timesBold();
    return montserrat;
  }

  double nameSize(double base) =>
      isClassica ? base + 6 : (isGotica ? base + 4 : base);

  String issueLine() {
    final local = input.local.trim();
    final date = input.issuedDate.trim();
    if (local.isNotEmpty && date.isNotEmpty) return '$local, $date';
    if (local.isNotEmpty) return local;
    return date;
  }

  final qrUrl = input.qrValidationUrl.trim();
  final galaBronze = PdfColor.fromHex('5C3D1E');
  final galaBronzeLight = PdfColor.fromHex('8B6914');
  final galaGold = PdfColor.fromHex('C9A227');
  final galaGoldDark = PdfColor.fromHex('8B6914');
  pw.Font? cinzelLux;
  pw.Font? pinyonLux;
  pw.Font? libreLux;
  if (input.fontCinzelDecorativeBytes != null &&
      input.fontCinzelDecorativeBytes!.length > 64) {
    try {
      cinzelLux = pw.Font.ttf(
        ByteData.view(input.fontCinzelDecorativeBytes!.buffer),
      );
    } catch (_) {}
  }
  if (input.fontPinyonScriptBytes != null &&
      input.fontPinyonScriptBytes!.length > 64) {
    try {
      pinyonLux = pw.Font.ttf(
        ByteData.view(input.fontPinyonScriptBytes!.buffer),
      );
    } catch (_) {}
  }
  if (input.fontLibreBaskervilleBytes != null &&
      input.fontLibreBaskervilleBytes!.length > 64) {
    try {
      libreLux = pw.Font.ttf(
        ByteData.view(input.fontLibreBaskervilleBytes!.buffer),
      );
    } catch (_) {}
  }
  final useLuxFonts = input.useLuxuryPdfFonts;
  final galaTitleFont = (useLuxFonts && cinzelLux != null)
      ? cinzelLux
      : (fontForTitle() ?? pw.Font.timesBold());
  final galaBody = (useLuxFonts && libreLux != null)
      ? libreLux
      : (fontForBody() ?? pw.Font.times());
  /// Libre Baskerville **Variable** num único TTF: [FontWeight.bold] não gera negrito real no `pdf`.
  /// Times Bold para os nomes/CPF no corpo — serif legível e contraste garantido.
  final galaBodyBold = (useLuxFonts && libreLux != null)
      ? pw.Font.timesBold()
      : (fontForBodyBold() ?? pw.Font.timesBold());
  final galaNameFont = (useLuxFonts && pinyonLux != null)
      ? pinyonLux
      : (fontForName() ?? pw.Font.timesItalic());
  const wGalaTitle = pw.FontWeight.bold;
  const wGalaName = pw.FontWeight.normal;

  /// Nome em manuscrito: destaque ultra premium (mínimo 26 pt).
  final galaNomeFontPts = math.max(26.0, nameSize(38).toDouble());

  /// Fundos claros: sombra suave em texto escuro para leitura (vetor no PDF).
  final useLightBgShadow = input.visualTemplateId.trim() != 'void';

  pw.Widget galaShadowedText({
    required String text,
    required pw.TextStyle style,
    required pw.TextAlign align,
    int maxLines = 1,
  }) {
    if (text.trim().isEmpty) {
      return pw.SizedBox();
    }
    if (!useLuxFonts || !useLightBgShadow) {
      return pw.Text(
        text,
        style: style,
        textAlign: align,
        maxLines: maxLines,
      );
    }
    return pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.Transform.translate(
          offset: const PdfPoint(0.65, 0.65),
          child: pw.Text(
            text,
            style: style.copyWith(color: PdfColors.white),
            textAlign: align,
            maxLines: maxLines,
          ),
        ),
        pw.Text(
          text,
          style: style,
          textAlign: align,
          maxLines: maxLines,
        ),
      ],
    );
  }

  pw.Widget cornerOrnament() {
    return pw.Stack(
      children: [
        pw.Positioned(
          left: 10,
          top: 10,
          child: pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: galaGoldDark, width: 2.4),
                top: pw.BorderSide(color: galaGoldDark, width: 2.4),
              ),
            ),
          ),
        ),
        pw.Positioned(
          right: 10,
          top: 10,
          child: pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(color: galaGoldDark, width: 2.4),
                top: pw.BorderSide(color: galaGoldDark, width: 2.4),
              ),
            ),
          ),
        ),
        pw.Positioned(
          left: 10,
          bottom: 10,
          child: pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: galaGoldDark, width: 2.4),
                bottom: pw.BorderSide(color: galaGoldDark, width: 2.4),
              ),
            ),
          ),
        ),
        pw.Positioned(
          right: 10,
          bottom: 10,
          child: pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(color: galaGoldDark, width: 2.4),
                bottom: pw.BorderSide(color: galaGoldDark, width: 2.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget authenticitySeal() {
    return pw.Container(
      width: 92,
      height: 92,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: PdfColors.white,
        border: pw.Border.all(color: galaGold, width: 2.8),
      ),
      child: pw.Stack(
        alignment: pw.Alignment.center,
        children: [
          pw.Positioned(
            top: 6,
            child: pw.Text(
              'AUTENTICIDADE',
              style: pw.TextStyle(
                fontSize: 5.2,
                fontWeight: pw.FontWeight.bold,
                color: galaBronze,
                letterSpacing: 0.6,
                font: galaBody,
              ),
            ),
          ),
          if (qrUrl.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrUrl,
                color: PdfColors.black,
                width: 64,
                height: 64,
              ),
            )
          else
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                '✦',
                style: pw.TextStyle(
                  fontSize: 28,
                  color: galaGoldDark,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget galaIssueFooter() {
    final line = issueLine();
    if (line.isEmpty) return pw.SizedBox();
    return pw.SizedBox(
      width: 128,
      child: pw.Text(
        line,
        style: pw.TextStyle(
          fontSize: 9.2,
          color: galaBronzeLight,
          font: galaBody,
          lineSpacing: 1.1,
        ),
        textAlign: pw.TextAlign.left,
      ),
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.zero,
      build: (ctx) {
        return pw.Container(
          width: double.infinity,
          height: double.infinity,
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [
                PdfColor.fromHex('6B4E16'),
                PdfColor.fromHex('C9A227'),
                PdfColor.fromHex('E8D060'),
                PdfColor.fromHex('8B6914'),
              ],
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
            ),
          ),
          padding: const pw.EdgeInsets.all(7),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: galaGoldDark, width: 2.0),
            ),
            padding: const pw.EdgeInsets.all(5),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: galaGold, width: 1.6),
              ),
              child: pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: _galaLuxoBackgroundFill(
                      backgroundBytes: input.backgroundTemplateBytes,
                      visualTemplateId: input.visualTemplateId,
                    ),
                  ),
                  if (input.visualTemplateId.trim() == 'moderno_geometrico' &&
                      (input.backgroundTemplateBytes == null ||
                          input.backgroundTemplateBytes!.length <= 64))
                    pw.Positioned.fill(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.all(18),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColor.fromHex('64748B'),
                            width: 1.1,
                          ),
                        ),
                      ),
                    ),
                  pw.Positioned.fill(child: cornerOrnament()),
                  if (logoImage != null)
                    pw.Center(
                      child: pw.Opacity(
                        opacity: 0.082,
                        child: pw.Container(
                          width: 340,
                          height: 340,
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      ),
                    ),
                  pw.Positioned.fill(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(36, 18, 36, 112),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.SizedBox(height: 14),
                          if (input.nomeIgreja.trim().isNotEmpty) ...[
                            pw.Text(
                              input.nomeIgreja.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 11.5,
                                fontWeight: pw.FontWeight.bold,
                                color: galaBronze,
                                letterSpacing: 0.5,
                                font: galaBody,
                                lineSpacing: 1.05,
                              ),
                              textAlign: pw.TextAlign.center,
                              maxLines: 2,
                            ),
                            pw.SizedBox(height: 10),
                          ],
                          galaShadowedText(
                            text: input.titulo.toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: wGalaTitle,
                              color: pdfTextCor,
                              letterSpacing: 1.1,
                              font: galaTitleFont,
                            ),
                            align: pw.TextAlign.center,
                          ),
                          if (input.subtitulo.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 8),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 48),
                              child: pw.Text(
                                input.subtitulo.trim(),
                                style: pw.TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: pw.FontStyle.italic,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pdfTextCor,
                                  font: galaBodyBold,
                                ),
                                textAlign: pw.TextAlign.center,
                                maxLines: 3,
                              ),
                            ),
                          ],
                          pw.SizedBox(height: 10),
                          pw.SizedBox(
                            height: nomeMembroLinha2Efetiva.isEmpty
                                ? 68.0
                                : 86.0,
                            width: double.infinity,
                            child: pw.Center(
                              child: pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 40),
                                child: nomeMembroLinha2Efetiva.isEmpty
                                    ? galaShadowedText(
                                        text: input.nomeMembro,
                                        style: pw.TextStyle(
                                          fontSize: galaNomeFontPts,
                                          fontWeight: wGalaName,
                                          color: galaBronze,
                                          letterSpacing: 0.35,
                                          font: galaNameFont,
                                        ),
                                        align: pw.TextAlign.center,
                                        maxLines: 2,
                                      )
                                    : pw.Column(
                                        mainAxisSize: pw.MainAxisSize.min,
                                        children: [
                                          galaShadowedText(
                                            text: input.nomeMembro,
                                            style: pw.TextStyle(
                                              fontSize: galaNomeFontPts,
                                              fontWeight: wGalaName,
                                              color: galaBronze,
                                              letterSpacing: 0.35,
                                              font: galaNameFont,
                                            ),
                                            align: pw.TextAlign.center,
                                            maxLines: 2,
                                          ),
                                          pw.SizedBox(height: 3),
                                          galaShadowedText(
                                            text: nomeMembroLinha2Efetiva,
                                            style: pw.TextStyle(
                                              fontSize: galaNomeFontPts * 0.96,
                                              fontWeight: wGalaName,
                                              color: galaBronze,
                                              letterSpacing: 0.35,
                                              font: galaNameFont,
                                            ),
                                            align: pw.TextAlign.center,
                                            maxLines: 2,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          pw.SizedBox(
                            height: 200,
                            width: double.infinity,
                            child: pw.Center(
                              child: pw.Container(
                                constraints:
                                    const pw.BoxConstraints(maxWidth: 560),
                                child: _certificateBodyRich(
                                  texto: input.texto,
                                  nome: input.nomeMembro,
                                  nomeLinha2: nomeMembroLinha2Efetiva,
                                  cpfFormatado: input.cpfFormatado,
                                  fontSize: 11.2,
                                  color: pdfTextCor,
                                  font: galaBody,
                                  fontBold: galaBodyBold,
                                  useSyntheticBoldForHighlights: true,
                                ),
                              ),
                            ),
                          ),
                          pw.Spacer(),
                          pw.Center(
                            child: buildFooterSignatures(
                                galaBronze, galaBronzeLight),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Positioned(
                    left: 28,
                    bottom: 18,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        authenticitySeal(),
                        pw.SizedBox(height: 8),
                        galaIssueFooter(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Vários certificados Gala Luxo em **um único PDF** (uma página por membro).
Future<Uint8List> buildCertificateGalaLuxoMultiPdfBytes(
  List<CertificatePdfInput> inputs,
) async {
  if (inputs.isEmpty) {
    throw ArgumentError('Lista de certificados vazia');
  }
  final doc = pw.Document();
  for (final input in inputs) {
    if (input.layoutId != 'gala_luxo') {
      throw UnsupportedError(
        'PDF único em lote suporta apenas layout gala_luxo',
      );
    }
    _appendGalaLuxoCertificatePage(doc, input);
  }
  return Uint8List.fromList(await doc.save());
}
