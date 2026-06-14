/// Denormalização — quem está orando (`orandoMembros`) no pedido de oração.
///
/// Evita lookup em `membros` só para avatares na lista.
abstract final class PrayerOrandoMembrosDenorm {
  PrayerOrandoMembrosDenorm._();

  static const String field = 'orandoMembros';

  static List<Map<String, dynamic>> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final uid = (m['uid'] ?? '').toString().trim();
      if (uid.isEmpty) continue;
      out.add(<String, dynamic>{
        'uid': uid,
        'nome': (m['nome'] ?? m['name'] ?? 'Membro').toString().trim(),
        'fotoUrl': (m['fotoUrl'] ?? m['photoUrl'] ?? '').toString().trim(),
      });
    }
    return out;
  }

  static Map<String, dynamic> entry({
    required String uid,
    required String nome,
    required String fotoUrl,
  }) {
    return <String, dynamic>{
      'uid': uid.trim(),
      'nome': nome.trim().isEmpty ? 'Membro' : nome.trim(),
      'fotoUrl': fotoUrl.trim(),
    };
  }

  static List<Map<String, dynamic>> upsert(
    List<Map<String, dynamic>> current, {
    required String uid,
    required String nome,
    required String fotoUrl,
  }) {
    final next = current.where((m) => m['uid'] != uid).toList();
    next.add(entry(uid: uid, nome: nome, fotoUrl: fotoUrl));
    return next;
  }

  static List<Map<String, dynamic>> removeUid(
    List<Map<String, dynamic>> current,
    String uid,
  ) =>
      current.where((m) => m['uid'] != uid).toList();

  static List<String> uidsFromMembros(List<Map<String, dynamic>> membros) =>
      membros.map((m) => (m['uid'] ?? '').toString()).where((u) => u.isNotEmpty).toList();
}
