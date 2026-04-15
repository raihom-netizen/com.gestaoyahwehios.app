/// Normalização leve para descrições de eventos/avisos (compartilhamento).
String polishTextForShare(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll(RegExp(r'\s+([.,;:!?])'), r'$1');
  return s;
}

/// [polishTextForShare] + capitalização no início de cada frase (após `. ` `! ` `? `).
String modernizeShareText(String raw) {
  var s = polishTextForShare(raw);
  if (s.isEmpty) return s;
  final parts = s.split(RegExp(r'(?<=[.!?])\s+'));
  final out = <String>[];
  for (final p in parts) {
    final t = p.trimLeft();
    if (t.isEmpty) continue;
    final first = t[0];
    final rest = t.length > 1 ? t.substring(1) : '';
    out.add(first.toUpperCase() + rest);
  }
  return out.join(' ');
}
