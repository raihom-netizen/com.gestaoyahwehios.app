import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

part 'certificate_pdf_gala_append.part.dart';

String _normCasamentoNomeChave(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

bool _casamentoNomeCorresponde(String candidato, String primeiroNorm) {
  final c = _normCasamentoNomeChave(candidato);
  if (c.isEmpty || primeiroNorm.isEmpty) return false;
  if (c == primeiroNorm) return true;
  // Um nome pode vir abreviado no dropdown em relação ao corpo (ou vice-versa).
  if (c.startsWith(primeiroNorm) &&
      (c.length == primeiroNorm.length || c[primeiroNorm.length] == ' ')) {
    return true;
  }
  if (primeiroNorm.startsWith(c) &&
      (primeiroNorm.length == c.length || primeiroNorm[c.length] == ' ')) {
    return true;
  }
  return false;
}

/// Quantas palavras “fortes” de [refNorm] aparecem em [candidatoNorm] (ajuda quando
/// [\_casamentoNomeCorresponde] falha por grafia/sobrenome diferente).
int _casamentoOverlapWordCount(String refNorm, String candidatoNorm) {
  final refWords =
      refNorm.split(' ').where((w) => w.length > 2).toSet();
  if (refWords.isEmpty) return 0;
  return candidatoNorm
      .split(' ')
      .where((w) => w.length > 2 && refWords.contains(w))
      .length;
}

/// Dado o par «A e B» extraído do corpo, devolve o cônjuge que não é [primeiroNome].
String _segundoConjugeDoParCasamento(String a, String b, String primeiroNome) {
  final p = primeiroNome.trim();
  if (p.isEmpty) return '';
  final pn = _normCasamentoNomeChave(p);
  if (pn.length < 3) return '';
  final an = _normCasamentoNomeChave(a);
  final bn = _normCasamentoNomeChave(b);
  final sa = _casamentoOverlapWordCount(pn, an);
  final sb = _casamentoOverlapWordCount(pn, bn);
  if (sa > sb + 1) return b.trim();
  if (sb > sa + 1) return a.trim();
  if (sa > sb) return b.trim();
  if (sb > sa) return a.trim();
  if (_casamentoNomeCorresponde(a, pn)) return b.trim();
  if (_casamentoNomeCorresponde(b, pn)) return a.trim();
  // Modelo típico: primeiro nome no cadastro = noivo (primeiro no texto).
  return b.trim();
}

/// Remove `**` e normaliza espaços — o texto do editor pode incluir markdown e
/// quebrar o reconhecimento de «certificamos que A e B contraiu…».
String _stripMarkdownParaRegexCertificado(String s) {
  return s.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Quando o segundo nome não chega ao pipeline, extrai do corpo já resolvido:
/// "Certificamos que A e B contraiu/contrataram/…", inclusive se A e B estiverem
/// em ordem invertida em relação a [primeiroNome].
String segundoNomeCasamentoFallbackDoCorpo(String corpo, String primeiroNome) {
  final p = primeiroNome.trim();
  if (p.isEmpty) return '';
  final flat = _stripMarkdownParaRegexCertificado(corpo);
  final pn = _normCasamentoNomeChave(p);

  // Separador antes do verbo: espaço ou vírgula («… Barbosa, contrataram»).
  const verbAlt = r'(?:contraiu|contraíram|contrataram|contratou|celebraram|'
      r'uniram-se|uniram|casaram-se|casaram|contraíram-se|contraiu-se|contraíram-se)\b';
  // Frase fixa "certificamos … que" e variante com texto entre vírgulas antes de "que".
  final pairPatterns = <RegExp>[
    RegExp(
      r'certificamos,?\s+que\s+(.+?)\s+e\s+(.+?)[\s,]+' + verbAlt,
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos[^.!?]{0,220}?que\s+(.+?)\s+e\s+(.+?)[\s,]+' + verbAlt,
      caseSensitive: false,
    ),
  ];
  for (final pairVerb in pairPatterns) {
    for (final m in pairVerb.allMatches(flat)) {
      final a = (m.group(1) ?? '').trim();
      final b = (m.group(2) ?? '').trim();
      if (a.isEmpty || b.isEmpty) continue;
      if (_casamentoNomeCorresponde(a, pn)) return b;
      if (_casamentoNomeCorresponde(b, pn)) return a;
      final guess = _segundoConjugeDoParCasamento(a, b, p);
      if (guess.isNotEmpty) return guess;
    }
  }

  final esc = RegExp.escape(p);
  final patterns = <RegExp>[
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+contraiu\b',
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+contraíram\b',
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+contrataram\b',
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+contratou\b',
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+celebraram\b',
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos,?\s+que\s+' + esc + r'\s+e\s+(.+?)[\s,]+contra\b',
      caseSensitive: false,
    ),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(flat);
    if (m != null) {
      final s = m.group(1)?.trim() ?? '';
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

/// Trechos exatos do parágrafo (após «que») para negrito no PDF — alinha com o texto emitido,
/// mesmo quando o cadastro difere ligeiramente (ex.: sobrenome no corpo e não na ficha).
List<String>? _casamentoHighlightPairFromCorpo(
  String texto,
  String n1,
  String n2,
) {
  final flat = _stripMarkdownParaRegexCertificado(texto);
  final pn1 = _normCasamentoNomeChave(n1);
  final pn2 = _normCasamentoNomeChave(n2);
  if (pn1.isEmpty || pn2.isEmpty) return null;
  const verbAltHighlight = r'(?:contraiu|contraíram|contrataram|contratou|celebraram|'
      r'uniram-se|uniram|casaram-se|casaram|contraíram-se|contraiu-se|contraíram-se)\b';
  final pairPatterns = <RegExp>[
    RegExp(
      r'certificamos,?\s+que\s+(.+?)\s+e\s+(.+?)[\s,]+' + verbAltHighlight,
      caseSensitive: false,
    ),
    RegExp(
      r'certificamos[^.!?]{0,220}?que\s+(.+?)\s+e\s+(.+?)[\s,]+' + verbAltHighlight,
      caseSensitive: false,
    ),
  ];
  for (final re in pairPatterns) {
    final m = re.firstMatch(flat);
    if (m == null) continue;
    final a = (m.group(1) ?? '').trim();
    final b = (m.group(2) ?? '').trim();
    if (a.isEmpty || b.isEmpty) continue;
    final a1 = _casamentoNomeCorresponde(a, pn1);
    final a2 = _casamentoNomeCorresponde(a, pn2);
    final b1 = _casamentoNomeCorresponde(b, pn1);
    final b2 = _casamentoNomeCorresponde(b, pn2);
    if (a1 && b2 && !a2 && !b1) return [a, b];
    if (b1 && a2 && !b2 && !a1) return [b, a];
    if (a1 && b2) return [a, b];
    if (b1 && a2) return [b, a];
    final scoreA1 = _casamentoOverlapWordCount(pn1, _normCasamentoNomeChave(a));
    final scoreA2 = _casamentoOverlapWordCount(pn2, _normCasamentoNomeChave(a));
    final scoreB1 = _casamentoOverlapWordCount(pn1, _normCasamentoNomeChave(b));
    final scoreB2 = _casamentoOverlapWordCount(pn2, _normCasamentoNomeChave(b));
    if (scoreA1 >= 2 && scoreB2 >= 2 && scoreA1 >= scoreB1 && scoreB2 >= scoreA2) {
      return [a, b];
    }
    if (scoreB1 >= 2 && scoreA2 >= 2 && scoreB1 >= scoreA1 && scoreA2 >= scoreB2) {
      return [b, a];
    }
  }
  return null;
}

/// Dados de um signatário já resolvidos (bytes opcionais da imagem da assinatura).
class CertSignatoryPdfData {
  final String nome;
  final String cargo;
  final Uint8List? signatureImageBytes;

  const CertSignatoryPdfData({
    required this.nome,
    required this.cargo,
    this.signatureImageBytes,
  });
}

/// Entrada serializável para gerar o PDF fora da thread da UI ([Isolate.run] / [compute]).
class CertificatePdfInput {
  final String titulo;
  /// Versículo ou frase curta sob o título (layouts tradicional, premium gold, moderno).
  final String subtitulo;
  final String texto;
  final String nomeMembro;
  /// Segunda linha do nome no PDF (ex.: segundo cônjuge no casamento).
  final String nomeMembroLinha2;
  /// CPF formatado como aparece em [texto] (para negrito no corpo).
  final String cpfFormatado;
  final String nomeIgreja;
  final String local;
  /// Data de emissão exibida no rodapé (aceita retroativa/futura).
  final String issuedDate;
  final String layoutId;
  final String fontStyleId;
  final int colorPrimaryArgb;
  final int colorTextArgb;
  final String pastorManual;
  final String cargoManual;
  final Uint8List? logoBytes;
  final List<CertSignatoryPdfData> signatories;
  final Uint8List? fontMontserratBytes;
  final Uint8List? fontGreatVibesBytes;
  final Uint8List? fontUnifrakturBytes;
  /// URL completa para o QR de autenticidade (layout [gala_luxo]); vazio omite o QR.
  final String qrValidationUrl;

  /// Fundo full-bleed (PNG/JPG do Storage). Se nulo, usa [visualTemplateId] para cor de fallback.
  final Uint8List? backgroundTemplateBytes;

  /// Identificador do modelo visual ([classico_dourado], [pergaminho], [moderno_geometrico]).
  final String visualTemplateId;

  /// Tipografia premium (Cinzel Decorative, Pinyon Script, Libre Baskerville) no PDF.
  final bool useLuxuryPdfFonts;

  final Uint8List? fontCinzelDecorativeBytes;
  final Uint8List? fontPinyonScriptBytes;
  final Uint8List? fontLibreBaskervilleBytes;

  const CertificatePdfInput({
    required this.titulo,
    this.subtitulo = '',
    required this.texto,
    required this.nomeMembro,
    this.nomeMembroLinha2 = '',
    this.cpfFormatado = '',
    required this.nomeIgreja,
    required this.local,
    this.issuedDate = '',
    required this.layoutId,
    this.fontStyleId = 'moderna',
    required this.colorPrimaryArgb,
    required this.colorTextArgb,
    required this.pastorManual,
    required this.cargoManual,
    this.logoBytes,
    this.signatories = const [],
    this.fontMontserratBytes,
    this.fontGreatVibesBytes,
    this.fontUnifrakturBytes,
    this.qrValidationUrl = '',
    this.backgroundTemplateBytes,
    this.visualTemplateId = 'classico_dourado',
    this.useLuxuryPdfFonts = true,
    this.fontCinzelDecorativeBytes,
    this.fontPinyonScriptBytes,
    this.fontLibreBaskervilleBytes,
  });
}

String _hexRgb(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

/// Alturas fixas (pt) — evita encavalamento por [pw.Expanded] dentro de [pw.Column] sem constraint
/// clara no pacote `pdf` (comportamento diferente do Flutter layout).
abstract final class _CertPdfLayoutHeights {
  static const double logoTop = 88;
  static const double titleBlock = 118;
  static const double nameBlock = 52;
  static const double bodyBlock = 232;
  static const double issueBlock = 36;
  static const double footerBlock = 96;
}

String _nomeCasamentoLinha2EfetivaParaDestaque(CertificatePdfInput input) {
  final n1 = input.nomeMembro.trim();
  final t = input.nomeMembroLinha2.trim();
  if (t.isNotEmpty && t != n1) return t;
  return segundoNomeCasamentoFallbackDoCorpo(input.texto, n1);
}

double _alturaBlocoNomeDecorativo(CertificatePdfInput input) {
  final n1 = input.nomeMembro.trim();
  final n2 = _nomeCasamentoLinha2EfetivaParaDestaque(input);
  if (n2.isEmpty || n2 == n1) return _CertPdfLayoutHeights.nameBlock;
  return 78;
}

double _alturaBlocoNomeDecorativoTradicional(CertificatePdfInput input) {
  final n1 = input.nomeMembro.trim();
  final n2 = _nomeCasamentoLinha2EfetivaParaDestaque(input);
  if (n2.isEmpty || n2 == n1) {
    return _CertPdfLayoutHeights.nameBlock + 4;
  }
  return 82;
}

/// Nome(s) em caligráfico no topo — casamento com duas linhas (igual ao corpo / layout gala).
pw.Widget _pwDecorativeCertificateNames({
  required CertificatePdfInput input,
  required double fontSize,
  required pw.FontWeight wDisplay,
  required PdfColor color,
  required pw.Font? font,
}) {
  final n1 = input.nomeMembro.trim();
  final n2Raw = _nomeCasamentoLinha2EfetivaParaDestaque(input);
  final n2 = (n2Raw.isNotEmpty && n2Raw != n1) ? n2Raw : '';
  final style = pw.TextStyle(
    fontSize: fontSize,
    fontWeight: wDisplay,
    color: color,
    font: font,
  );
  if (n2.isEmpty) {
    return pw.Text(
      n1,
      style: style,
      textAlign: pw.TextAlign.center,
      maxLines: 2,
    );
  }
  final fs2 = fontSize * 0.92;
  final style2 = pw.TextStyle(
    fontSize: fs2,
    fontWeight: wDisplay,
    color: color,
    font: font,
  );
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(n1, style: style, textAlign: pw.TextAlign.center, maxLines: 2),
      pw.SizedBox(height: 3),
      pw.Text(n2, style: style2, textAlign: pw.TextAlign.center, maxLines: 2),
    ],
  );
}

/// Corpo do certificado com nome(s) e CPF em negrito (trechos iguais ao texto final).
pw.Widget _certificateBodyRich({
  required String texto,
  required String nome,
  required String nomeLinha2,
  required String cpfFormatado,
  required double fontSize,
  required PdfColor color,
  pw.Font? font,
  pw.Font? fontBold,
  /// `false` para gótica/clássica: o PDF já usa face Times Bold; `fontWeight.bold` extra some o texto.
  required bool useSyntheticBoldForHighlights,
}) {
  final nomeT = nome.trim();
  final nome2T = nomeLinha2.trim();
  final cpfT = cpfFormatado.trim();
  /// Alinha com [\_stripMarkdownParaRegexCertificado]: `**` fora e espaços colapsados
  /// para os trechos do regex baterem com o mesmo texto exibido no PDF.
  final textoCorpo =
      _stripMarkdownParaRegexCertificado(texto.replaceAll('**', ''));
  final tokens = <String>[];
  final pair = (nomeT.isNotEmpty && nome2T.isNotEmpty)
      ? _casamentoHighlightPairFromCorpo(textoCorpo, nomeT, nome2T)
      : null;
  if (pair != null && pair.length == 2) {
    tokens.add(pair[0]);
    tokens.add(pair[1]);
  } else {
    if (nomeT.isNotEmpty) tokens.add(nomeT);
    if (nome2T.isNotEmpty) tokens.add(nome2T);
  }
  if (cpfT.isNotEmpty) tokens.add(cpfT);
  tokens.sort((a, b) => b.length.compareTo(a.length));
  final normal = pw.TextStyle(
    fontSize: fontSize,
    color: color,
    lineSpacing: 2,
    font: font,
  );
  final boldFont = fontBold ?? font;
  /// Face bold distinta (ex.: Times Bold no gala) — não somar [fontWeight.bold] no pacote `pdf`.
  final distinctBoldFace = fontBold != null && !identical(font, fontBold);
  final bold = pw.TextStyle(
    fontSize: fontSize,
    fontWeight: !distinctBoldFace && useSyntheticBoldForHighlights
        ? pw.FontWeight.bold
        : pw.FontWeight.normal,
    color: color,
    lineSpacing: 2,
    font: boldFont,
  );
  if (textoCorpo.isEmpty) return pw.SizedBox();
  if (tokens.isEmpty) {
    return pw.Text(
      textoCorpo,
      style: normal,
      textAlign: pw.TextAlign.center,
    );
  }
  final children = <pw.InlineSpan>[];
  var remaining = textoCorpo;
  while (remaining.isNotEmpty) {
    int bestPos = -1;
    String? bestToken;
    for (final tok in tokens) {
      if (tok.isEmpty) continue;
      // Busca case-insensitive para não perder destaque quando o corpo vier
      // em caixa diferente (ex.: "JOÃO" no texto e "João" no cadastro).
      final i = remaining.toLowerCase().indexOf(tok.toLowerCase());
      if (i < 0) continue;
      if (bestPos < 0 ||
          i < bestPos ||
          (i == bestPos && tok.length > (bestToken?.length ?? 0))) {
        bestPos = i;
        bestToken = tok;
      }
    }
    if (bestPos < 0 || bestToken == null) {
      children.add(pw.TextSpan(text: remaining, style: normal));
      break;
    }
    if (bestPos > 0) {
      children.add(
          pw.TextSpan(text: remaining.substring(0, bestPos), style: normal));
    }
    final matched = remaining.substring(bestPos, bestPos + bestToken.length);
    children.add(pw.TextSpan(text: matched, style: bold));
    remaining = remaining.substring(bestPos + matched.length);
  }
  return pw.RichText(
    textAlign: pw.TextAlign.center,
    text: pw.TextSpan(style: normal, children: children),
  );
}

/// Fundo A4 paisagem: imagem do Storage ou degradê conforme o modelo visual.
pw.Widget _galaLuxoBackgroundFill({
  required Uint8List? backgroundBytes,
  required String visualTemplateId,
}) {
  if (backgroundBytes != null && backgroundBytes.length > 64) {
    try {
      final prov = pw.MemoryImage(backgroundBytes);
      return pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Image(prov, fit: pw.BoxFit.cover),
          ),
          pw.Positioned.fill(
            child: pw.Opacity(
              opacity: 0.20,
              child: pw.Container(color: PdfColors.white),
            ),
          ),
        ],
      );
    } catch (_) {}
  }
  final id = visualTemplateId.trim();
  List<PdfColor> colors;
  switch (id) {
    case 'pergaminho':
      colors = [PdfColor.fromHex('E8D4B8'), PdfColor.fromHex('BE9B6A')];
      break;
    case 'moderno_geometrico':
      colors = [PdfColors.white, PdfColor.fromHex('F1F5F9')];
      break;
    default:
      colors = [PdfColor.fromHex('FFF8E7'), PdfColor.fromHex('F5E6C8')];
  }
  return pw.Container(
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(
        colors: colors,
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
      ),
    ),
  );
}

