import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Linha de membro na carta (nome + CPF opcional).
class ChurchLetterMemberLine {
  final String name;
  final String? cpfDigits;

  const ChurchLetterMemberLine({required this.name, this.cpfDigits});
}

/// Corpo da carta: ~2 cm de recuo na 1.ª linha (normas cultas).
const double _kLetterFirstLineIndentPt = 57;

/// Gera PDF de carta de apresentação ou transferência (cabeçalho premium + logo).
Future<Uint8List> buildChurchTransferLetterPdf({
  required ReportPdfBranding branding,
  required String documentTitle,
  required String bodyAfterReplacements,
  required Map<String, dynamic> churchData,
}) async {
  await PdfSuperPremiumTheme.loadRobotoPdfTheme();
  final doc = await PdfSuperPremiumTheme.newPdfDocument();

  pw.Font? serifBody;
  try {
    final bytes =
        await rootBundle.load('assets/fonts/LibreBaskerville-Variable.ttf');
    serifBody = pw.Font.ttf(bytes);
  } catch (e, st) {
    debugPrint('church_transfer_letter_pdf: serif font $e\n$st');
  }

  final extra = _churchHeaderExtraLines(churchData);
  final ink = PdfColor.fromInt(0xFF1E293B);
  final muted = PdfColor.fromInt(0xFF64748B);
  final oficioDate = pdfSafeText(_oficioDateLineExtensa(churchData));

  final bodyStyle = pw.TextStyle(
    fontSize: 10.5,
    lineSpacing: 1.38,
    color: ink,
    font: serifBody,
  );

  final paragraphs = _buildChurchLetterBodyWidgetsPremium(
    bodyAfterReplacements,
    bodyStyle: bodyStyle,
    signatureFrameColor: branding.accent,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 80,
      theme: doc.theme,
      pageTheme: pw.PageTheme(
        // Margens um pouco mais estreitas para caber assinatura + rodapé numa folha.
        margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 42),
      ),
      header: (pw.Context ctx) {
        if (ctx.pageNumber != 1) return pw.SizedBox();
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            PdfSuperPremiumTheme.header(
              documentTitle,
              branding: branding,
              extraLines: extra,
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                oficioDate,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  color: ink,
                  fontStyle: pw.FontStyle.italic,
                  font: serifBody,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.SizedBox(height: 10),
          ],
        );
      },
      footer: (pw.Context ctx) {
        final left = pdfSafeText(branding.churchName.trim());
        return pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.55),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  left.isEmpty ? 'Carta ministerial' : '$left · Carta ministerial',
                  style: pw.TextStyle(fontSize: 7.8, color: muted),
                ),
              ),
              pw.Text(
                'Pág. ${ctx.pageNumber}/${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 7.8, color: muted),
              ),
            ],
          ),
        );
      },
      build: (pw.Context ctx) => paragraphs,
    ),
  );

  return doc.save();
}

/// Data por extenso + local (padrão ofício), alinhada à direita abaixo do cabeçalho.
String _oficioDateLineExtensa(Map<String, dynamic> data) {
  final cidade =
      (data['cidade'] ?? data['CIDADE'] ?? data['localidade'] ?? '').toString().trim();
  final uf = (data['estado'] ?? data['UF'] ?? data['uf'] ?? '').toString().trim();
  String local = '';
  if (cidade.isNotEmpty && uf.isNotEmpty) {
    local = '$cidade–$uf';
  } else if (cidade.isNotEmpty) {
    local = cidade;
  } else if (uf.isNotEmpty) {
    local = uf;
  }
  final dataEx =
      DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(DateTime.now());
  if (local.isEmpty) return dataEx;
  return '$local, $dataEx';
}

/// Início do bloco de assinaturas (texto corrido, antes do trecho centralizado).
int? _signatureBlockStartIndex(String body) {
  const keys = ['Fraternalmente em Cristo', 'Atenciosamente'];
  int? best;
  for (final k in keys) {
    final i = body.indexOf(k);
    if (i >= 0 && (best == null || i < best)) best = i;
  }
  return best;
}

bool _looksLikeMemberLine(String raw) {
  final x = raw.startsWith('•') ? raw.substring(1).trim() : raw;
  if (x.contains('—')) return true;
  if (x.toUpperCase().contains('CPF')) return true;
  if (RegExp(r'\d{3}\.\d{3}\.\d{3}-\d{2}').hasMatch(x)) return true;
  final d = x.replaceAll(RegExp(r'\D'), '');
  return d.length == 11;
}

