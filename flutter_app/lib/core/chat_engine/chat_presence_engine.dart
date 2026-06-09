import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Presença — online, visto por último, digitando, gravando áudio.
abstract final class ChatPresenceEngine {
  ChatPresenceEngine._();

  static const Duration typingTtl = Duration(seconds: 8);

  static CollectionReference<Map<String, dynamic>> _presenceCol(String churchId) =>
      ChurchFirestoreAccess.collectionRef(churchId, 'chat_presence');

  static CollectionReference<Map<String, dynamic>> _typingCol(
    String churchId,
    String chatId,
  ) =>
      ChurchFirestoreAccess.collectionRef(churchId, 'chats')
          .doc(chatId)
          .collection('typing');

  static Future<void> setOnline({
    required String churchId,
    required String uid,
    bool online = true,
  }) async {
    await _presenceCol(churchId).doc(uid).set(
      {
        'online': online,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setTyping({
    required String churchId,
    required String chatId,
    required String uid,
    String preview = '',
    bool recordingAudio = false,
  }) async {
    await _typingCol(churchId, chatId).doc(uid).set(
      {
        'uid': uid,
        'preview': preview,
        'recordingAudio': recordingAudio,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await ChurchFirestoreAccess.collectionRef(churchId, 'chats')
        .doc(chatId)
        .set(
      {
        'typingUid': uid,
        'typingPreview': preview.isNotEmpty ? preview : 'A digitar…',
        'typingUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> clearTyping({
    required String churchId,
    required String chatId,
    required String uid,
  }) async {
    await _typingCol(churchId, chatId).doc(uid).delete();
    await ChurchFirestoreAccess.collectionRef(churchId, 'chats')
        .doc(chatId)
        .set(
      {
        'typingUid': FieldValue.delete(),
        'typingPreview': FieldValue.delete(),
        'typingUpdatedAt': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchPeerPresence({
    required String churchId,
    required String peerUid,
  }) =>
      FirestoreStreamUtils.documentWatchBootstrap(
        _presenceCol(churchId).doc(peerUid),
      );

  static String? typingLabelFromThreadData(
    Map<String, dynamic> threadData,
    String myUid, {
    Map<String, String>? namesByUid,
  }) {
    final typingUid = (threadData['typingUid'] ?? '').toString();
    if (typingUid.isEmpty || typingUid == myUid) return null;
    final ts = threadData['typingUpdatedAt'];
    if (ts is! Timestamp) return null;
    if (DateTime.now().difference(ts.toDate()) > typingTtl) return null;
    final name = namesByUid?[typingUid] ?? 'Alguém';
    final recording = threadData['recordingAudio'] == true;
    if (recording) return '$name está gravando áudio…';
    return '$name está digitando…';
  }

  static Future<void> markThreadRead({
    required String churchId,
    required String chatId,
    required String uid,
  }) async {
    await ChurchFirestoreAccess.collectionRef(churchId, 'chats')
        .doc(chatId)
        .set(
      {
        'lastSeenAtByUid.$uid': FieldValue.serverTimestamp(),
        'unreadCountByUid.$uid': 0,
      },
      SetOptions(merge: true),
    );
  }

  /// Online se `lastSeenAt` < 45s (mesma regra do hub legado).
  static bool isOnlineFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>>? snap,
  ) {
    final ts = snap?.data()?['lastSeenAt'];
    if (ts is! Timestamp) return false;
    return DateTime.now().difference(ts.toDate()).inSeconds < 45;
  }

  /// Presença em lote — evita N listeners na lista de conversas.
  static Future<Map<String, bool>> fetchOnlineMap({
    required String churchId,
    required Iterable<String> authUids,
  }) async {
    final id = churchId.trim();
    final uids = authUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (id.isEmpty || uids.isEmpty) return {};
    final out = <String, bool>{};
    const chunk = 12;
    for (var i = 0; i < uids.length; i += chunk) {
      final part = uids.sublist(
        i,
        i + chunk > uids.length ? uids.length : i + chunk,
      );
      final snaps = await Future.wait(
        part.map((uid) => _presenceCol(id).doc(uid).get()),
      );
      for (var j = 0; j < part.length; j++) {
        out[part[j]] = isOnlineFromSnapshot(snaps[j]);
      }
    }
    return out;
  }
}
