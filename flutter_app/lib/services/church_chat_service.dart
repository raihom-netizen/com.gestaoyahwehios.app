import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'church_chat_attachment_utils.dart';
import 'church_chat_member_prefs.dart';
import 'firestore_stream_utils.dart';
import 'analytics_service.dart';
import 'media_upload_service.dart';
import 'upload_storage_task.dart' show formatUploadErrorForUser;

/// Chat entre membros / grupos por departamento — retenção: texto 30 dias, mídia 3 dias.
class ChurchChatService {
  ChurchChatService._();

  static const Duration textRetention = Duration(days: 30);
  static const Duration mediaRetention = Duration(days: 3);

  /// Estados de entrega (estilo WhatsApp).
  static const String deliverySending = 'sending';
  static const String deliveryUploading = 'uploading';
  static const String deliverySent = 'sent';

  static String formatInstantSendError(Object e) => formatUploadErrorForUser(e);

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

  /// Histórico por páginas no cliente (`startAfter` + stream da página recente).
  static const int defaultMessagePageSize =
      YahwehPerformanceV4.chatMessagesPageSize;
  static const int maxOlderMessagePages = 50;

  /// Stream só da «cauda» recente (substitui `limit` crescente até 2500).
  static Stream<QuerySnapshot<Map<String, dynamic>>> recentMessagesStream({
    required String tenantId,
    required String threadId,
    int pageSize = defaultMessagePageSize,
  }) {
    return messagesCol(tenantId, threadId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots();
  }

  /// Página mais antiga (`startAfterDocument`) para scroll infinito.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderMessagesPage({
    required String tenantId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int pageSize = defaultMessagePageSize,
  }) async {
    final snap = await messagesCol(tenantId, threadId)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfterDoc)
        .limit(pageSize)
        .get();
    return snap.docs;
  }

  static CollectionReference<Map<String, dynamic>> typingCol(
      String tenantId, String threadId) {
    return threadRef(tenantId, threadId).collection('typing');
  }

  /// Threads em que o utilizador participa — ordenadas por atividade.
  /// Usa o índice composto em `firestore.indexes.json` (`participantUids` + `lastMessageAt`).
  static Query<Map<String, dynamic>> chatThreadsQueryForUser(
    String tenantId,
    String uid,
  ) {
    return _db
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_threads')
        .where('participantUids', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(400);
  }

  /// Varredura ampla (regras devolvem DM legíveis pelo id `dm_{uid}_…` mesmo sem índice).
  static Query<Map<String, dynamic>> chatThreadsBroadScanQuery(String tenantId) {
    return _db
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_threads')
        .limit(480);
  }

  static bool userInDmThreadId(String threadId, String uid) {
    if (!threadId.startsWith('dm_') || uid.isEmpty) return false;
    return threadId.startsWith('dm_${uid}_') || threadId.endsWith('_$uid');
  }

  /// Outro participante num DM `dm_{menor}_{maior}` (legado sem `participantUids`).
  static String? otherUidInDmThread(String threadId, String myUid) {
    if (!threadId.startsWith('dm_') || myUid.isEmpty) return null;
    final body = threadId.substring(3);
    final i = body.indexOf('_');
    if (i <= 0 || i >= body.length - 1) return null;
    final u1 = body.substring(0, i);
    final u2 = body.substring(i + 1);
    if (u1 == myUid) return u2.isEmpty ? null : u2;
    if (u2 == myUid) return u1.isEmpty ? null : u1;
    return null;
  }

  /// Participação no thread — índice `participantUids` ou id `dm_{uid}_…` (Firestore rules).
  static bool userParticipatesInThread({
    required String threadId,
    required Map<String, dynamic> data,
    required String uid,
  }) {
    if (uid.isEmpty) return false;
    final peers = data['participantUids'];
    if (peers is List &&
        peers.map((e) => e.toString()).where((e) => e.isNotEmpty).contains(uid)) {
      return true;
    }
    return userInDmThreadId(threadId, uid);
  }

  /// DM só entra na lista «Conversas» depois da primeira mensagem real (evita «Toque para conversar» de quem nunca falou).
  static bool threadHasListableConversation(
    Map<String, dynamic> data, {
    String? threadId,
  }) {
    final id = (threadId ?? '').trim();
    if (id.startsWith('dept_') ||
        (data['type'] ?? '').toString() == 'department') {
      return true;
    }
    final preview = (data['lastMessagePreview'] ?? '').toString().trim();
    if (preview.isNotEmpty) return true;
    final sender = (data['lastSenderUid'] ?? '').toString().trim();
    if (sender.isNotEmpty) return true;
    final mc = data['messageCount'];
    if (mc is num && mc > 0) return true;
    final lm = data['lastMessageAt'];
    if (lm is Timestamp) return true;
    return false;
  }

  static Map<String, dynamic>? dmThreadIndexPatch(
    String threadId,
    Map<String, dynamic> data,
  ) {
    if (!threadId.startsWith('dm_')) return null;
    final body = threadId.substring(3);
    final i = body.indexOf('_');
    if (i <= 0 || i >= body.length - 1) return null;
    final u1 = body.substring(0, i);
    final u2 = body.substring(i + 1);
    if (u1.isEmpty || u2.isEmpty || u1 == u2) return null;

    final patch = <String, dynamic>{};
    final current = data['participantUids'];
    final hasBoth = current is List &&
        current.map((e) => e.toString()).contains(u1) &&
        current.map((e) => e.toString()).contains(u2);
    if (!hasBoth) patch['participantUids'] = [u1, u2];
    if (data['type'] != 'dm') patch['type'] = 'dm';
    // lastMessageAt só a partir de mensagem real — não usar createdAt (senão DM vazio ocupa o top-220).
    return patch.isEmpty ? null : patch;
  }

  /// Reparo no dispositivo + callable (threads antigos sem `participantUids` / `lastMessageAt`).
  static Future<int> syncDmThreadsIndex(String tenantId) async {
    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
    var n = await repairDmThreadsClient(tenantId);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'repairChurchChatDmThreads',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 50)),
      );
      await fn
          .call(<String, dynamic>{'tenantId': tenantId})
          .timeout(const Duration(seconds: 52));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('syncDmThreadsIndex callable: $e');
      }
    }
    n += await repairDmThreadsClient(tenantId);
    return n;
  }

  static Future<Map<String, dynamic>?> _lastMessageIndexPatch(
    DocumentReference<Map<String, dynamic>> threadRef,
    Map<String, dynamic> data,
  ) async {
    try {
      final last = await threadRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (last.docs.isEmpty) return null;
      final msg = last.docs.first.data();
      final created = msg['createdAt'];
      if (created is! Timestamp) return null;
      final t = (msg['type'] ?? 'text').toString();
      var preview = (msg['text'] ?? '').toString().trim();
      if (t == 'image') {
        preview = '📷 Foto';
      } else if (t == 'video') {
        preview = '🎬 Vídeo';
      } else if (t == 'audio') {
        preview = '🎤 Áudio';
      } else if (t == 'sticker') {
        preview = '🎨 Figurinha';
      }
      if (preview.length > 120) preview = '${preview.substring(0, 117)}…';

      final patch = <String, dynamic>{};
      if (data['lastMessageAt'] == null) patch['lastMessageAt'] = created;
      if ((data['lastMessagePreview'] ?? '').toString().trim().isEmpty &&
          preview.isNotEmpty) {
        patch['lastMessagePreview'] = preview;
      }
      final sender = (msg['senderUid'] ?? '').toString().trim();
      if ((data['lastSenderUid'] ?? '').toString().trim().isEmpty &&
          sender.isNotEmpty) {
        patch['lastSenderUid'] = sender;
      }
      return patch.isEmpty ? null : patch;
    } catch (_) {
      return null;
    }
  }

  static Future<int> repairDmThreadsClient(String tenantId) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await chatThreadsBroadScanQuery(tenantId).get();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('repairDmThreadsClient broad scan: $e');
      }
      return 0;
    }
    var n = 0;
    WriteBatch? batch = _db.batch();
    var batchCount = 0;
    for (final doc in snap.docs) {
      if (!doc.id.startsWith('dm_')) continue;
      final data = doc.data();
      var patch = dmThreadIndexPatch(doc.id, data);
      final msgPatch = await _lastMessageIndexPatch(doc.reference, data);
      if (msgPatch != null) {
        patch ??= <String, dynamic>{};
        patch.addAll(msgPatch);
      }
      if (!threadHasListableConversation({...data, ...?patch}, threadId: doc.id) &&
          data['lastMessageAt'] != null) {
        patch ??= <String, dynamic>{};
        patch['lastMessageAt'] = FieldValue.delete();
        patch['lastMessagePreview'] = FieldValue.delete();
      }
      if (patch == null) continue;
      batch!.set(doc.reference, patch, SetOptions(merge: true));
      batchCount++;
      n++;
      if (batchCount >= 400) {
        await batch.commit();
        batch = _db.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0 && batch != null) await batch.commit();
    return n;
  }

  /// Fallback quando a query ampla falha na web: lê threads DM por id (`dm_{uid}_peer`).
  static Future<QuerySnapshot<Map<String, dynamic>>> loadDmThreadsSnapshotFallback({
    required String tenantId,
    required String uid,
  }) async {
    final peerUids = <String>{};
    try {
      final profiles = await _db
          .collection('igrejas')
          .doc(tenantId)
          .collection('chat_peer_profiles')
          .limit(220)
          .get();
      for (final p in profiles.docs) {
        final id = p.id.trim();
        if (id.isNotEmpty && id != uid) peerUids.add(id);
      }
    } catch (_) {}

    final threadIds = peerUids.map((p) => dmThreadId(uid, p)).toSet();
    if (threadIds.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final col = _db.collection('igrejas').doc(tenantId).collection('chat_threads');
    final ids = threadIds.toList();
    for (var i = 0; i < ids.length; i += 10) {
      final end = (i + 10 < ids.length) ? i + 10 : ids.length;
      final chunk = ids.sublist(i, end);
      try {
        final snap = await col
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          if (_docIsDmForUserList(doc, uid)) docs.add(doc);
        }
      } catch (_) {
        // Chunk ignorado — reparo callable + query indexada cobrem o resto.
      }
    }

    docs.sort(
      (a, b) =>
          _threadActivityMs(b.data()).compareTo(_threadActivityMs(a.data())),
    );
    return MergedFirestoreQuerySnapshot(docs);
  }

  static int _threadActivityMs(Map<String, dynamic> data) {
    final lm = data['lastMessageAt'];
    if (lm is Timestamp) return lm.millisecondsSinceEpoch;
    final up = data['updatedAt'];
    if (up is Timestamp) return up.millisecondsSinceEpoch;
    final cr = data['createdAt'];
    if (cr is Timestamp) return cr.millisecondsSinceEpoch;
    return 0;
  }

  static QuerySnapshot<Map<String, dynamic>> _mergeThreadSnapshots(
    String uid,
    QuerySnapshot<Map<String, dynamic>>? indexed,
    QuerySnapshot<Map<String, dynamic>>? broad,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    void absorb(QuerySnapshot<Map<String, dynamic>>? snap) {
      if (snap == null) return;
      for (final doc in snap.docs) {
        if (_docIsDmForUserList(doc, uid)) {
          byId[doc.id] = doc;
        }
      }
    }

    absorb(indexed);
    absorb(broad);
    final merged = byId.values.toList()
      ..sort(
        (a, b) =>
            _threadActivityMs(b.data()).compareTo(_threadActivityMs(a.data())),
      );
    return MergedFirestoreQuerySnapshot(merged);
  }

  static bool _docIsDmForUserList(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final data = doc.data();
    final t = (data['type'] ?? '').toString();
    if (t == 'department' || doc.id.startsWith('dept_')) return false;
    if (!userParticipatesInThread(threadId: doc.id, data: data, uid: uid)) {
      return false;
    }
    return threadHasListableConversation(data, threadId: doc.id);
  }

  /// Stream de conversas: query indexada + varredura ampla (DM legados) fundidas.
  static Stream<QuerySnapshot<Map<String, dynamic>>> chatThreadsSnapshotsForUser(
    String tenantId,
    String uid,
  ) {
    late StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subIndexed;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subBroad;
    QuerySnapshot<Map<String, dynamic>>? lastIndexed;
    QuerySnapshot<Map<String, dynamic>>? lastBroad;
    var wireAttempts = 0;
    var wiring = false;
    var fallbackInFlight = false;

    void emitMerged() {
      if (controller.isClosed) return;
      final merged = _mergeThreadSnapshots(uid, lastIndexed, lastBroad);
      controller.add(merged);
      if (merged.docs.isNotEmpty || fallbackInFlight) return;
      fallbackInFlight = true;
      unawaited(() async {
        try {
          final fb = await loadDmThreadsSnapshotFallback(
            tenantId: tenantId,
            uid: uid,
          );
          if (!controller.isClosed && fb.docs.isNotEmpty) {
            controller.add(fb);
          }
        } finally {
          fallbackInFlight = false;
        }
      }());
    }

    Future<void> wire() async {
      if (wiring) return;
      wiring = true;
      try {
        await subIndexed?.cancel();
        await subBroad?.cancel();
        subIndexed = null;
        subBroad = null;
        if (controller.isClosed) return;

        subIndexed = chatThreadsQueryForUser(tenantId, uid).snapshots().listen(
          (event) {
            wireAttempts = 0;
            lastIndexed = event;
            emitMerged();
          },
          onError: (Object error, StackTrace stack) {
            if (controller.isClosed) return;
            if (!FirestoreStreamUtils.isPermissionDenied(error)) {
              wireAttempts++;
              if (wireAttempts > 14) {
                controller.addError(error, stack);
                return;
              }
            }
            lastIndexed = null;
            emitMerged();
            subIndexed?.cancel();
            subIndexed = null;
            final delayMs = 260 + 110 * wireAttempts.clamp(1, 12);
            Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
              if (controller.isClosed) return;
              unawaited(wire());
            });
          },
          cancelOnError: false,
        );

        subBroad = chatThreadsBroadScanQuery(tenantId).snapshots().listen(
          (event) {
            lastBroad = event;
            emitMerged();
          },
          onError: (Object error, StackTrace stack) {
            if (controller.isClosed) return;
            if (!FirestoreStreamUtils.isPermissionDenied(error)) {
              controller.addError(error, stack);
            }
          },
          cancelOnError: false,
        );
      } finally {
        wiring = false;
      }
    }

    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
      onListen: () {
        wireAttempts = 0;
        unawaited(wire());
      },
      onCancel: () {
        if (!controller.hasListener) {
          subIndexed?.cancel();
          subBroad?.cancel();
          subIndexed = null;
          subBroad = null;
        }
      },
    );
    return controller.stream;
  }

  /// Rótulo interno para «a gravar áudio…» na lista de conversas.
  static const String typingLabelRecording = '__recording__';

  /// Indicador «a digitar…» — um doc por utilizador (`typing/{uid}`) + prévia no thread.
  static Future<void> setTypingActive({
    required String tenantId,
    required String threadId,
    required bool active,
    String? displayLabel,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = typingCol(tenantId, threadId).doc(uid);
    final thread = threadRef(tenantId, threadId);
    if (!active) {
      try {
        await ref.delete();
      } catch (_) {}
      try {
        final snap = await thread.get();
        final data = snap.data();
        if (data != null && (data['typingUid'] ?? '').toString() == uid) {
          await thread.set(
            {
              'typingPreview': FieldValue.delete(),
              'typingUid': FieldValue.delete(),
              'typingUpdatedAt': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
        }
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
    final preview = label == typingLabelRecording
        ? '${senderDisplayNameForNewMessage()} está a gravar áudio…'
        : label.isNotEmpty
            ? '$label está a digitar…'
            : 'A digitar…';
    await thread.set(
      {
        'typingPreview': preview,
        'typingUid': uid,
        'typingUpdatedAt': FieldValue.serverTimestamp(),
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

  static Map<String, dynamic>? normalizeForwardedFrom(
    Map<String, dynamic>? f,
  ) {
    if (f == null || f.isEmpty) return null;
    final mid = (f['messageId'] ?? '').toString().trim();
    final sid = (f['senderUid'] ?? '').toString().trim();
    var preview = (f['preview'] ?? '').toString().trim();
    var type = (f['type'] ?? 'text').toString().trim();
    final fromThread = (f['fromThreadId'] ?? '').toString().trim();
    if (mid.isEmpty || preview.isEmpty) return null;
    if (preview.length > 240) {
      preview = '${preview.substring(0, 237)}…';
    }
    if (type.isEmpty) type = 'text';
    return {
      'messageId': mid,
      if (sid.isNotEmpty) 'senderUid': sid,
      'preview': preview,
      'type': type,
      if (fromThread.isNotEmpty) 'fromThreadId': fromThread,
    };
  }

  static Map<String, dynamic> forwardedFromMessageDoc(
    String sourceThreadId,
    String messageId,
    Map<String, dynamic> data,
  ) {
    final type = (data['type'] ?? 'text').toString();
    var preview = type == 'text'
        ? (data['text'] ?? '').toString().trim()
        : ChurchChatAttachmentUtils.previewForThreadLastMessage(
            kind: type,
            fileName: (data['fileName'] ?? '').toString(),
          );
    if (preview.isEmpty) preview = 'Mensagem';
    return {
      'messageId': messageId,
      'senderUid': (data['senderUid'] ?? '').toString(),
      'preview': preview,
      'type': type,
      'fromThreadId': sourceThreadId,
    };
  }

  /// Reencaminha cópia para outro thread (texto ou mídia já no Storage).
  static Future<bool> forwardMessageToThread({
    required String tenantId,
    required String sourceThreadId,
    required String targetThreadId,
    required String messageId,
    required Map<String, dynamic> messageData,
  }) async {
    if (targetThreadId.trim().isEmpty || sourceThreadId == targetThreadId) {
      return false;
    }
    final fwd = forwardedFromMessageDoc(
      sourceThreadId,
      messageId,
      messageData,
    );
    final type = (messageData['type'] ?? 'text').toString();
    if (type == 'text') {
      final text = (messageData['text'] ?? '').toString().trim();
      if (text.isEmpty) return false;
      return sendTextMessage(
        tenantId: tenantId,
        threadId: targetThreadId,
        text: text,
        forwardedFrom: fwd,
        senderDisplayName: senderDisplayNameForNewMessage(),
      );
    }
    final url = (messageData['mediaUrl'] ?? '').toString().trim();
    if (url.isEmpty) return false;
    return sendMediaMessage(
      tenantId: tenantId,
      threadId: targetThreadId,
      downloadUrl: url,
      storagePath: (messageData['storagePath'] ?? '').toString(),
      kind: type,
      fileName: (messageData['fileName'] ?? '').toString().isEmpty
          ? null
          : (messageData['fileName'] ?? '').toString(),
      forwardedFrom: fwd,
      senderDisplayName: senderDisplayNameForNewMessage(),
    );
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

  static Timer? _appPresenceHeartbeat;
  static String? _appPresenceTenantId;

  /// Atualiza `chat_presence` em ciclo enquanto o painel da igreja está aberto,
  /// para o membro aparecer «online» sem abrir o módulo Chat (alinhado a [isOnlineFromSnapshot] ~45s).
  static void startAppWidePresenceHeartbeat(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      stopAppWidePresenceHeartbeat();
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      stopAppWidePresenceHeartbeat();
      return;
    }
    if (_appPresenceHeartbeat != null && _appPresenceTenantId == tid) return;
    _appPresenceHeartbeat?.cancel();
    _appPresenceTenantId = tid;
    unawaited(touchPresence(tid));
    _appPresenceHeartbeat = Timer.periodic(
      const Duration(seconds: 25),
      (_) => touchPresence(tid),
    );
  }

  static void stopAppWidePresenceHeartbeat() {
    _appPresenceHeartbeat?.cancel();
    _appPresenceHeartbeat = null;
    _appPresenceTenantId = null;
  }

  /// Volta ao primeiro plano — refresca já o indicador «online».
  static Future<void> appWidePresencePingIfActive() async {
    final tid = _appPresenceTenantId;
    if (tid == null || tid.isEmpty) return;
    await touchPresence(tid);
  }

  static bool isOnlineFromSnapshot(DocumentSnapshot<Map<String, dynamic>>? snap) {
    final ts = snap?.data()?['lastSeenAt'];
    if (ts is! Timestamp) return false;
    return DateTime.now().difference(ts.toDate()).inSeconds < 45;
  }

  /// Presença em lote (evita N listeners `chat_presence/{uid}` na lista de conversas).
  static Future<Map<String, bool>> fetchPresenceOnlineMap({
    required String tenantId,
    required Iterable<String> authUids,
  }) async {
    final tid = tenantId.trim();
    final ids = authUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (tid.isEmpty || ids.isEmpty) return {};
    final out = <String, bool>{};
    const chunk = 12;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(
        i,
        i + chunk > ids.length ? ids.length : i + chunk,
      );
      final snaps = await Future.wait(
        part.map(
          (uid) => _db
              .collection('igrejas')
              .doc(tid)
              .collection('chat_presence')
              .doc(uid)
              .get(),
        ),
      );
      for (var j = 0; j < part.length; j++) {
        out[part[j]] = isOnlineFromSnapshot(snaps[j]);
      }
    }
    return out;
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

  /// Legado síncrono — preferir [ChurchChatInstantSendService.enqueueText].
  static Future<bool> sendTextMessage({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
  }) async {
    final begun = await beginTextMessage(
      tenantId: tenantId,
      threadId: threadId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
    );
    if (!begun.allowed) return false;
    await finalizeTextMessage(
      tenantId: tenantId,
      threadId: threadId,
      messageId: begun.messageId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
    );
    unawaited(AnalyticsService.logMessage());
    return true;
  }

  /// Stub de texto (`deliveryStatus: sending`) — aparece na thread sem esperar rede lenta.
  static Future<({String messageId, bool allowed})> beginTextMessage({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
  }) async {
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tenantId,
      threadId: threadId,
    )) {
      return (messageId: '', allowed: false);
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(textRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
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
      'deliveryStatus': deliverySending,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
      if (nf != null) 'forwardedFrom': nf,
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
      if (mentions.isNotEmpty) 'mentionedUids': mentions,
    });
    return (messageId: msgRef.id, allowed: true);
  }

  static Future<void> finalizeTextMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final nf = normalizeForwardedFrom(forwardedFrom);
    final preview = nf != null
        ? '↪ ${nf['preview']}'
        : (text.length > 120 ? '${text.substring(0, 117)}…' : text);
    await messagesCol(tenantId, threadId).doc(messageId).update({
      'deliveryStatus': deliverySent,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': preview.length > 120
            ? '${preview.substring(0, 117)}…'
            : preview,
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> abandonTextMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      await messagesCol(tenantId, threadId).doc(messageId).delete();
    } catch (_) {}
  }

  static Future<({String messageId, bool allowed})> beginStickerMessage({
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
      return (messageId: '', allowed: false);
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    final nr = normalizeReplyTo(replyTo);
    final sp = storagePath?.trim() ?? '';
    final label = (senderDisplayName ?? '').trim();
    await msgRef.set({
      'senderUid': uid,
      'type': 'sticker',
      'deliveryStatus': deliverySending,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (nr != null) 'replyTo': nr,
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
    });
    return (messageId: msgRef.id, allowed: true);
  }

  static Future<void> finalizeStickerMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String downloadUrl,
    String? storagePath,
    String stickerSource = 'upload',
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: 'sticker',
      fileName: null,
    );
    final sp = storagePath?.trim() ?? '';
    await messagesCol(tenantId, threadId).doc(messageId).update({
      'mediaUrl': downloadUrl,
      if (sp.isNotEmpty) 'storagePath': sp,
      'stickerSource': stickerSource,
      'deliveryStatus': deliverySent,
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
  }

  static Future<bool> sendMediaMessage({
    required String tenantId,
    required String threadId,
    required String downloadUrl,
    required String storagePath,
    required String kind,
    String? fileName,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
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
    var preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: kind,
      fileName: fileName,
    );
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
    if (nf != null) {
      preview = '↪ ${nf['preview']}';
    }
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
      if (nf != null) 'forwardedFrom': nf,
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
      'deliveryStatus': deliverySent,
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

  /// Caminho Storage determinístico (stub Firestore + upload usam o mesmo path).
  static String buildChatMediaStoragePath({
    required String tenantId,
    required String threadId,
    required String fileName,
  }) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return 'igrejas/$tenantId/chat_media/$threadId/${uid}_${ts}_$safeName';
  }

  /// Cria mensagem no thread sem `mediaUrl` (lista e thread atualizam na hora).
  static Future<({String messageId, String storagePath})> beginMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String kind,
    String? fileName,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
  }) async {
    await ensureFirebaseInitialized();
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tenantId,
      threadId: threadId,
    )) {
      throw StateError('Envio bloqueado para este contacto.');
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final storagePath = buildChatMediaStoragePath(
      tenantId: tenantId,
      threadId: threadId,
      fileName: fileName ?? 'media',
    );
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    var preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: kind,
      fileName: fileName,
    );
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
    if (nf != null) {
      preview = '↪ ${nf['preview']}';
    }
    final label = (senderDisplayName ?? '').trim();
    await msgRef.set({
      'senderUid': uid,
      'type': kind,
      'deliveryStatus': deliveryUploading,
      'uploadProgress': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      if (fileName != null && fileName.trim().isNotEmpty)
        'fileName': fileName.trim(),
      if (nr != null) 'replyTo': nr,
      if (nf != null) 'forwardedFrom': nf,
      if (label.isNotEmpty)
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
    });
    await threadRef(tenantId, threadId).set(
      {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': preview.length > 120
            ? '${preview.substring(0, 117)}…'
            : preview,
        'lastSenderUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return (messageId: msgRef.id, storagePath: storagePath);
  }

  /// Completa o stub após upload no Storage.
  static Future<bool> completeMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String downloadUrl,
    required String storagePath,
    String? fileName,
    String? thumbUrl,
  }) async {
    final patch = <String, dynamic>{
      'mediaUrl': downloadUrl,
      'storagePath': storagePath,
      'deliveryStatus': deliverySent,
      'uploadProgress': 1,
    };
    if (thumbUrl != null && thumbUrl.trim().isNotEmpty) {
      patch['thumbUrl'] = thumbUrl.trim();
    }
    if (fileName != null && fileName.trim().isNotEmpty) {
      patch['fileName'] = fileName.trim();
    }
    final ref = messagesCol(tenantId, threadId).doc(messageId);
    try {
      await ref.update(patch);
    } on FirebaseException catch (e) {
      if (thumbUrl != null &&
          patch.containsKey('thumbUrl') &&
          e.code == 'permission-denied') {
        patch.remove('thumbUrl');
        await ref.update(patch);
      } else {
        rethrow;
      }
    }
    return true;
  }

  /// Android/iOS: rede instável pode falhar o `update` após o Storage já ter recebido o ficheiro.
  static Future<bool> completeMediaUploadMessageWithRetry({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String downloadUrl,
    required String storagePath,
    String? fileName,
    String? thumbUrl,
    int maxAttempts = 5,
  }) async {
    Object? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await completeMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          fileName: fileName,
          thumbUrl: thumbUrl,
        );
      } catch (e) {
        last = e;
        if (attempt >= maxAttempts) break;
        await Future.delayed(
          Duration(milliseconds: 280 * attempt),
        );
      }
    }
    throw last ?? StateError('Não foi possível concluir o envio no servidor.');
  }

  /// Atualiza progresso no stub (regras: só `uploadProgress` enquanto `uploading`).
  static Future<void> patchMediaUploadProgress({
    required String tenantId,
    required String threadId,
    required String messageId,
    required double progress,
  }) async {
    try {
      await messagesCol(tenantId, threadId).doc(messageId).update({
        'uploadProgress': progress.clamp(0.0, 1.0),
      });
    } catch (_) {}
  }

  /// Remove stub se o upload falhar de forma irrecuperável.
  static Future<void> abandonMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      await messagesCol(tenantId, threadId).doc(messageId).delete();
    } catch (_) {}
  }

  /// Upload para `chat_media/` — compressão JPEG/PNG leve (via [MediaUploadService]),
  /// sem fila offline (envio imediato). [onUploadTaskCreated] permite cancelar o [UploadTask].
  static Future<({String url, String path})> uploadChatBytes({
    required String tenantId,
    required String threadId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? storagePathOverride,
    bool skipClientPrepare = false,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    await ensureFirebaseInitialized();
    final path = storagePathOverride ??
        buildChatMediaStoragePath(
          tenantId: tenantId,
          threadId: threadId,
          fileName: fileName,
        );
    final ubytes =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final ct = contentType.toLowerCase();
    final chatJpegFast =
        ct.contains('jpeg') || ct == 'image/jpg' || ct == 'image/pjpeg';
    final url = await MediaUploadService.uploadBytesWithRetry(
      storagePath: path,
      bytes: ubytes,
      contentType: contentType,
      useOfflineQueue: false,
      maxAttempts: 4,
      skipClientPrepare: skipClientPrepare,
      chatJpegFast: chatJpegFast,
      onProgress: onProgress,
      onUploadTaskCreated: onUploadTaskCreated,
    );
    return (url: url, path: path);
  }

  /// Upload por ficheiro no disco (vídeos/PDF grandes — evita `readAsBytes` completo na RAM).
  static Future<({String url, String path})> uploadChatFile({
    required String tenantId,
    required String threadId,
    required String localPath,
    required String fileName,
    required String contentType,
    String? storagePathOverride,
    bool skipRecompress = false,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('uploadChatFile não suportado na web.');
    }
    final path = storagePathOverride ??
        buildChatMediaStoragePath(
          tenantId: tenantId,
          threadId: threadId,
          fileName: fileName,
        );
    final ct = contentType.toLowerCase();
    final chatJpegFast = skipRecompress ||
        ct.contains('jpeg') ||
        ct == 'image/jpg' ||
        ct == 'image/pjpeg';
    final url = await MediaUploadService.uploadFileWithRetry(
      storagePath: path,
      file: File(localPath),
      contentType: contentType,
      useOfflineQueue: false,
      maxAttempts: 4,
      skipRecompress: skipRecompress,
      chatJpegFast: chatJpegFast,
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