/// Linhas de lista de membros (nome + CPF) — alinham como parágrafo com recuo, sem bullet extra.
bool _chunkIsMemberListLines(String chunk) {
  final lines = chunk
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return false;
  return lines.every(_looksLikeMemberLine);
}

bool _chunkIsSalutationOrQuoteOrList(String chunk) {
  final t = chunk.trim();
  if (t.isEmpty) return true;
  if (_chunkIsMemberListLines(chunk)) return false;
  final lines = t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return true;
  final fl = lines.first;
  if (fl.startsWith('À')) return true;
  if (fl.startsWith('Graça')) return true;
  if (fl.startsWith('Prezado')) return true;
  if (fl.startsWith('"') || fl.startsWith('“') || fl.startsWith('«')) return true;
  if (fl.startsWith('Membros apresentados')) return true;
  if (fl.startsWith('E no demais')) return true;
  if (fl.startsWith('Para que o mundo')) return true;
  if (lines.every((l) => l.startsWith('•') || l.startsWith('-'))) {
    return true;
  }
  return false;
}

bool _chunkWantsJustifyNormaCulta(String chunk) {
  if (_chunkIsSalutationOrQuoteOrList(chunk)) return false;
  if (_chunkIsMemberListLines(chunk)) return true;
  return chunk.trim().length > 55;
}

pw.Widget _normaCultaBodyParagraph(String chunk, {required pw.TextStyle bodyStyle}) {
  var body = chunk.trim();
  if (_chunkIsMemberListLines(body)) {
    body = body
        .split('\n')
        .map((l) {
          var t = l.trim();
          if (t.startsWith('•')) t = t.substring(1).trim();
          if (t.startsWith('-') && t.length > 1 && t[1] == ' ') {
            t = t.substring(1).trim();
          }
          return t;
        })
        .join('\n');
  }
  final isMembers = _chunkIsMemberListLines(chunk);
  final align = isMembers
      ? pw.TextAlign.left
      : (_chunkWantsJustifyNormaCulta(chunk)
          ? pw.TextAlign.justify
          : pw.TextAlign.left);
  final useIndent = _chunkWantsJustifyNormaCulta(chunk);
  final text = pw.Text(
    pdfSafeText(body),
    style: bodyStyle,
    textAlign: align,
  );
  final padded = useIndent
      ? pw.Padding(
          padding: const pw.EdgeInsets.only(left: _kLetterFirstLineIndentPt),
          child: text,
        )
      : text;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 9),
    child: padded,
  );
}

