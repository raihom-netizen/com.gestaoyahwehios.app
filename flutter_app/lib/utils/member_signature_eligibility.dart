// Regras compartilhadas: campo de assinatura e signatários na carteirinha.
// Qualquer função além de "membro" exige o bloco de assinatura e habilita a pessoa como signatário no PDF.

/// Normaliza chave de função para comparação (minúsculas, trim, espaços → `_`).
String normalizeMemberRoleKey(String raw) {
  return raw
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('á', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');
}

/// Extrai lista de chaves de função/cargo do documento do membro (mesma lógica da tela de membros).
List<String> extractMemberFuncoesKeys(Map<String, dynamic> d) {
  final funcoesRaw = d['FUNCOES'] ?? d['funcoes'];
  var keys = <String>[];
  if (funcoesRaw is List) {
    keys = funcoesRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet().toList();
  }
  if (keys.isEmpty) {
    final f = (d['FUNCAO'] ?? d['funcao'] ?? d['CARGO'] ?? d['cargo'] ?? d['role'] ?? '').toString().trim();
    if (f.isNotEmpty) keys = [f];
  }
  if (keys.isEmpty) keys = ['membro'];
  return keys;
}

/// `true` se houver pelo menos uma função que não seja apenas "membro".
bool memberNeedsAssinaturaFieldFromFuncoes(List<String> funcoes) {
  for (final f in funcoes) {
    final n = normalizeMemberRoleKey(f);
    if (n.isEmpty) continue;
    if (n != 'membro') return true;
  }
  return false;
}

/// Membro pode figurar como signatário na carteirinha (cargo de liderança / não só membro).
bool memberHasLeadershipForAssinatura(Map<String, dynamic> d) {
  return memberNeedsAssinaturaFieldFromFuncoes(extractMemberFuncoesKeys(d));
}

String _formatCargoKeyForDisplay(String key) {
  final k = key.replaceAll('_', ' ').trim();
  if (k.isEmpty) return 'Cargo';
  return k.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}';
  }).join(' ');
}

/// Rótulo amigável do cargo para exibir no PDF / dropdown (pastor, secretário, cargos customizados).
String signatoryCargoDisplayLabel(Map<String, dynamic> d) {
  final funcoes = d['FUNCOES'];
  final funcaoSingle = (d['FUNCAO'] ?? d['funcao'] ?? d['CARGO'] ?? d['cargo'] ?? '').toString();
  final list = <String>[];
  if (funcoes is List) {
    for (final f in funcoes) {
      final s = normalizeMemberRoleKey((f ?? '').toString());
      if (s.isNotEmpty && !list.contains(s)) list.add(s);
    }
  }
  final one = normalizeMemberRoleKey(funcaoSingle);
  if (one.isNotEmpty && !list.contains(one)) list.add(one);

  if (list.any((s) => s == 'pastor' || s == 'pastora')) return 'Pastor(a)';
  if (list.contains('gestor')) return 'Gestor(a)';
  if (list.contains('secretario')) return 'Secretário(a)';
  if (list.contains('secretaria')) return 'Secretária(o)';
  if (list.contains('tesoureiro')) return 'Tesoureiro(a)';

  final leadership = list.where((s) => s != 'membro').toList();
  if (leadership.isNotEmpty) {
    return leadership.map(_formatCargoKeyForDisplay).join(', ');
  }
  if (list.isNotEmpty) return _formatCargoKeyForDisplay(list.first);
  return 'Liderança';
}

/// Lista de cargos possíveis para o signatário (usada quando a pessoa tem mais de uma função).
/// A UI escolhe um único cargo para exibir no certificado.
List<String> signatoryCargoDisplayOptions(Map<String, dynamic> d) {
  final funcoes = extractMemberFuncoesKeys(d);
  final out = <String>[];
  for (final f in funcoes) {
    final n = normalizeMemberRoleKey(f);
    if (n.isEmpty || n == 'membro') continue;
    String label;
    if (n == 'pastor') {
      label = 'Pastor';
    } else if (n == 'pastora') {
      label = 'Pastora';
    } else if (n == 'adm') {
      label = 'Adm';
    } else if (n == 'gestor') {
      label = 'Gestor(a)';
    } else if (n == 'secretario') {
      label = 'Secretário(a)';
    } else if (n == 'secretaria') {
      label = 'Secretária(o)';
    } else if (n == 'tesoureiro') {
      label = 'Tesoureiro(a)';
    } else {
      label = _formatCargoKeyForDisplay(n);
    }
    if (!out.contains(label)) out.add(label);
  }
  if (out.isNotEmpty) return out;
  return [signatoryCargoDisplayLabel(d)];
}
