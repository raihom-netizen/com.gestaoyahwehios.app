/// Nomes no YahwehChat — nunca exibir UID Firebase como título de contacto.
abstract final class ChurchChatDisplayName {
  ChurchChatDisplayName._();

  static const String fallbackMember = 'Membro';

  static bool looksLikeFirebaseUid(String raw) {
    final s = raw.trim();
    if (s.length < 20 || s.length > 128) return false;
    if (s.contains('@') || s.contains(' ')) return false;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s);
  }

  static String sanitize(String raw) {
    final t = raw.trim();
    if (t.isEmpty || looksLikeFirebaseUid(t) || t == 'null') {
      return '';
    }
    return t;
  }

  static String fromMemberData(
    Map<String, dynamic> data, {
    String? authUid,
    String? memberDocId,
  }) {
    final nome = sanitize(
      (data['NOME_COMPLETO'] ??
              data['nome'] ??
              data['name'] ??
              data['displayName'] ??
              '')
          .toString(),
    );
    if (nome.isNotEmpty) return nome;
    final uid = (authUid ?? data['authUid'] ?? data['firebaseUid'] ?? '')
        .toString()
        .trim();
    if (uid.isNotEmpty && !looksLikeFirebaseUid(uid)) {
      return sanitize(uid);
    }
    final doc = (memberDocId ?? '').trim();
    if (doc.isNotEmpty && !looksLikeFirebaseUid(doc)) {
      return 'Membro · ${doc.length > 8 ? doc.substring(doc.length - 4) : doc}';
    }
    return fallbackMember;
  }

  static String peerTitle({
    required String peerUid,
    String? fromMemberName,
    String? fromThreadTitle,
    String? fromLocalCache,
  }) {
    for (final candidate in [
      fromMemberName,
      fromThreadTitle,
      fromLocalCache,
    ]) {
      final s = sanitize(candidate ?? '');
      if (s.isNotEmpty) return s;
    }
    if (peerUid.isNotEmpty && !looksLikeFirebaseUid(peerUid)) {
      return sanitize(peerUid);
    }
    return fallbackMember;
  }
}
