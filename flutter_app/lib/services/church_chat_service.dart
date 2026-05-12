import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'church_chat_attachment_utils.dart';
import 'church_chat_member_prefs.dart';
import 'media_upload_service.dart';

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

  /// Nome mostrado no grupo/DM (gravado em mensagens novas).
  static String senderDisplayNameForNewMessage() {
    final u = FirebaseAuth.instance.currentUser;
    final n = u?.displayName?.trim();
    if (n != null && n.isNotEmpty) {
      return n.length > 100 ? n.substring(0, 100) : n;
    }
    final e = u?.email?.trim();
    if (e != null && e.contains('@')) {
      final p = e.split('@').first.trim();
      if (p.isNotEmpty) {
        return p.length > 100 ? p.substring(0, 100) : p;
      }
    }
    return 'Membro';
  }

  /// Membros ativos do departamento (menções, listas).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchActiveDepartmentMembers({
    required String tenantId,
    required String departmentId,
  }) async {
    final deptId = departmentId.trim();
    if (deptId.isEmpty) return [];

    bool isActive(Map<String, dynamic> d) {
      final st = (d['STATUS'] ?? d['status'] ?? '').toString().toLowerCase();
      return st == 'ativo';
    }

    int nameCmp(QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b) {
      final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    }

    try {
      final q = await _db
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .where('departamentosIds', arrayContains: deptId)
          .limit(400)
          .get();
      final out = q.docs.where((doc) => isActive(doc.data())).toList();
      out.sort(nameCmp);
      return out;
    } catch (_) {
      final all = await _db
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .limit(600)
          .get();
      final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in all.docs) {
        final data = doc.data();
        if (!isActive(data)) continue;
        final ids = data['departamentosIds'];
        if (ids is! List) continue;
        var hit = false;
        for (final x in ids) {
          if (x.toString() == deptId) {
            hit = true;
            break;
          }
        }
        if (!hit) continue;
        out.add(doc);
      }
      out.sort(nameCmp);
      return out;
    }
  }

  /// Reação do utilizador atual (`emoji` vazio remove).
  static Future<bool> setMyReactionOnMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    String? emoji,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    var e = emoji?.trim() ?? '';
    if (e.length > 8) e = e.substring(0, 8);
    final ref = messagesCol(tenantId, threadId).doc(messageId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final raw = snap.data()?['reactionsByUid'];
        final cur = <String, String>{};
        if (raw is Map) {
          for (final en in raw.entries) {
            final k = en.key.toString();
            final v = en.value?.toString() ?? '';
            if (k.isNotEmpty && v.isNotEmpty) cur[k] = v;
          }
        }
        if (e.isEmpty) {
          cur.remove(uid);
        } else {
          cur[uid] = e;
        }
        tx.update(ref, {'reactionsByUid': cur});
      });
      return true;
    } catch (_) {
      return false;
    }
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

  /// Contagem agregada (Firestore `count`) — não lidas = mensagens com `createdAt` depois da última leitura do utilizador no thread.
  static Future<({int unread, int total})> threadMessageUnreadAndTotalCounts({
    required String tenantId,
    required String threadId,
    Timestamp? myLastSeenInThread,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || threadId.trim().isEmpty) {
      return (unread: 0, total: 0);
    }
    final col = messagesCol(tid, threadId);
    try {
      final totalSnap = await col.count().get();
      final total = totalSnap.count ?? 0;
      if (total == 0) {
        return (unread: 0, total: 0);
      }
      if (myLastSeenInThread == null) {
        return (unread: total, total: total);
      }
      final unreadSnap = await col
          .where('createdAt', isGreaterThan: myLastSeenInThread)
          .count()
          .get();
      final unread = unreadSnap.count ?? 0;
      return (unread: unread, total: total);
    } catch (_) {
      return (unread: 0, total: 0);
    }
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
    final toAdd = participantUids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    await ref.set(
      {
        'type': 'department',
        'departmentId': departmentId,
        'title': departmentName,
        if (toAdd.isNotEmpty) 'participantUids': FieldValue.arrayUnion(toAdd),
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
    String? senderDisplayName,
    List<String>? mentionedUids,
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
    final label = (senderDisplayName ?? '').trim();
    final mentions = (mentionedUids ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.length > 4)
        .toSet()
        .take(24)
        .toList();
    await msgRef.set({
      'senderUid': uid,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
      if (mentions.isNotEmpty) 'mentionedUids': mentions,
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
    String? senderDisplayName,
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
    final label = (senderDisplayName ?? '').trim();
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
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
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
    String? senderDisplayName,
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
    final label = (senderDisplayName ?? '').trim();
    await msgRef.set({
      'senderUid': uid,
      'type': 'sticker',
      'mediaUrl': downloadUrl,
      if (sp.isNotEmpty) 'storagePath': sp,
      'stickerSource': stickerSource,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
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

  /// Upload para `chat_media/` — compressão JPEG/PNG leve (via [MediaUploadService]),
  /// sem fila offline (envio imediato). [onUploadTaskCreated] permite cancelar o [UploadTask].
  static Future<({String url, String path})> uploadChatBytes({
    required String tenantId,
    required String threadId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'igrejas/$tenantId/chat_media/$threadId/${uid}_${ts}_$safeName';
    final ubytes =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final url = await MediaUploadService.uploadBytesWithRetry(
      storagePath: path,
      bytes: ubytes,
      contentType: contentType,
      useOfflineQueue: false,
      maxAttempts: 2,
      onProgress: onProgress,
      onUploadTaskCreated: onUploadTaskCreated,
    );
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
