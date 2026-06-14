/// Normalização de líderes de departamento no Firestore.
///
/// Canónico: [leaderCpfs] — lista de CPFs só dígitos (vários líderes).
/// Legado: [leaderCpf] + [viceLeaderCpf] — mantidos ao gravar para compatibilidade.
library;

abstract final class ChurchDepartmentLeaders {
  ChurchDepartmentLeaders._();

  static String _normCpf(Object? raw) {
    return (raw ?? '').toString().replaceAll(RegExp(r'\D'), '');
  }

  /// CPF canónico para chave (Firestore às vezes grava sem zeros à esquerda).
  static String canonicalCpfDigits(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (d.length > 11) return d.substring(d.length - 11);
    if (d.length < 11) return d.padLeft(11, '0');
    return d;
  }

  /// CPFs dos líderes (normalizados a 11 dígitos quando possível), sem duplicar.
  static List<String> cpfsFromDepartmentData(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['leaderCpfs'] ??
        data['leader_cpfs'] ??
        data['liderCpfs'] ??
        data['lider_cpfs'];
    final out = <String>[];
    void add(Object? v) {
      final x = _normCpf(v);
      if (x.isEmpty) return;
      if (x.length >= 9 && x.length <= 11) {
        final c = canonicalCpfDigits(x);
        if (!out.contains(c)) out.add(c);
      }
    }
    if (raw is List) {
      for (final e in raw) {
        add(e);
      }
    }
    add(data['leaderCpf']);
    add(data['leader_cpf']);
    add(data['LIDER_CPF']);
    add(data['liderCpf']);
    add(data['lider_cpf']);
    add(data['viceLeaderCpf']);
    add(data['vice_leader_cpf']);
    add(data['viceLiderCpf']);
    return out;
  }

  /// UIDs Firebase em campos legados / bootstrap (`leaderUid` no preset).
  static List<String> leaderUidsFromDepartmentData(Map<String, dynamic>? data) {
    if (data == null) return [];
    final out = <String>[];
    void addUid(Object? v) {
      final s = (v ?? '').toString().trim();
      if (s.length >= 8 && !out.contains(s)) out.add(s);
    }
    final raw = data['leaderUids'] ?? data['leader_uids'];
    if (raw is List) {
      for (final e in raw) {
        addUid(e);
      }
    }
    addUid(data['leaderUid']);
    addUid(data['leader_uid']);
    addUid(data['viceLeaderUid']);
    addUid(data['vice_leader_uid']);
    return out;
  }

  /// Campos a gravar no doc do departamento (lista + legado).
  static Map<String, dynamic> firestoreFieldsFromCpfs(List<String> cpfs) {
    final clean = <String>[];
    for (final c in cpfs) {
      final d = _normCpf(c);
      if (d.length >= 9 && d.length <= 11) {
        final cc = canonicalCpfDigits(d);
        if (!clean.contains(cc)) clean.add(cc);
      }
    }
    return <String, dynamic>{
      'leaderCpfs': clean,
      'leaderCpf': clean.isNotEmpty ? clean.first : '',
      'viceLeaderCpf': clean.length > 1 ? clean[1] : '',
    };
  }

  /// Denormalização — exibir líder na lista sem join com `membros`.
  static const String leaderNameField = 'leaderName';
  static const String leaderFotoUrlField = 'leaderFotoUrl';

  static String leaderNameFromDepartmentData(Map<String, dynamic>? data) =>
      (data?[leaderNameField] ?? '').toString().trim();

  static String leaderFotoUrlFromDepartmentData(Map<String, dynamic>? data) =>
      (data?[leaderFotoUrlField] ?? '').toString().trim();

  static String _memberDisplayNameFromData(Map<String, dynamic> data) {
    for (final k in [
      'NOME_COMPLETO',
      'nome',
      'name',
      'displayName',
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _memberPhotoUrlFromData(Map<String, dynamic> data) {
    for (final k in [
      'fotoThumbUrl',
      'fotoUrl',
      'photoUrl',
      'FOTO_URL',
      'foto',
      'imageUrl',
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Resolve nome/foto do 1.º líder encontrado nos mapas locais.
  static Map<String, dynamic> denormalizedLeaderFieldsFromCpfs(
    List<String> leaderCpfs, {
    Map<String, Map<String, dynamic>>? memberDataByCpf,
    Map<String, String>? nameByCpf,
  }) {
    final clean = cpfsFromDepartmentData(<String, dynamic>{
      'leaderCpfs': leaderCpfs,
    });
    var name = '';
    var foto = '';
    for (final cpf in clean) {
      final member = memberDataByCpf?[cpf];
      if (member != null) {
        final n = _memberDisplayNameFromData(member);
        final f = _memberPhotoUrlFromData(member);
        if (n.isNotEmpty) name = n;
        if (f.isNotEmpty) foto = f;
        if (name.isNotEmpty || foto.isNotEmpty) break;
      }
      final cachedName = (nameByCpf?[cpf] ?? '').trim();
      if (cachedName.isNotEmpty && name.isEmpty) name = cachedName;
      if (name.isNotEmpty && foto.isNotEmpty) break;
    }
    return <String, dynamic>{
      leaderNameField: name,
      leaderFotoUrlField: foto,
    };
  }

  /// CPFs + campos denormalizados — gravar num único `update`/`set`.
  static Map<String, dynamic> firestoreLeaderPayloadFromCpfs(
    List<String> cpfs, {
    Map<String, Map<String, dynamic>>? memberDataByCpf,
    Map<String, String>? nameByCpf,
  }) {
    return <String, dynamic>{
      ...firestoreFieldsFromCpfs(cpfs),
      ...denormalizedLeaderFieldsFromCpfs(
        cpfs,
        memberDataByCpf: memberDataByCpf,
        nameByCpf: nameByCpf,
      ),
    };
  }

  static bool memberIsLeaderOfDepartment(
    Map<String, dynamic>? deptData,
    String memberCpfDigits,
  ) {
    final m = canonicalCpfDigits(_normCpf(memberCpfDigits));
    if (m.length != 11) return false;
    return cpfsFromDepartmentData(deptData).contains(m);
  }
}
