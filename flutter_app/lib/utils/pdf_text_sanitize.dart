/// Normaliza texto para PDFs gerados com `package:pdf` e fontes Latin base:
/// travessões e alguns Unicode viram quadrados ("tofu") se o glifo não existir na fonte.
String pdfSafeText(String? input) {
  if (input == null) return '';
  var s = input;
  // Travessões / hífens Unicode → ASCII
  s = s.replaceAll('\u2014', ' - '); // em dash —
  s = s.replaceAll('\u2013', '-'); // en dash –
  s = s.replaceAll('\u2212', '-'); // minus sign
  s = s.replaceAll('\uFE58', '-'); // small em dash
  // Espaços especiais
  s = s.replaceAll('\u00A0', ' ');
  s = s.replaceAll('\u202F', ' ');
  // Reticências e substituto
  s = s.replaceAll('\u2026', '...');
  s = s.replaceAll('\uFFFD', '');
  // Zero-width space (ex.: quebra em e-mail) — em alguns leitores PDF vira “tofu”.
  s = s.replaceAll('\u200B', '');
  s = s.replaceAll('\u200C', '');
  s = s.replaceAll('\uFEFF', '');
  // Aspas tipográficas comuns (opcional: reduz problemas em cópias de Word)
  s = s.replaceAll('\u201C', '"');
  s = s.replaceAll('\u201D', '"');
  s = s.replaceAll('\u2018', "'");
  s = s.replaceAll('\u2019', "'");
  return s.trimRight();
}

List<String> pdfSafeStrings(Iterable<String> lines) =>
    lines.map(pdfSafeText).toList();

List<List<String>> pdfSafeTableRows(List<List<String>> rows) =>
    rows.map((r) => r.map(pdfSafeText).toList()).toList();

/// E-mail para PDF: só sanitiza (sem U+200B — Helvetica/Roboto antigo quebrava o `@`).
String pdfEmailBreakOpportunities(String? input) {
  return pdfSafeText(input);
}
