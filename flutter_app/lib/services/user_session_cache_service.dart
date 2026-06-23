import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_document_memory_cache.dart';

/// Cache do utilizador logado (`users/{uid}`) — evita leituras repetidas no painel.
abstract final class UserSessionCacheService {
  UserSessionCacheService._();

  static String? get _uid => firebaseDefaultAuth.currentUser?.uid;

  static String _path(String uid) => 'users/$uid';

  static Future<Map<String, dynamic>?> readUserDoc({bool forceRefresh = false}) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    final path = _path(uid);
    if (forceRefresh) {
      FirestoreDocumentMemoryCache.instance.invalidate(path);
    }
    return cachedFirestoreDoc(
      documentPath: path,
      ttl: const Duration(minutes: 10),
      fetcher: () async {
        final snap = await firebaseDefaultFirestore.doc(path).get();
        if (!snap.exists) return null;
        return snap.data();
      },
    );
  }

  static void invalidateCurrentUser() {
    final uid = _uid;
    if (uid != null) {
      FirestoreDocumentMemoryCache.instance.invalidate(_path(uid));
    }
  }
}
