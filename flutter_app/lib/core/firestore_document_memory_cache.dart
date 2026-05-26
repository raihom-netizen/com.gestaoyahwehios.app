import 'dart:async';

/// Cache em memória de documentos Firestore (evita `users/uid` repetido na sessão).
///
/// TTL curto — dados de perfil; invalidar após updates explícitos.
class FirestoreDocumentMemoryCache {
  FirestoreDocumentMemoryCache._();
  static final FirestoreDocumentMemoryCache instance =
      FirestoreDocumentMemoryCache._();

  static const Duration defaultTtl = Duration(minutes: 8);

  final Map<String, _Entry> _map = {};

  String _key(String path) => path.trim();

  Map<String, dynamic>? getIfFresh(String documentPath) {
    final e = _map[_key(documentPath)];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > e.ttl) {
      _map.remove(_key(documentPath));
      return null;
    }
    return Map<String, dynamic>.from(e.data);
  }

  void put(String documentPath, Map<String, dynamic> data, {Duration? ttl}) {
    _map[_key(documentPath)] = _Entry(
      Map<String, dynamic>.from(data),
      DateTime.now(),
      ttl ?? defaultTtl,
    );
  }

  void invalidate(String documentPath) {
    _map.remove(_key(documentPath));
  }

  void invalidatePrefix(String pathPrefix) {
    final p = pathPrefix.trim();
    _map.removeWhere((k, _) => k.startsWith(p));
  }

  void clear() => _map.clear();
}

class _Entry {
  _Entry(this.data, this.at, this.ttl);
  final Map<String, dynamic> data;
  final DateTime at;
  final Duration ttl;
}

/// Obtém dados com cache; [fetcher] só corre se não houver entrada válida.
Future<Map<String, dynamic>?> cachedFirestoreDoc({
  required String documentPath,
  required Future<Map<String, dynamic>?> Function() fetcher,
  Duration? ttl,
}) async {
  final cached =
      FirestoreDocumentMemoryCache.instance.getIfFresh(documentPath);
  if (cached != null) return cached;
  final fresh = await fetcher();
  if (fresh != null && fresh.isNotEmpty) {
    FirestoreDocumentMemoryCache.instance.put(
      documentPath,
      fresh,
      ttl: ttl,
    );
  }
  return fresh;
}
