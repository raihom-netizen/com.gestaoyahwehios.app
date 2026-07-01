// Regras compartilhadas: campo de assinatura e signatários oficiais (certificados, carteirinha, PDFs).
// Apenas pastor, gestor, secretário, tesoureiro, administrador ou líder de departamento.

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
///
/// Se [FUNCOES] existir só como `["membro"]` mas a ficha tiver [CARGO]/[FUNCAO] de liderança,
/// usa o cargo da ficha — evita lista vazia de signatários em certificados/carteirinha.
List<String> extractMemberFuncoesKeys(Map<String, dynamic> d) {
  final funcoesRaw = d['FUNCOES'] ?? d['funcoes'];
  var keys = <String>[];
  if (funcoesRaw is List) {
    keys = funcoesRaw
        .map((e) => (e ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final single = (d['FUNCAO'] ??
          d['funcao'] ??
          d['CARGO'] ??
          d['cargo'] ??
          d['role'] ??
          '')
      .toString()
      .trim();
  if (single.isNotEmpty) {
    if (keys.isEmpty) {
      keys = [single];
    } else {
      final norms = keys.map(normalizeMemberRoleKey).toList();
      final onlyMembro = keys.length == 1 &&
          norms.length == 1 &&
          norms.first == 'membro';
      final singleNorm = normalizeMemberRoleKey(single);
      if (onlyMembro && singleNorm != 'membro') {
        keys = [single];
      } else if (!onlyMembro &&
          singleNorm.isNotEmpty &&
          !norms.contains(singleNorm)) {
        keys = [...keys, single];
      }
    }
  }
  if (keys.isEmpty) {
    keys = ['membro'];
  }
  return keys;
}

/// `true` se o membro pode cadastrar assinatura (mesmos cargos dos documentos oficiais).
bool memberNeedsAssinaturaFieldFromFuncoes(List<String> funcoes) =>
    memberHasLeadershipForAssinatura({'FUNCOES': funcoes});

/// Cargos que podem assinar documentos oficiais (carteirinha, certificados, PDFs).
const Set<String> kChurchDocumentSignatoryRoleKeys = {
  'gestor',
  'pastor',
  'pastora',
  'pastor_auxiliar',
  'pastor_presidente',
  'pastor_president',
  'secretario',
  'secretaria',
  'tesoureiro',
  'tesouraria',
  'administrador',
  'admin',
  'adm',
  'lider_departamento',
  'lider_de_departamento',
  'liderdepartamento',
};

bool _roleKeyCanSignDocuments(String normalizedKey) {
  if (normalizedKey.isEmpty || normalizedKey == 'membro') return false;
  if (kChurchDocumentSignatoryRoleKeys.contains(normalizedKey)) return true;
  if (normalizedKey.contains('pastor')) return true;
  if (normalizedKey.contains('gestor')) return true;
  if (normalizedKey.contains('administr')) return true;
  if (normalizedKey == 'adm' || normalizedKey == 'admin') return true;
  if (normalizedKey.contains('lider') &&
      (normalizedKey.contains('depart') || normalizedKey.contains('dept'))) {
    return true;
  }
  if (normalizedKey.contains('tesour')) return true;
  if (normalizedKey.contains('secretar')) return true;
  return false;
}

/// Campo de assinatura na ficha — mesmos cargos elegíveis que documentos oficiais.
bool memberHasLeadershipForAssinatura(Map<String, dynamic> d) =>
    memberCanSignChurchDocuments(d);

/// Prioridade na lista de assinantes — menor = mais alto (pastor primeiro).
int signatoryRoleSortPriority(Map<String, dynamic> d) {
  final keys = extractMemberFuncoesKeys(d)
      .map(normalizeMemberRoleKey)
      .where((k) => k.isNotEmpty && k != 'membro')
      .toList();
  final cargo = normalizeMemberRoleKey(
    (d['FUNCAO'] ?? d['funcao'] ?? d['CARGO'] ?? d['cargo'] ?? '')
        .toString(),
  );
  if (cargo.isNotEmpty && !keys.contains(cargo)) keys.add(cargo);

  bool any(bool Function(String k) test) => keys.any(test);

  if (any((k) => k.contains('pastor'))) return 0;
  if (any((k) => k.contains('gestor') || k.contains('presidente'))) return 10;
  if (any((k) => k.contains('secretar'))) return 20;
  if (any((k) => k.contains('tesour'))) return 30;
  if (any((k) =>
      k.contains('administr') || k == 'adm' || k == 'admin')) {
    return 40;
  }
  if (any((k) => k.contains('lider'))) return 50;
  return 90;
}

bool memberHasPastorRole(Map<String, dynamic> d) {
  for (final f in extractMemberFuncoesKeys(d)) {
    if (normalizeMemberRoleKey(f).contains('pastor')) return true;
  }
  return normalizeMemberRoleKey(
    (d['FUNCAO'] ?? d['funcao'] ?? d['CARGO'] ?? d['cargo'] ?? '')
        .toString(),
  ).contains('pastor');
}

/// Ordena assinantes — pastor no topo, depois gestor/secretário/etc.
int compareSignatoriesPastorFirst(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final pa = signatoryRoleSortPriority(a);
  final pb = signatoryRoleSortPriority(b);
  if (pa != pb) return pa.compareTo(pb);
  final na = (a['NOME_COMPLETO'] ?? a['nome'] ?? a['name'] ?? '')
      .toString()
      .toLowerCase();
  final nb = (b['NOME_COMPLETO'] ?? b['nome'] ?? b['name'] ?? '')
      .toString()
      .toLowerCase();
  return na.compareTo(nb);
}

/// Pastor, gestor, secretário, tesoureiro, administrador ou líder de departamento.
bool memberCanSignChurchDocuments(Map<String, dynamic> d) {
  for (final f in extractMemberFuncoesKeys(d)) {
    if (_roleKeyCanSignDocuments(normalizeMemberRoleKey(f))) return true;
  }
  final cargoSingle = normalizeMemberRoleKey(
    (d['FUNCAO'] ?? d['funcao'] ?? d['CARGO'] ?? d['cargo'] ?? '').toString(),
  );
  if (_roleKeyCanSignDocuments(cargoSingle)) return true;

  final ex = d['certificadoSignatario'] ?? d['podeAssinarCertificado'];
  if (ex == true) {
    for (final f in extractMemberFuncoesKeys(d)) {
      if (_roleKeyCanSignDocuments(normalizeMemberRoleKey(f))) return true;
    }
    return _roleKeyCanSignDocuments(cargoSingle);
  }
  return false;
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
  if (list.contains('administrador') ||
      list.contains('admin') ||
      list.contains('adm')) {
    return 'Administrador(a)';
  }
  if (list.contains('gestor')) return 'Gestor(a)';
  if (list.contains('secretario')) return 'Secretário(a)';
  if (list.contains('secretaria')) return 'Secretária(o)';
  if (list.contains('tesoureiro') || list.contains('tesouraria')) {
    return 'Tesoureiro(a)';
  }

  final leadership = list.where((s) => s != 'membro').toList();
  if (leadership.isNotEmpty) {
    return _formatCargoKeyForDisplay(leadership.first);
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
    if (!_roleKeyCanSignDocuments(n)) continue;
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
    } else if (n == 'tesouraria') {
      label = 'Tesoureiro(a)';
    } else {
      label = _formatCargoKeyForDisplay(n);
    }
    if (!out.contains(label)) out.add(label);
  }
  if (out.isNotEmpty) return out;
  return [signatoryCargoDisplayLabel(d)];
}
