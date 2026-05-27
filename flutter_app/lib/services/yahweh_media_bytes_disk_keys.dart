/// Chaves estáveis para cache em disco (membros, mural, eventos).
abstract final class YahwehMediaBytesDiskKeys {
  YahwehMediaBytesDiskKeys._();

  static String member({required String storagePath, int revision = 0}) {
    final p = storagePath.trim();
    if (p.isEmpty) return '';
    if (revision > 0) return 'm:$p:r$revision';
    return 'm:$p';
  }

  static String feed({required String storagePath, int revision = 0}) {
    final p = storagePath.trim();
    if (p.isEmpty) return '';
    if (revision > 0) return 'f:$p:r$revision';
    return 'f:$p';
  }

  /// Legado (`p:path`) — leitura de entradas antigas.
  static String legacyProfilePathKey(String storagePath) {
    final p = storagePath.trim();
    if (p.isEmpty) return '';
    return 'p:$p';
  }

  static List<String> diskLookupKeys({
    required String? storagePath,
    int revision = 0,
    bool preferMemberScope = false,
  }) {
    final path = (storagePath ?? '').trim();
    if (path.isEmpty) return const [];
    final keys = <String>[];
    final isMember = preferMemberScope || path.contains('/membros/');
    if (isMember) {
      if (revision > 0) keys.add(member(storagePath: path, revision: revision));
      keys.add(member(storagePath: path));
      keys.add(legacyProfilePathKey(path));
    } else {
      if (revision > 0) keys.add(feed(storagePath: path, revision: revision));
      keys.add(feed(storagePath: path));
    }
    return keys.toSet().toList();
  }

  static String primaryWriteKey({
    required String? storagePath,
    int revision = 0,
    bool preferMemberScope = false,
  }) {
    final path = (storagePath ?? '').trim();
    if (path.isEmpty) return '';
    final isMember = preferMemberScope || path.contains('/membros/');
    if (isMember) return member(storagePath: path, revision: revision);
    return feed(storagePath: path, revision: revision);
  }

  static List<String> invalidateKeysForStoragePath(String storagePath) {
    final path = storagePath.trim();
    if (path.isEmpty) return const [];
    return [
      member(storagePath: path),
      legacyProfilePathKey(path),
      feed(storagePath: path),
    ];
  }
}

/// Revisão de cache para capas de avisos/eventos (troca de mídia no Firestore).
int feedMediaCacheRevisionFromPost(Map<String, dynamic> post) {
  for (final k in const [
    'mediaCacheRevision',
    'imageCacheRevision',
    'fotoUrlCacheRevision',
  ]) {
    final v = post[k];
    if (v is int && v > 0) return v;
    if (v is num) {
      final n = v.toInt();
      if (n > 0) return n;
    }
  }
  for (final k in const [
    'updatedAt',
    'editedAt',
    'publishedAt',
    'createdAt',
  ]) {
    final ms = _timestampLikeMillis(post[k]);
    if (ms != null && ms > 0) return ms;
  }
  return 0;
}

int? _timestampLikeMillis(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is int) {
    if (v > 1000000000000) return v;
    if (v > 1000000000) return v * 1000;
    return v;
  }
  if (v is num) {
    final n = v.toInt();
    if (n > 1000000000000) return n;
    if (n > 1000000000) return n * 1000;
    return n;
  }
  try {
    final dynamic d = v;
    final ms = d.millisecondsSinceEpoch;
    if (ms is int && ms > 0) return ms;
  } catch (_) {}
  return null;
}
