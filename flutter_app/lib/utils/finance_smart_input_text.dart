/// Texto colado / importação: remove ruído comum (controlo, zero-width) sem quebrar extratos.
class FinanceSmartInputText {
  FinanceSmartInputText._();

  static final RegExp _zwsAndControls = RegExp(
    r'[\u200B-\u200D\uFEFF\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );

  /// Limpa caracteres estranhos, NBSP, normaliza espaços.
  static String sanitize(String s) {
    if (s.isEmpty) return s;
    var t = s
        .replaceAll('\uFEFF', '')
        .replaceAll('\u00A0', ' ')
        .replaceAll(_zwsAndControls, ' ');
    t = t.replaceAll(RegExp(r'[ \t\u00A0]+'), ' ');
    t = t.replaceAll(RegExp(r' *\n *'), '\n');
    return t.trim();
  }
}