/// Monta e serializa o certificado (uso em isolate; [doc.save] é assíncrono no pdf ^3.10).
/// Tipografias TTF passadas em [CertificatePdfInput] são **embutidas** no PDF via [pw.Font.ttf].
Future<Uint8List> buildCertificatePdfBytes(CertificatePdfInput input) async {
  if (input.layoutId == 'gala_luxo') {
    final docGala = pw.Document();
    _appendGalaLuxoCertificatePage(docGala, input);
    return Uint8List.fromList(await docGala.save());
  }

  final doc = pw.Document();
  final corHex = _hexRgb(input.colorPrimaryArgb);
  final pdfCor = PdfColor.fromHex(corHex);
  final textHex = _hexRgb(input.colorTextArgb);
  final pdfTextCor = PdfColor.fromHex(textHex);
  final pdfCorClaro = PdfColor.fromHex(corHex).shade(0.85);

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
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.SizedBox(
                width: 108,
                height: 44,
                child: pw.Image(img, fit: pw.BoxFit.contain),
              ),
            ),
          pw.Container(width: 120, height: 1, color: accent),
          pw.SizedBox(height: 8),
          pw.Text(
            s.nome,
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            s.cargo,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
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
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: accent,
          ),
        ),
      ],
    );
  }

  final isTradicional = input.layoutId == 'tradicional';
  final isMinimalista = input.layoutId == 'minimalista';
  final isPremiumGold = input.layoutId == 'premium_gold';
  final isClassica = input.fontStyleId == 'classica';
  final isGotica = input.fontStyleId == 'gotica';
  /// Só clássica usa script “decorativo” no título; “gótica” legava blackletter ilegível — tratamos como moderna no PDF.
  final decorative = isClassica;
  /// Sem peso sintético no nome/título quando a face TTF já é bold ou script (evita sumiço de glifos no pdf).
  final pw.FontWeight wDisplay =
      decorative ? pw.FontWeight.normal : pw.FontWeight.bold;
  final useSyntheticBoldInBody = !decorative;
  final nomeLinha2Corpo = _nomeCasamentoLinha2EfetivaParaDestaque(input);

  pw.Font? montserrat;
  pw.Font? greatVibes;
  if (input.fontMontserratBytes != null && input.fontMontserratBytes!.isNotEmpty) {
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

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) {
        if (isPremiumGold) {
          return pw.Container(
            width: double.infinity,
            height: double.infinity,
            color: PdfColors.white,
            padding: const pw.EdgeInsets.all(18),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColor.fromHex('D4AF37'),
                  width: 2.4,
                ),
              ),
              child: pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(26, 18, 26, 22),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromHex('E9D08C'),
                    width: 1.2,
                  ),
                ),
                child: pw.Stack(
                  children: [
                    if (logoImage != null)
                      pw.Center(
                        child: pw.Opacity(
                          opacity: 0.085,
                          child: pw.Container(
                            width: 300,
                            height: 300,
                            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                          ),
                        ),
                      ),
                    pw.Positioned.fill(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.SizedBox(height: logoImage != null ? 22 : 28),
                          if (input.nomeIgreja.trim().isNotEmpty) ...[
                            pw.Padding(
                              padding:
                                  const pw.EdgeInsets.symmetric(horizontal: 20),
                              child: pw.Text(
                                input.nomeIgreja.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pdfCor,
                                  font: fontForBody(),
                                  letterSpacing: 0.4,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                          ],
                          pw.SizedBox(
                            height: _CertPdfLayoutHeights.titleBlock,
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.start,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  input.titulo.toUpperCase(),
                                  style: pw.TextStyle(
                                    fontSize: 22,
                                    fontWeight: wDisplay,
                                    color: pdfTextCor,
                                    letterSpacing: 0.9,
                                    font: fontForTitle(),
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                                if (input.subtitulo.trim().isNotEmpty) ...[
                                  pw.SizedBox(height: 6),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: pw.Text(
                                      input.subtitulo.trim(),
                                      style: pw.TextStyle(
                                        fontSize: 12,
                                        fontStyle: pw.FontStyle.italic,
                                        color: pdfTextCor,
                                        font: fontForBody(),
                                      ),
                                      textAlign: pw.TextAlign.center,
                                      maxLines: 3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          pw.SizedBox(
                            height: _alturaBlocoNomeDecorativo(input),
                            child: pw.Center(
                              child: _pwDecorativeCertificateNames(
                                input: input,
                                fontSize: nameSize(22),
                                wDisplay: wDisplay,
                                color: pdfCor,
                                font: fontForName(),
                              ),
                            ),
                          ),
                          pw.SizedBox(
                            height: _CertPdfLayoutHeights.bodyBlock,
                            child: pw.Center(
                              child: pw.Container(
                                constraints:
                                    const pw.BoxConstraints(maxWidth: 480),
                                child: _certificateBodyRich(
                                  texto: input.texto,
                                  nome: input.nomeMembro,
                                  nomeLinha2: nomeLinha2Corpo,
                                  cpfFormatado: input.cpfFormatado,
                                  fontSize: 12,
                                  color: pdfTextCor,
                                  font: fontForBody(),
                                  fontBold: fontForBodyBold(),
                                  useSyntheticBoldForHighlights:
                                      useSyntheticBoldInBody,
                                ),
                              ),
                            ),
                          ),
                          pw.SizedBox(
                            height: _CertPdfLayoutHeights.issueBlock,
                            child: issueLine().isNotEmpty
                                ? pw.Center(
                                    child: pw.Text(
                                      issueLine(),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        color: pdfCorClaro,
                                        font: fontForBody(),
                                      ),
                                      textAlign: pw.TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  )
                                : pw.SizedBox(),
                          ),
                          pw.SizedBox(
                            height: _CertPdfLayoutHeights.footerBlock,
                            child: pw.Center(
                              child: buildFooterSignatures(
                                  pdfCor, pdfCorClaro),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (isTradicional) {
          return pw.Container(
            width: double.infinity,
            height: double.infinity,
            color: PdfColors.white,
            padding: const pw.EdgeInsets.all(18),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColor.fromHex('C9983A'), width: 2.2),
              ),
              child: pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(24, 16, 24, 20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: PdfColor.fromHex('E5C77A'), width: 1.2),
                ),
                child: pw.Stack(
                  children: [
                    if (logoImage != null)
                      pw.Center(
                        child: pw.Opacity(
                          opacity: 0.075,
                          child: pw.Container(
                            width: 280,
                            height: 280,
                            child:
                                pw.Image(logoImage, fit: pw.BoxFit.contain),
                          ),
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              input.titulo.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: wDisplay,
                                color: pdfTextCor,
                                letterSpacing: 1.0,
                                font: fontForTitle(),
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            if (input.nomeIgreja.trim().isNotEmpty) ...[
                              pw.SizedBox(height: 6),
                              pw.Text(
                                input.nomeIgreja.toUpperCase(),
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pdfCor,
                                  font: fontForBody(),
                                  letterSpacing: 0.35,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                            if (input.subtitulo.trim().isNotEmpty) ...[
                              pw.SizedBox(height: 6),
                              pw.Text(
                                input.subtitulo.trim(),
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontStyle: pw.FontStyle.italic,
                                  color: pdfTextCor,
                                  font: fontForBody(),
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        pw.SizedBox(
                          height: _alturaBlocoNomeDecorativoTradicional(input),
                          child: pw.Center(
                            child: _pwDecorativeCertificateNames(
                              input: input,
                              fontSize: nameSize(20),
                              wDisplay: wDisplay,
                              color: pdfCor,
                              font: fontForName(),
                            ),
                          ),
                        ),
                        pw.SizedBox(
                          height: _CertPdfLayoutHeights.bodyBlock + 24,
                          child: pw.Center(
                            child: pw.Container(
                              constraints:
                                  const pw.BoxConstraints(maxWidth: 480),
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  _certificateBodyRich(
                                    texto: input.texto,
                                    nome: input.nomeMembro,
                                    nomeLinha2: nomeLinha2Corpo,
                                    cpfFormatado: input.cpfFormatado,
                                    fontSize: 13,
                                    color: pdfTextCor,
                                    font: fontForBody(),
                                    fontBold: fontForBodyBold(),
                                    useSyntheticBoldForHighlights:
                                        useSyntheticBoldInBody,
                                  ),
                                  if (issueLine().isNotEmpty) ...[
                                    pw.SizedBox(height: 12),
                                    pw.Text(
                                      issueLine(),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        color: pdfCorClaro,
                                        font: fontForBody(),
                                      ),
                                      textAlign: pw.TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        buildFooterSignatures(pdfCor, pdfCorClaro),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return pw.Container(
          width: double.infinity,
          height: double.infinity,
          color: isMinimalista ? PdfColors.white : PdfColors.grey100,
          padding: const pw.EdgeInsets.all(20),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: pdfCor, width: 2.2),
            ),
            child: pw.Column(
              children: [
                pw.Container(
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: pdfCor,
                    borderRadius: const pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(10),
                      topRight: pw.Radius.circular(10),
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 16),
                    child: pw.Stack(
                      children: [
                        if (logoImage != null)
                          pw.Center(
                            child: pw.Opacity(
                              opacity: 0.07,
                              child: pw.Container(
                                width: 300,
                                height: 300,
                                child: pw.Image(logoImage,
                                    fit: pw.BoxFit.contain),
                              ),
                            ),
                          ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                        pw.SizedBox(
                          height: _CertPdfLayoutHeights.logoTop +
                              _CertPdfLayoutHeights.titleBlock +
                              8,
                          child: pw.Column(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.start,
                            crossAxisAlignment:
                                pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                input.titulo,
                                style: pw.TextStyle(
                                  fontSize:
                                      isMinimalista ? 26 : 24,
                                  fontWeight: wDisplay,
                                  color: pdfCor,
                                  font: fontForTitle(),
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                              if (input.subtitulo
                                  .trim()
                                  .isNotEmpty) ...[
                                pw.SizedBox(height: 8),
                                pw.Padding(
                                  padding: const pw
                                      .EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: pw.Text(
                                    input.subtitulo.trim(),
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      fontStyle:
                                          pw.FontStyle.italic,
                                      color: pdfTextCor,
                                      font: fontForBody(),
                                    ),
                                    textAlign: pw.TextAlign.center,
                                    maxLines: 3,
                                  ),
                                ),
                              ],
                              if (input.nomeIgreja
                                  .trim()
                                  .isNotEmpty) ...[
                                pw.SizedBox(height: 8),
                                pw.Padding(
                                  padding: const pw
                                      .EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: pw.Text(
                                    input.nomeIgreja
                                        .toUpperCase(),
                                    style: pw.TextStyle(
                                      fontSize: 11,
                                      color: pdfCor,
                                      fontWeight:
                                          pw.FontWeight.bold,
                                      font: fontForBody(),
                                      letterSpacing: 0.35,
                                    ),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        pw.SizedBox(
                          height: _alturaBlocoNomeDecorativo(input),
                          child: pw.Center(
                            child: _pwDecorativeCertificateNames(
                              input: input,
                              fontSize: nameSize(22),
                              wDisplay: wDisplay,
                              color: pdfTextCor,
                              font: fontForName(),
                            ),
                          ),
                        ),
                        pw.SizedBox(
                          height: _CertPdfLayoutHeights.bodyBlock + 20,
                          child: pw.Center(
                            child: pw.Container(
                              constraints:
                                  const pw.BoxConstraints(maxWidth: 480),
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  _certificateBodyRich(
                                    texto: input.texto,
                                    nome: input.nomeMembro,
                                    nomeLinha2: nomeLinha2Corpo,
                                    cpfFormatado: input.cpfFormatado,
                                    fontSize: 12,
                                    color: pdfTextCor,
                                    font: fontForBody(),
                                    fontBold: fontForBodyBold(),
                                    useSyntheticBoldForHighlights:
                                        useSyntheticBoldInBody,
                                  ),
                                  if (issueLine().isNotEmpty) ...[
                                    pw.SizedBox(height: 14),
                                    pw.Text(
                                      issueLine(),
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        color: pdfCorClaro,
                                        font: fontForBody(),
                                      ),
                                      textAlign: pw.TextAlign.center,
                                      maxLines: 2,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                  ),
                ),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: buildFooterSignatures(pdfCor, pdfCorClaro),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  final raw = await doc.save();
  return Uint8List.fromList(raw);
}
