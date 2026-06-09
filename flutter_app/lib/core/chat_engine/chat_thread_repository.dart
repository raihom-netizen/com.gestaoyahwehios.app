import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/chat_engine/chat_engine_audit.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_message_payload.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Threads / grupos — `igrejas/{churchId}/chats`.
abstract final class ChatThreadRepository {
  ChatThreadRepository._();

  static CollectionReference<Map<String, dynamic>> _chatsCol(String churchId) =>
      ChurchFirestoreAccess.collectionRef(churchId, 'chats');

  static DocumentReference<Map<String, dynamic>> threadRef(
    String churchId,
    String chatId,
  ) =>
      _chatsCol(churchId).doc(chatId);

  static Query<Map<String, dynamic>> threadsForUser({
    required String churchId,
    required String uid,
    int? limit,
  }) =>
      _chatsCol(churchId)
          .where('participantUids', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(limit ?? FirebasePerformanceLimits.chatThreadsPage);

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchThreadsForUser({
    required String churchId,
    required String uid,
    int? limit,
  }) =>
      FirestoreStreamUtils.queryWatchBootstrap(
        threadsForUser(churchId: churchId, uid: uid, limit: limit),
      );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchThread({
    required String churchId,
    required String chatId,
  }) =>
      FirestoreStreamUtils.documentWatchBootstrap(threadRef(churchId, chatId));

  static Future<ChatThread?> getThread({
    required String churchId,
    required String chatId,
  }) async {
    final snap = await threadRef(churchId, chatId).get();
    if (!snap.exists) return null;
    return ChatThread.fromDoc(churchId, snap);
  }

  static Future<void> patchLastMessage({
    required String churchId,
    required String chatId,
    required String preview,
    required String type,
    required String senderId,
  }) async {
    await threadRef(churchId, chatId).set(
      ChatMessagePayload.threadLastMessagePatch(
        preview: preview,
        type: type,
        senderId: senderId,
      ),
      SetOptions(merge: true),
    );
  }

  static Future<String> createGroup({
    required String churchId,
    required String nome,
    required List<String> participants,
    required List<String> admins,
    String? foto,
  }) async {
    final sw = ChatEngineAudit.start('create_group');
    final now = FieldValue.serverTimestamp();
    final ref = await _chatsCol(churchId).add({
      'tipo': 'grupo',
      'type': 'group',
      'nome': nome,
      'name': nome,
      if (foto != null) 'foto': foto,
      'participants': participants,
      'participantUids': participants,
      'admins': admins,
      'memberCount': participants.length,
      'createdAt': now,
      'updatedAt': now,
      'hasConversation': false,
    });
    ChatEngineAudit.end(sw);
    return ref.id;
  }

  static Future<void> updateGroup({
    required String churchId,
    required String chatId,
    String? nome,
    String? foto,
    List<String>? participants,
    List<String>? admins,
  }) async {
    final patch = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (nome != null) {
      patch['nome'] = nome;
      patch['name'] = nome;
    }
    if (foto != null) patch['foto'] = foto;
    if (participants != null) {
      patch['participants'] = participants;
      patch['participantUids'] = participants;
      patch['memberCount'] = participants.length;
    }
    if (admins != null) patch['admins'] = admins;
    await threadRef(churchId, chatId).set(patch, SetOptions(merge: true));
  }

  static Future<void> removeMember({
    required String churchId,
    required String chatId,
    required String uid,
  }) async {
    await threadRef(churchId, chatId).update({
      'participants': FieldValue.arrayRemove([uid]),
      'participantUids': FieldValue.arrayRemove([uid]),
      'memberCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> promoteAdmin({
    required String churchId,
    required String chatId,
    required String uid,
  }) async {
    await threadRef(churchId, chatId).update({
      'admins': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Excluir da lista do utilizador — histórico preservado para outros.
  static Future<void> hideThreadForUser({
    required String churchId,
    required String chatId,
    required String uid,
  }) async {
    await threadRef(churchId, chatId).set(
      {'hiddenForUids': FieldValue.arrayUnion([uid])},
      SetOptions(merge: true),
    );
  }

  /// Apagar grupo para todos — só admins (validação nas rules).
  static Future<void> deleteGroupForEveryone({
    required String churchId,
    required String chatId,
    required String actorUid,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => threadRef(churchId, chatId).delete(),
      );
      return;
    }
    await threadRef(churchId, chatId).delete();
    await ChurchFirestoreAccess.collectionRef(churchId, 'chat_audit').add({
      'action': 'group_deleted',
      'chatId': chatId,
      'actorUid': actorUid,
      'at': FieldValue.serverTimestamp(),
    });
  }
}
