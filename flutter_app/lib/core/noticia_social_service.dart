import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Comentário leve para listagem no mural.
class MuralCommentItem {
  const MuralCommentItem({
    required this.id,
    required this.authorName,
    required this.text,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String authorName;
  final String text;
  final Timestamp? createdAt;
  final bool pending;

  factory MuralCommentItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final text = (d['text'] ?? d['texto'] ?? '').toString().trim();
    final name =
        (d['authorName'] ?? d['name'] ?? d['memberName'] ?? 'Membro')
            .toString()
            .trim();
    return MuralCommentItem(
      id: doc.id,
      authorName: name.isEmpty ? 'Membro' : name,
      text: text,
      createdAt: d['createdAt'] is Timestamp ? d['createdAt'] as Timestamp : null,
    );
  }
}

/// Interações sociais em `igrejas/{tenantId}/eventos|avisos/{postId}`:
/// — subcoleções `curtidas`, `comentarios` e `confirmacoes`
/// — campos legados no pai: `likes`, `rsvp`, contadores
class NoticiaSocialService {
  NoticiaSocialService._();

  static CollectionReference<Map<String, dynamic>> _commentsRef(
    DocumentReference<Map<String, dynamic>> postRef,
  ) =>
      postRef.collection('comentarios');

  static DocumentReference<Map<String, dynamic>> _post(
    String tenantId,
    String postId, {
    String parentCollection = ChurchTenantPostsCollections.eventos,
  }) =>
      ChurchOperationalPaths.churchDoc(tenantId)
          .collection(parentCollection)
          .doc(postId);

  /// Lista comentários — cache local primeiro; fallback sem `orderBy` se necessário.
  static Future<List<MuralCommentItem>> fetchComments(
    DocumentReference<Map<String, dynamic>> postRef, {
    int limit = 50,
  }) async {
    Future<List<MuralCommentItem>> orderedQuery() async {
      final q = _commentsRef(postRef)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await q
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (snap.docs.isEmpty) {
          snap = await q
              .get()
              .timeout(Duration(seconds: kIsWeb ? 12 : 8));
        }
      } catch (_) {
        snap = await q.get().timeout(Duration(seconds: kIsWeb ? 12 : 8));
      }
      return snap.docs.map(MuralCommentItem.fromDoc).toList();
    }

    Future<List<MuralCommentItem>> plainQuery() async {
      final snap = await _commentsRef(postRef)
          .limit(limit)
          .get()
          .timeout(Duration(seconds: kIsWeb ? 12 : 8));
      final items = snap.docs.map(MuralCommentItem.fromDoc).toList();
      items.sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return items;
    }

    Future<List<MuralCommentItem>> run() async {
      try {
        return await orderedQuery();
      } catch (_) {
        return plainQuery();
      }
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      return FirestoreWebGuard.runWithWebRecovery(run, maxAttempts: 3);
    }
    return run();
  }

  /// Grava comentário + incrementa contador no post (atómico via batch).
  static Future<void> addComment({
    required DocumentReference<Map<String, dynamic>> postRef,
    required String uid,
    required String authorName,
    required String text,
    String authorPhoto = '',
  }) async {
    final trimmed = text.trim();
    if (uid.isEmpty || trimmed.isEmpty) {
      throw ArgumentError('uid ou texto vazio.');
    }
    await ensureFirebaseReadyForChatSend();

    Future<void> write() async {
      final batch = firebaseDefaultFirestore.batch();
      final commentRef = _commentsRef(postRef).doc();
      batch.set(commentRef, {
        'authorUid': uid,
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'text': trimmed,
        'texto': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        postRef,
        {'commentsCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      await batch.commit();
    }

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
      await FirestoreWebGuard.runWithWebRecovery(write, maxAttempts: 3);
      return;
    }
    await write();
  }

  /// Curtida no documento exacto do feed (evita divergência de tenantId).
  static Future<void> toggleCurtidaOnPost({
    required DocumentReference<Map<String, dynamic>> postRef,
    required String uid,
    required String memberName,
    String photoUrl = '',
    required bool currentlyLiked,
  }) async {
    if (uid.isEmpty) throw ArgumentError('uid vazio.');
    await ensureFirebaseReadyForChatSend();

    final likeRef = postRef.collection('curtidas').doc(uid);
    final batch = firebaseDefaultFirestore.batch();
    if (currentlyLiked) {
      batch.delete(likeRef);
      batch.set(
        postRef,
        {
          'likes': FieldValue.arrayRemove([uid]),
          'likedBy': FieldValue.arrayRemove([uid]),
          'likesCount': FieldValue.increment(-1),
        },
        SetOptions(merge: true),
      );
    } else {
      batch.set(likeRef, {
        'uid': uid,
        'memberName': memberName,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        postRef,
        {
          'likes': FieldValue.arrayUnion([uid]),
          'likedBy': FieldValue.arrayUnion([uid]),
          'likesCount': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }

    Future<void> commit() => batch.commit();

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
      await FirestoreWebGuard.runWithWebRecovery(commit, maxAttempts: 3);
      return;
    }
    await commit();
  }

  /// Alterna curtida (legado — preferir [toggleCurtidaOnPost] com [postRef] do feed).
  static Future<void> toggleCurtida({
    required String tenantId,
    required String postId,
    required String uid,
    required String memberName,
    String photoUrl = '',
    required bool currentlyLiked,
    String parentCollection = ChurchTenantPostsCollections.eventos,
  }) =>
      toggleCurtidaOnPost(
        postRef: _post(tenantId, postId, parentCollection: parentCollection),
        uid: uid,
        memberName: memberName,
        photoUrl: photoUrl,
        currentlyLiked: currentlyLiked,
      );

  /// RSVP / confirmar presença (apenas eventos no UI; pode existir no doc).
  static Future<void> toggleConfirmacaoPresenca({
    required String tenantId,
    required String postId,
    required String uid,
    required String memberName,
    String photoUrl = '',
    required bool currentlyConfirmed,
    String parentCollection = ChurchTenantPostsCollections.eventos,
  }) async {
    final postRef = _post(tenantId, postId, parentCollection: parentCollection);
    final confRef = postRef.collection('confirmacoes').doc(uid);
    await ensureFirebaseReadyForChatSend();
    final batch = firebaseDefaultFirestore.batch();
    if (currentlyConfirmed) {
      batch.delete(confRef);
      batch.set(
        postRef,
        {
          'rsvp': FieldValue.arrayRemove([uid]),
          'rsvpCount': FieldValue.increment(-1),
        },
        SetOptions(merge: true),
      );
    } else {
      batch.set(confRef, {
        'uid': uid,
        'memberName': memberName,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        postRef,
        {
          'rsvp': FieldValue.arrayUnion([uid]),
          'rsvpCount': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }

    Future<void> commit() => batch.commit();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
      await FirestoreWebGuard.runWithWebRecovery(commit, maxAttempts: 3);
      return;
    }
    await commit();
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
