import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'church_chat_member_prefs.dart';

/// Chat entre membros / grupos por departamento — retenção: texto 30 dias, mídia 3 dias.
class ChurchChatService {
  ChurchChatService._();

  static const Duration textRetention = Duration(days: 30);
  static const Duration mediaRetention = Duration(days: 3);

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String dmThreadId(String uidA, String uidB) {
    final a = uidA.compareTo(uidB) < 0 ? uidA : uidB;
    final b = uidA.compareTo(uidB) < 0 ? uidB : uidA;
    return 'dm_${a}_$b';
  }

  static String deptThreadId(String departmentId) => 'dept_$departmentId';

  static DocumentReference<Map<String, dynamic>> threadRef(
      String tenantId, String threadId) {
    return _db
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_threads')
        .doc(threadId);
  }

  static CollectionReference<Map<String, dynamic>> messagesCol(
      String tenantId, String threadId) {
    return threadRef(tenantId, threadId).collection('messages');
  }

  /// Sincroniza departamentos do membro para as regras Firestore (`users_profile_chat`).
  static Future<void> syncUserChatProfile({
    required String tenantId,
    required List<String> departmentIds,
    String? memberDocId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    await _db
        .collection('igrejas')
        .doc(tid)
        .collection('users_profile_chat')
        .doc(uid)
        .set(
          {
            'uid': uid,
            'departmentIds': departmentIds,
            if (memberDocId != null && memberDocId.isNotEmpty)
              'memberDocId': memberDocId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
  }

  static Future<void> touchPresence(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_presence')
        .doc(uid)
        .set(
          {'lastSeenAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
  }

  static bool isOnlineFromSnapshot(DocumentSnapshot<Map<String, dynamic>>? snap) {
    final ts = snap?.data()?['lastSeenAt'];
    if (ts is! Timestamp) return false;
    return DateTime.now().difference(ts.toDate()).inSeconds < 45;
  }

  static Future<void> ensureDepartmentThread({
    required String tenantId,
    required String departmentId,
    required String departmentName,
    required List<String> participantUids,
  }) async {
    final id = deptThreadId(departmentId);
    final ref = threadRef(tenantId, id);
    await ref.set(
      {
        'type': 'department',
        'departmentId': departmentId,
        'title': departmentName,
        'participantUids': participantUids.toSet().toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> ensureDmThread({
    required String tenantId,
    required String uidA,
    required String uidB,
    required String titleA,
    required String titleB,
  }) async {
    final id = dmThreadId(uidA, uidB);
    await threadRef(tenantId, id).set(
      {
        'type': 'dm',
        'participantUids': [uidA, uidB],
        'titlesByUid': {uidA: titleA, uidB: titleB},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<bool> sendTextMessage({
    required String tenantId,
    required String threadId,
    required String text,
  }) async {
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tenantId,
      threadId: threadId,
    )) {
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(textRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    await msgRef.set({
      'senderUid': uid,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview':
            text.length > 120 ? '${text.substring(0, 117)}…' : text,
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  static Future<bool> sendMediaMessage({
    required String tenantId,
    required String threadId,
    required String downloadUrl,
    required String storagePath,
    required String kind,
  }) async {
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tenantId,
      threadId: threadId,
    )) {
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    await msgRef.set({
      'senderUid': uid,
      'type': kind,
      'mediaUrl': downloadUrl,
      'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': kind == 'audio'
            ? '🎤 Áudio'
            : (kind == 'video' ? '🎬 Vídeo' : '📷 Foto'),
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// Devolve URL pública após upload.
  static Future<({String url, String path})> uploadChatBytes({
    required String tenantId,
    required String threadId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'igrejas/$tenantId/chat_media/$threadId/${uid}_${ts}_$safeName';
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return (url: url, path: path);
  }

  static Future<void> hideThreadForMe({
    required String tenantId,
    required String threadId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await threadRef(tenantId, threadId).set(
      {
        'hiddenForUids': FieldValue.arrayUnion([uid]),
      },
      SetOptions(merge: true),
    );
  }
}
