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

  static bool memberIsLeaderOfDepartment(
    Map<String, dynamic>? deptData,
    String memberCpfDigits,
  ) {
    final m = canonicalCpfDigits(_normCpf(memberCpfDigits));
    if (m.length != 11) return false;
    return cpfsFromDepartmentData(deptData).contains(m);
  }
}
