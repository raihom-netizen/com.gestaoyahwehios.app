import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';

/// Interações sociais em `igrejas/{tenantId}/noticias|avisos/{postId}`:
/// — subcoleções `curtidas` e `confirmacoes` (documento por uid)
/// — campos legados no pai: `likes`, `rsvp`, contadores `likesCount`, `rsvpCount`
class NoticiaSocialService {
  NoticiaSocialService._();

  static DocumentReference<Map<String, dynamic>> _post(
    String tenantId,
    String postId, {
    String parentCollection = ChurchTenantPostsCollections.noticias,
  }) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection(parentCollection)
          .doc(postId);

  /// Alterna curtida (otimista: atualize UI antes/depois do await).
  static Future<void> toggleCurtida({
    required String tenantId,
    required String postId,
    required String uid,
    required String memberName,
    String photoUrl = '',
    required bool currentlyLiked,
    String parentCollection = ChurchTenantPostsCollections.noticias,
  }) async {
    final postRef = _post(tenantId, postId, parentCollection: parentCollection);
    final likeRef = postRef.collection('curtidas').doc(uid);
    final batch = FirebaseFirestore.instance.batch();
    if (currentlyLiked) {
      batch.delete(likeRef);
      batch.update(postRef, {
        'likes': FieldValue.arrayRemove([uid]),
        'likedBy': FieldValue.arrayRemove([uid]),
        'likesCount': FieldValue.increment(-1),
      });
    } else {
      batch.set(likeRef, {
        'uid': uid,
        'memberName': memberName,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'likes': FieldValue.arrayUnion([uid]),
        'likedBy': FieldValue.arrayUnion([uid]),
        'likesCount': FieldValue.increment(1),
      });
    }
    await batch.commit();
  }

  /// RSVP / confirmar presença (apenas eventos no UI; pode existir no doc).
  static Future<void> toggleConfirmacaoPresenca({
    required String tenantId,
    required String postId,
    required String uid,
    required String memberName,
    String photoUrl = '',
    required bool currentlyConfirmed,
    String parentCollection = ChurchTenantPostsCollections.noticias,
  }) async {
    final postRef = _post(tenantId, postId, parentCollection: parentCollection);
    final confRef = postRef.collection('confirmacoes').doc(uid);
    final batch = FirebaseFirestore.instance.batch();
    if (currentlyConfirmed) {
      batch.delete(confRef);
      batch.update(postRef, {
        'rsvp': FieldValue.arrayRemove([uid]),
        'rsvpCount': FieldValue.increment(-1),
      });
    } else {
      batch.set(confRef, {
        'uid': uid,
        'memberName': memberName,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'rsvp': FieldValue.arrayUnion([uid]),
        'rsvpCount': FieldValue.increment(1),
      });
    }
    await batch.commit();
  }

  /// Mescla `likes` e legado `likedBy` para exibição.
  static List<String> mergedLikeUids(Map<String, dynamic> data) {
    final out = <String>[];
    void addFrom(dynamic list) {
      if (list is! List) return;
      for (final e in list) {
        final s = e.toString();
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
    }

    addFrom(data['likes']);
    addFrom(data['likedBy']);
    return out;
  }

  static int likeDisplayCount(Map<String, dynamic> data, List<String> mergedUids) {
    final n = data['likesCount'];
    if (n is num && n > 0) return n.toInt();
    return mergedUids.length;
  }

  static int rsvpDisplayCount(Map<String, dynamic> data, List<String> rsvpUids) {
    final n = data['rsvpCount'];
    if (n is num && n > 0) return n.toInt();
    return rsvpUids.length;
  }
}
