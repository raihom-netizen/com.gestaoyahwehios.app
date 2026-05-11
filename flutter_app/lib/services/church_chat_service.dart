import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'church_chat_attachment_utils.dart';
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

  /// Biblioteca de figurinhas por igreja (`chat_stickers`).
  static CollectionReference<Map<String, dynamic>> stickersCol(
      String tenantId) {
    return _db.collection('igrejas').doc(tenantId).collection('chat_stickers');
  }

  /// Histórico por páginas no cliente (`limit` dinâmico na query).
  static const int defaultMessagePageSize = 50;

  static CollectionReference<Map<String, dynamic>> typingCol(
      String tenantId, String threadId) {
    return threadRef(tenantId, threadId).collection('typing');
  }

  /// Indicador «a digitar…» — um doc por utilizador (`typing/{uid}`).
  static Future<void> setTypingActive({
    required String tenantId,
    required String threadId,
    required bool active,
    String? displayLabel,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = typingCol(tenantId, threadId).doc(uid);
    if (!active) {
      try {
        await ref.delete();
      } catch (_) {}
      return;
    }
    var label = (displayLabel ?? '').trim();
    if (label.length > 80) {
      label = label.substring(0, 80);
    }
    await ref.set(
      {
        'updatedAt': FieldValue.serverTimestamp(),
        if (label.isNotEmpty) 'label': label,
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> clearTypingForMe({
    required String tenantId,
    required String threadId,
  }) async {
    await setTypingActive(
      tenantId: tenantId,
      threadId: threadId,
      active: false,
    );
  }

  /// Normaliza e limita tamanhos para as regras Firestore.
  static Map<String, dynamic>? normalizeReplyTo(Map<String, dynamic>? r) {
    if (r == null || r.isEmpty) return null;
    final mid = (r['messageId'] ?? '').toString().trim();
    final sid = (r['senderUid'] ?? '').toString().trim();
    var preview = (r['preview'] ?? '').toString().trim();
    var type = (r['type'] ?? 'text').toString().trim();
    if (mid.isEmpty || sid.isEmpty) return null;
    if (preview.length > 240) {
      preview = '${preview.substring(0, 237)}…';
    }
    if (type.isEmpty) type = 'text';
    return {
      'messageId': mid,
      'senderUid': sid,
      'preview': preview,
      'type': type,
    };
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

  /// Atualiza `lastSeenAtByUid.{uid}` no thread (DM ou grupo) para recibos de leitura na DM.
  static Future<bool> deleteMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      await messagesCol(tenantId, threadId).doc(messageId).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// «Apagar para mim» — mantém o documento; outros continuam a ver.
  static Future<bool> hideMessageForMe({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      await messagesCol(tenantId, threadId).doc(messageId).update({
        'hiddenForUids': FieldValue.arrayUnion([uid]),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mensagem oculta pelo utilizador atual (lista).
  static bool messageHiddenForMe(Map<String, dynamic> m, String uid) {
    final h = m['hiddenForUids'];
    if (h is! List) return false;
    return h.map((e) => e.toString()).contains(uid);
  }

  static Future<void> markThreadLastSeen({
    required String tenantId,
    required String threadId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      await threadRef(tid, threadId).update({
        'lastSeenAtByUid.$uid': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
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
    Map<String, dynamic>? replyTo,
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
    final nr = normalizeReplyTo(replyTo);
    await msgRef.set({
      'senderUid': uid,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
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
    String? fileName,
    Map<String, dynamic>? replyTo,
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
    final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: kind,
      fileName: fileName,
    );
    final nr = normalizeReplyTo(replyTo);
    await msgRef.set({
      'senderUid': uid,
      'type': kind,
      'mediaUrl': downloadUrl,
      'storagePath': storagePath,
      if (fileName != null && fileName.trim().isNotEmpty)
        'fileName': fileName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': preview,
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// Mensagem do tipo figurinha (PNG/WebP — mesma retenção que mídia).
  static Future<bool> sendStickerMessage({
    required String tenantId,
    required String threadId,
    required String downloadUrl,
    String? storagePath,
    String stickerSource = 'upload',
    Map<String, dynamic>? replyTo,
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
    final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: 'sticker',
      fileName: null,
    );
    final nr = normalizeReplyTo(replyTo);
    final sp = storagePath?.trim() ?? '';
    await msgRef.set({
      'senderUid': uid,
      'type': 'sticker',
      'mediaUrl': downloadUrl,
      if (sp.isNotEmpty) 'storagePath': sp,
      'stickerSource': stickerSource,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': preview,
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// Upload para a biblioteca `chat_stickers/` (Storage).
  static Future<({String url, String path})> uploadStickerPackBytes({
    required String tenantId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'igrejas/$tenantId/chat_stickers/${uid}_${ts}_$safeName';
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return (url: url, path: path);
  }

  /// Regista figurinha importada na biblioteca da igreja.
  static Future<String?> registerStickerPackEntry({
    required String tenantId,
    required String mediaUrl,
    required String storagePath,
    String label = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = stickersCol(tenantId).doc();
    await doc.set({
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': uid,
      'mediaUrl': mediaUrl,
      'storagePath': storagePath,
      'label': label.trim(),
      'source': 'upload',
    });
    return doc.id;
  }

  /// Remove figurinha da biblioteca (apenas o criador).
  static Future<bool> deleteStickerPackEntry({
    required String tenantId,
    required String stickerDocId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final ref = stickersCol(tenantId).doc(stickerDocId);
    final snap = await ref.get();
    if (!snap.exists) return false;
    final d = snap.data();
    if (d == null || (d['createdByUid'] ?? '').toString() != uid) {
      return false;
    }
    final path = (d['storagePath'] ?? '').toString().trim();
    if (path.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
    try {
      await ref.delete();
    } catch (_) {
      return false;
    }
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