pw.Widget _normaCultaSignatureBlock(
  String sigPart, {
  required pw.TextStyle bodyStyle,
  PdfColor? signatureFrameColor,
}) {
  final t = sigPart.trim();
  if (t.isEmpty) return pw.SizedBox();

  const salutations = ['Fraternalmente em Cristo', 'Atenciosamente'];
  String? salLine;
  final rest = <String>[];
  for (final raw in t.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (salLine == null) {
      final hit = salutations.any((s) => line.startsWith(s));
      if (hit) {
        salLine = line;
        continue;
      }
      rest.add(line);
    } else {
      rest.add(line);
    }
  }

  if (salLine == null) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 13),
      child: pw.Text(
        pdfSafeText(t),
        style: bodyStyle,
        textAlign: pw.TextAlign.left,
      ),
    );
  }

  final fs = bodyStyle.fontSize ?? 11;
  final lh = bodyStyle.lineSpacing ?? 1.45;
  final gap4 = fs * lh * 2.1;
  final frame = signatureFrameColor ?? PdfColor.fromInt(0xFF64748B);
  final nameStyle = bodyStyle.copyWith(
    fontSize: (bodyStyle.fontSize ?? 10.5) + 1.0,
    fontWeight: pw.FontWeight.bold,
  );

  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          pdfSafeText(salLine),
          style: bodyStyle,
          textAlign: pw.TextAlign.left,
        ),
        pw.SizedBox(height: gap4),
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAFC),
            borderRadius: pw.BorderRadius.circular(7),
            border: pw.Border.all(
              color: PdfColor(frame.red, frame.green, frame.blue, 0.4),
              width: 1.2,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                height: 3,
                decoration: pw.BoxDecoration(
                  color: frame,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(height: 12),
              ...rest.map(
                (line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    pdfSafeText(line),
                    style: nameStyle,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

List<pw.Widget> _buildChurchLetterBodyWidgetsPremium(
  String bodyAfterReplacements, {
  required pw.TextStyle bodyStyle,
  PdfColor? signatureFrameColor,
}) {
  final raw = bodyAfterReplacements.replaceAll('\r\n', '\n').trim();
  if (raw.isEmpty) return [];

  final sigAt = _signatureBlockStartIndex(raw);
  String mainPart;
  String? sigPart;
  if (sigAt != null) {
    mainPart = raw.substring(0, sigAt).trim();
    sigPart = raw.substring(sigAt).trim();
  } else {
    mainPart = raw;
    sigPart = null;
  }

  final out = <pw.Widget>[];
  if (mainPart.isNotEmpty) {
    for (final chunk in mainPart
        .split(RegExp(r'\n\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)) {
      out.add(_normaCultaBodyParagraph(chunk, bodyStyle: bodyStyle));
    }
  }
  if (sigPart != null && sigPart.isNotEmpty) {
    out.add(_normaCultaSignatureBlock(
      sigPart,
      bodyStyle: bodyStyle,
      signatureFrameColor: signatureFrameColor,
    ));
  }
  return out;
}

List<String> _churchHeaderExtraLines(Map<String, dynamic> data) {
  final lines = <String>[];
  final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
  final qd = (data['quadraLoteNumero'] ?? '').toString().trim();
  final ruaC = rua.isEmpty ? qd : (qd.isEmpty ? rua : '$rua, $qd');
  final bairro = (data['bairro'] ?? '').toString().trim();
  final cidade =
      (data['cidade'] ?? data['CIDADE'] ?? data['localidade'] ?? '').toString().trim();
  final uf = (data['estado'] ?? data['UF'] ?? data['uf'] ?? '').toString().trim();
  final cep = (data['cep'] ?? data['CEP'] ?? '').toString().trim();
  final parts = <String>[];
  if (ruaC.isNotEmpty) parts.add(ruaC);
  if (bairro.isNotEmpty) parts.add(bairro);
  if (cidade.isNotEmpty && uf.isNotEmpty) {
    parts.add('$cidade - $uf');
  } else if (cidade.isNotEmpty) {
    parts.add(cidade);
  } else if (uf.isNotEmpty) {
    parts.add(uf);
  }
  if (cep.isNotEmpty) parts.add('CEP $cep');
  if (parts.isNotEmpty) {
    lines.add(parts.join(', '));
  }
  final tel = (data['telefoneIgreja'] ??
          data['telefone'] ??
          data['whatsappIgreja'] ??
          data['whatsapp'] ??
          '')
      .toString()
      .trim();
  if (tel.isNotEmpty) {
    lines.add('Contato: $tel');
  }
  return lines;
}

/// Monta o bloco em bullets dos membros selecionados.
String churchLetterMembersBlock(Iterable<ChurchLetterMemberLine> members) {
  final buf = StringBuffer();
  for (final m in members) {
    final n = m.name.trim();
    if (n.isEmpty) continue;
    final c = (m.cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (c.length == 11) {
      buf.writeln('$n — CPF ${_formatCpf(c)}');
    } else if (c.isNotEmpty) {
      buf.writeln('$n — CPF $c');
    } else {
      buf.writeln(n);
    }
  }
  return buf.toString().trim();
}

/// Nomes em texto corrido (ex.: "A e B" ou "A, B e C") para modelos tipo carta de mudança.
String churchLetterMembersInline(Iterable<ChurchLetterMemberLine> members) {
  final names = <String>[];
  for (final m in members) {
    final n = m.name.trim();
    if (n.isNotEmpty) names.add(n);
  }
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} e ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
}

String _formatCpf(String d) {
  if (d.length != 11) return d;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

/// Corpo da carta (sem bloco de assinaturas) — destinos, missão, lista de membros.
/// Evita "Igreja Igreja …" quando o utilizador já escreve "Igreja Batista …" no campo
/// (modelo já traz o prefixo «Igreja » antes do marcador).
String normalizeDestinationChurchNameForLetter(String raw) {
  var s = raw.trim();
  if (s.length > 7) {
    final low = s.toLowerCase();
    if (low.startsWith('igreja ')) {
      s = s.substring(7).trim();
    }
  }
  return s;
}

String applyChurchLetterBodyPlaceholders({
  required String template,
  required String destinationChurchName,
  required String issuingChurchName,
  required String cityState,
  required String missionDescription,
  required String membersBlock,
  String membersInline = '',
}) {
  var s = template;
  void rep(String key, String value) {
    s = s.replaceAll(key, value);
  }

  rep(
    '[Nome da Igreja Destinatária]',
    normalizeDestinationChurchNameForLetter(destinationChurchName),
  );
  // Modelo neutro (empresas / instituições) — mesmo valor que os marcadores eclesiásticos.
  rep(
    '[Nome da entidade destinatária]',
    normalizeDestinationChurchNameForLetter(destinationChurchName),
  );
  rep('[Nome da Sua Igreja]', issuingChurchName.trim());
  rep('[Nome da sua entidade]', issuingChurchName.trim());
  rep('[Igreja Nome]', issuingChurchName.trim());
  rep('[cidade/estado]', cityState.trim());
  rep(
    '[breve descrição: evangelizar, discipular, servir a comunidade, etc.]',
    missionDescription.trim(),
  );
  rep('[Lista de membros apresentados]', membersBlock.trim());
  rep('[Membros por extenso]', membersInline.trim());
  rep('[ocasião ou motivo da gratidão]', missionDescription.trim());
  return s;
}

/// Bloco de encerramento com até duas assinaturas (cadastro de membro).
String buildChurchLetterSignatureBlock({
  required String signer1Name,
  required String signer1Role,
  String signer2Name = '',
  String signer2Role = '',
  required String churchLine,
  required String contact,
  String openingSalutation = 'Fraternalmente em Cristo,',
}) {
  final n1 = signer1Name.trim();
  final r1 = signer1Role.trim();
  final n2 = signer2Name.trim();
  final r2 = signer2Role.trim();
  final ch = churchLine.trim();
  final ct = contact.trim();
  final b = StringBuffer();
  b.writeln(openingSalutation.trim());
  b.writeln();
  b.writeln(n1);
  if (r1.isNotEmpty) b.writeln(r1);
  if (n2.isNotEmpty) {
    b.writeln();
    b.writeln(n2);
    if (r2.isNotEmpty) b.writeln(r2);
  }
  b.writeln();
  b.writeln(ch);
  b.writeln(ct);
  return b.toString().trim();
}

/// Preenche o modelo: usa `[BLOCO_ASSINATURAS]` (recomendado) ou marcadores legados.
String fillChurchLetterTemplate({
  required String template,
  required String destinationChurchName,
  required String issuingChurchName,
  required String cityState,
  required String missionDescription,
  required String membersBlock,
  required String signer1Name,
  required String signer1Role,
  String signer2Name = '',
  String signer2Role = '',
  required String issuerChurchLine,
  required String issuerContact,
  String membersInline = '',
  String openingSalutation = 'Fraternalmente em Cristo,',
}) {
  final t = template.trim();
  if (t.contains('[BLOCO_ASSINATURAS]')) {
    final body = applyChurchLetterBodyPlaceholders(
      template: t,
      destinationChurchName: destinationChurchName,
      issuingChurchName: issuingChurchName,
      cityState: cityState,
      missionDescription: missionDescription,
      membersBlock: membersBlock,
      membersInline: membersInline,
    );
    final sig = buildChurchLetterSignatureBlock(
      signer1Name: signer1Name,
      signer1Role: signer1Role,
      signer2Name: signer2Name,
      signer2Role: signer2Role,
      churchLine: issuerChurchLine,
      contact: issuerContact,
      openingSalutation: openingSalutation,
    );
    return body.replaceAll('[BLOCO_ASSINATURAS]', sig);
  }
  return applyChurchLetterPlaceholders(
    template: t,
    destinationChurchName: destinationChurchName,
    issuingChurchName: issuingChurchName,
    cityState: cityState,
    missionDescription: missionDescription,
    membersBlock: membersBlock,
    issuerName: signer1Name,
    issuerRole: signer1Role,
    issuer2Name: signer2Name,
    issuer2Role: signer2Role,
    issuerChurchLine: issuerChurchLine,
    issuerContact: issuerContact,
    membersInline: membersInline,
  );
}

/// Substitui marcadores padrão no texto editável (modelos legados com [Seu Nome] no corpo).
String applyChurchLetterPlaceholders({
  required String template,
  required String destinationChurchName,
  required String issuingChurchName,
  required String cityState,
  required String missionDescription,
  required String membersBlock,
  required String issuerName,
  required String issuerRole,
  String issuer2Name = '',
  String issuer2Role = '',
  required String issuerChurchLine,
  required String issuerContact,
  String membersInline = '',
}) {
  var s = applyChurchLetterBodyPlaceholders(
    template: template,
    destinationChurchName: destinationChurchName,
    issuingChurchName: issuingChurchName,
    cityState: cityState,
    missionDescription: missionDescription,
    membersBlock: membersBlock,
    membersInline: membersInline,
  );
  void rep(String key, String value) {
    s = s.replaceAll(key, value);
  }

  rep('[Seu Nome]', issuerName.trim());
  rep('[Cargo - ex: Pastor, Líder, etc.]', issuerRole.trim());
  rep('[Cargo – ex: Pastor, Líder, etc.]', issuerRole.trim());
  rep('[Seu Nome 2]', issuer2Name.trim());
  rep('[Cargo 2 - ex: Pastor, Líder, etc.]', issuer2Role.trim());
  rep('[Cargo 2 – ex: Pastor, Líder, etc.]', issuer2Role.trim());
  rep('[Contato - telefone/WhatsApp/e-mail]', issuerContact.trim());
  rep('[Contato – telefone/WhatsApp/e-mail]', issuerContact.trim());
  rep('[Igreja Nome]', issuerChurchLine.trim());
  return s;
}

/// Modelos iniciais (placeholders com hífen ASCII para cópia estável).
const String kDefaultChurchLetterApresentacaoTemplate = '''
À
Igreja [Nome da Igreja Destinatária]

Graça e paz!

Com estima no Senhor, a [Nome da Sua Igreja], em [cidade/estado], dirige-se a vós para apresentar, para vossa acolhida e comunhão no Corpo de Cristo, o(s) membro(s) relacionado(s) abaixo.

Nossa igreja caminha na missão de [breve descrição: evangelizar, discipular, servir a comunidade, etc.], buscando fidelidade às Escrituras, ao evangelho e ao serviço ao Reino de Deus.

Membros apresentados:

[Lista de membros apresentados]

Reforçamos o desejo de unidade na fé, no amor e no testemunho cristão, e colocamo-nos à disposição para comunhão e cooperação ministerial, na medida do que o Senhor permitir.

"Para que o mundo creia." João 17:21

[BLOCO_ASSINATURAS]
''';

const String kDefaultChurchLetterTransferenciaTemplate = '''
A [Nome da Sua Igreja], em [cidade/estado], apresenta nossos irmãos em Cristo, [Membros por extenso], que sendo membros nesta igreja e estando em perfeita comunhão e idoneidade, com dedicação exemplar ao serviço de Deus e à comunhão dos santos, recomendamos que recebais como costumam fazer os santos no Senhor.

Gratos pelo acolhimento e pelo carinho, nos confraternizamos, sempre rendidos à fé e ao amor em Cristo Jesus, o nosso Senhor.

E no demais, irmãos meus, fortalecei-vos no Senhor e na força de seu poder. "Habite ricamente em vocês a palavra de Cristo; ensinem e aconselhem-se uns aos outros com toda sabedoria, e cantem salmos, hinos e cânticos espirituais com gratidão a Deus em seus corações". Colossenses 3:16

[BLOCO_ASSINATURAS]
''';

/// Carta de agradecimento — texto neutro (empresas, ONGs, instituições ou igrejas).
/// Preencha o motivo no campo «Motivo da gratidão» ou edite o modelo; marcadores eclesiásticos continuam válidos.
const String kDefaultChurchLetterAgradecimentoTemplate = '''
À
[Nome da entidade destinatária]

Prezado(a)s,

Por meio desta, [Nome da sua entidade], com sede em [cidade/estado], manifesta reconhecimento e agradecimento por [ocasião ou motivo da gratidão].

Valorizamos a colaboração recebida e permanecemos à disposição para futuras interações de mútuo proveito.

[BLOCO_ASSINATURAS]
''';
