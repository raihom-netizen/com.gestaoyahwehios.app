import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Preferências por utilizador na igreja: favoritos, silenciar conversa, bloquear contacto (DM).
/// Firestore: `igrejas/{tenantId}/chat_member_prefs/{uid}`.
class ChurchChatMemberPrefsModel {
  final List<String> favoriteThreadIds;
  final List<String> mutedThreadIds;
  final List<String> blockedPeerUids;

  const ChurchChatMemberPrefsModel({
    this.favoriteThreadIds = const [],
    this.mutedThreadIds = const [],
    this.blockedPeerUids = const [],
  });

  bool isFavorite(String threadId) => favoriteThreadIds.contains(threadId);
  bool isMutedThread(String threadId) => mutedThreadIds.contains(threadId);
  bool isBlockedPeer(String peerUid) =>
      peerUid.isNotEmpty && blockedPeerUids.contains(peerUid);
}

class ChurchChatMemberPrefs {
  ChurchChatMemberPrefs._();

  /// Máximo de conversas favoritas (grupos + DM) por utilizador.
  static const int maxFavoriteThreads = 5;

  static DocumentReference<Map<String, dynamic>> docRef(
    String tenantId,
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_member_prefs')
        .doc(uid);
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String tenantId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return docRef(tenantId, uid).snapshots();
  }

  static ChurchChatMemberPrefsModel parse(
    DocumentSnapshot<Map<String, dynamic>>? snap,
  ) {
    final d = snap?.data();
    return ChurchChatMemberPrefsModel(
      favoriteThreadIds: _stringList(d?['favoriteThreadIds']),
      mutedThreadIds: _stringList(d?['mutedThreadIds']),
      blockedPeerUids: _stringList(d?['blockedPeerUids']),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  static Future<ChurchChatMemberPrefsModel> load(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const ChurchChatMemberPrefsModel();
    final snap = await docRef(tenantId, uid).get();
    return parse(snap);
  }

  /// Remove favorito: sempre `true`. Adicionar: `false` se já existirem [maxFavoriteThreads] favoritos.
  static Future<bool> setFavorite({
    required String tenantId,
    required String threadId,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (value) {
      final cur = await load(tenantId);
      final ids = cur.favoriteThreadIds.toSet();
      if (!ids.contains(threadId) && ids.length >= maxFavoriteThreads) {
        return false;
      }
    }
    await docRef(tenantId, uid).set(
      {
        'favoriteThreadIds': value
            ? FieldValue.arrayUnion([threadId])
            : FieldValue.arrayRemove([threadId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  static Future<void> setMutedThread({
    required String tenantId,
    required String threadId,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await docRef(tenantId, uid).set(
      {
        'mutedThreadIds': value
            ? FieldValue.arrayUnion([threadId])
            : FieldValue.arrayRemove([threadId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setBlockedPeer({
    required String tenantId,
    required String peerUid,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await docRef(tenantId, uid).set(
      {
        'blockedPeerUids': value
            ? FieldValue.arrayUnion([peerUid])
            : FieldValue.arrayRemove([peerUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// DM: não enviar se bloqueou o interlocutor.
  static Future<bool> canSendToDmThread({
    required String tenantId,
    required String threadId,
  }) async {
    if (!threadId.startsWith('dm_')) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final thread =
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tenantId)
            .collection('chat_threads')
            .doc(threadId)
            .get();
    final peers = thread.data()?['participantUids'];
    if (peers is! List) return true;
    String peer = '';
    for (final p in peers) {
      if (p.toString() != uid) peer = p.toString();
    }
    if (peer.isEmpty) return true;
    final prefs = await load(tenantId);
    return !prefs.isBlockedPeer(peer);
  }
}
