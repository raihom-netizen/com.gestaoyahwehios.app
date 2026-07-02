import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import 'package:gestao_yahweh/core/chat_engine/chat_messaging_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_presence_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_thread_repository.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart'
    show YahwehUploadModule;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'church_chat_album_utils.dart';
import 'church_chat_attachment_utils.dart';
import 'church_chat_media_storage.dart';
import 'church_chat_local_conversations.dart';
import 'church_chat_member_prefs.dart';
import 'church_chat_message_fields.dart';
import 'church_chat_threads_list_cache.dart';
import 'chat_publish_verification_service.dart';
import 'chat_strict_publish_service.dart';
import 'firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'analytics_service.dart';
import 'media_upload_service.dart';
import 'storage_media_service.dart';
import 'upload_storage_task.dart' show formatUploadErrorForUser;

/// Indicadores «a digitar / a gravar» num thread (polling leve).
class ChurchChatTypingActivity {
  const ChurchChatTypingActivity({
    this.names = const [],
    this.unnamed = 0,
    this.recording = 0,
  });

  final List<String> names;
  final int unnamed;
  final int recording;

  bool get isEmpty => names.isEmpty && unnamed == 0 && recording == 0;

  String get label {
    if (recording > 0 && names.isEmpty && unnamed == 0) {
      return recording == 1
          ? 'A gravar áudio…'
          : '$recording pessoas a gravar áudio…';
    }
    if (names.isEmpty) {
      return unnamed == 1
          ? 'A digitar…'
          : '$unnamed pessoas a digitar…';
    }
    if (unnamed == 0) {
      return names.length == 1
          ? '${names.first} está a digitar…'
          : '${names.join(', ')} estão a digitar…';
    }
    return '${names.join(', ')} e mais $unnamed a digitar…';
  }
}

/// Chat entre membros / grupos por departamento — retenção: texto 30 dias, mídia 3 dias.
class ChurchChatService {
  ChurchChatService._();

  static const Duration textRetention = Duration(days: 30);
  static const Duration mediaRetention = Duration(days: 3);

  /// Estados de entrega (estilo WhatsApp).
  static const String deliveryLocal = 'local';
  static const String deliverySending = 'sending';
  static const String deliveryUploading = 'uploading';
  /// Aguardando rede / fila de reenvio (stub mantém-se; não apagar mensagem).
  static const String deliveryQueued = 'queued';
  static const String deliverySent = 'sent';
  static const String deliveryDelivered = 'delivered';
  static const String deliveryRead = 'read';
  static const String deliveryFailed = 'failed';

  static String formatInstantSendError(Object e) => formatUploadErrorForUser(e);

  static FirebaseFirestore get _db => firebaseDefaultFirestore;

  static String dmThreadId(String uidA, String uidB) {
    final a = uidA.compareTo(uidB) < 0 ? uidA : uidB;
    final b = uidA.compareTo(uidB) < 0 ? uidB : uidA;
    return 'dm_${a}_$b';
  }

  static String deptThreadId(String departmentId) => 'dept_$departmentId';

  static DocumentReference<Map<String, dynamic>> threadRef(
      String tenantId, String threadId) {
    return         ChurchOperationalPaths.churchDoc(tenantId)
        .collection('chats')
        .doc(threadId);
  }

  static CollectionReference<Map<String, dynamic>> messagesCol(
      String tenantId, String threadId) {
    return threadRef(tenantId, threadId).collection('messages');
  }

  /// Biblioteca de figurinhas por igreja (`chat_stickers`).
  static CollectionReference<Map<String, dynamic>> stickersCol(
      String tenantId) {
    return ChurchOperationalPaths.churchDoc(tenantId).collection('chat_stickers');
  }

  /// Histórico por páginas no cliente (`startAfter` + stream da página recente).
  ///
  /// **Realtime (§11):** `snapshots()` em [recentMessagesStream] com
  /// `orderBy(createdAt, descending: true)` — campo canónico = «timestamp» da mensagem.
  static const String messageTimestampField = 'createdAt';

  static const int defaultMessagePageSize =
      YahwehPerformanceV4.chatMessagesPageSize;
  static const int maxOlderMessagePages = 50;

  static String recentMessagesCacheKey(String tenantId, String threadId) =>
      'chat_msgs_${tenantId.trim()}_$threadId';

  static Query<Map<String, dynamic>> recentMessagesQuery({
    required String tenantId,
    required String threadId,
    int pageSize = defaultMessagePageSize,
  }) {
    return messagesCol(tenantId, threadId)
        .orderBy(messageTimestampField, descending: true)
        .limit(pageSize);
  }

  /// Leitura pontual estável (Controle Total) — cache → rede com retry.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchRecentMessagesPage({
    required String tenantId,
    required String threadId,
    int pageSize = defaultMessagePageSize,
  }) async {
    final op = ChurchRepository.churchId(tenantId);
    return ChatMessagingEngine.fetchRecentMessagesPage(
      churchId: op,
      chatId: threadId,
      pageSize: pageSize,
    );
  }

  /// Stream da cauda recente — resiliente a rede/`INTERNAL ASSERTION` (web).
  static Stream<QuerySnapshot<Map<String, dynamic>>> recentMessagesStream({
    required String tenantId,
    required String threadId,
    int pageSize = defaultMessagePageSize,
  }) {
    return ChatMessagingEngine.watchRecentMessages(
      churchId: tenantId,
      chatId: threadId,
      pageSize: pageSize,
    );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> threadSnapshots(
    String tenantId,
    String threadId,
  ) {
    return FirestoreStreamUtils.documentWatchBootstrap(
      threadRef(tenantId, threadId),
    );
  }

  /// Página mais antiga (`startAfterDocument`) para scroll infinito.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderMessagesPage({
    required String tenantId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int pageSize = defaultMessagePageSize,
  }) async {
    return ChatMessagingEngine.loadOlderMessagesPage(
      churchId: tenantId,
      chatId: threadId,
      startAfterDoc: startAfterDoc,
      pageSize: pageSize,
    );
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
    return ChatThreadRepository.threadsForUser(
      churchId: tenantId,
      uid: uid,
      limit: YahwehPerformanceV4.chatThreadsListLimit,
    );
  }

  /// Threads com `participantUids` mas sem `lastMessageAt` (não entram na query ordenada).
  static Query<Map<String, dynamic>> chatThreadsParticipantQuery(
    String tenantId,
    String uid,
  ) {
    return         ChurchOperationalPaths.churchDoc(tenantId)
        .collection('chats')
        .where('participantUids', arrayContains: uid)
        .limit(YahwehPerformanceV4.chatThreadsFallbackLimit);
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
  ///
  /// Equivalente Firestore ao spec `conversations/{id}`: doc em `chat_threads/{id}`.
  static bool threadHasListableConversation(
    Map<String, dynamic> data, {
    String? threadId,
  }) {
    final id = (threadId ?? '').trim();
    if (id.startsWith('dept_') ||
        (data['type'] ?? '').toString() == 'department') {
      return true;
    }
    if (data['hasConversation'] == true) return true;
    final preview = (data['lastMessagePreview'] ?? data['lastMessage'] ?? '')
        .toString()
        .trim();
    if (preview.isNotEmpty) return true;
    final sender = (data['lastSenderUid'] ?? '').toString().trim();
    if (sender.isNotEmpty) return true;
    final mc = data['messageCount'];
    if (mc is num && mc > 0) return true;
    final lm = data['lastMessageAt'];
    if (lm is Timestamp) return true;
    // Threads DM indexados mas metadados incompletos (legado / web) — manter na lista.
    if (id.startsWith('dm_') && data['participantUids'] is List) {
      final peerCount = (data['participantUids'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .length;
      if (peerCount >= 2) {
        if (data['updatedAt'] is Timestamp || data['createdAt'] is Timestamp) {
          return true;
        }
      }
    }
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

  /// Índice DM (`participantUids`, `type`) — escrita separada (regras Firestore).
  static Future<void> mergeDmThreadIndexIfNeeded(
    String tenantId,
    String threadId,
  ) async {
    if (!threadId.startsWith('dm_')) return;
    try {
      final snap = await threadRef(tenantId, threadId).get();
      final patch = dmThreadIndexPatch(threadId, snap.data() ?? {});
      if (patch == null || patch.isEmpty) return;
      await threadRef(tenantId, threadId).set(patch, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Atualiza `chat_threads` (= conversations no spec) — ordenação por `lastMessageAt`.
  static Map<String, dynamic> threadLastMessageIndexPatch({
    required String preview,
    required String senderUid,
    required String messageType,
  }) {
    final p = preview.trim();
    final short = p.length > 120 ? '${p.substring(0, 117)}…' : p;
    return {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessage': short,
      'lastMessagePreview': short,
      'lastMessageType': messageType,
      'lastSenderUid': senderUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'hasConversation': true,
    };
  }

  /// Garante doc DM antes do 1.º envio (regras exigem `exists` no thread).
  static Future<void> _ensureDmThreadDocBeforeSend(
    String tenantId,
    String threadId,
  ) async {
    if (!threadId.startsWith('dm_')) return;
    final ref = threadRef(tenantId, threadId);
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (cached.exists) return;
    } catch (_) {}
    try {
      final live = await ref.get();
      if (live.exists) return;
    } catch (_) {}
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final body = threadId.substring(3);
    final parts = body.split('_');
    if (parts.length < 2) return;
    final uidA = parts.first;
    final uidB = parts.sublist(1).join('_');
    if (uid != uidA && uid != uidB) return;
    final other = uid == uidA ? uidB : uidA;
    await ensureDmThreadResilient(
      tenantId: tenantId,
      uidA: uid,
      uidB: other,
      titleA: senderDisplayNameForNewMessage(),
      titleB: 'Membro',
    );
  }

  /// Mensagem + índice do thread no mesmo commit (evita conversa invisível na lista).
  static Future<void> _commitMessageAndThreadIndex({
    required String tenantId,
    required String threadId,
    required DocumentReference<Map<String, dynamic>> msgRef,
    required Map<String, dynamic> messageData,
    required String preview,
    required String senderUid,
    required String messageType,
    String? peerUid,
    String? peerDisplayName,
  }) async {
    final threadPatch = threadLastMessageIndexPatch(
      preview: preview,
      senderUid: senderUid,
      messageType: messageType,
    );
    final tRef = threadRef(tenantId, threadId);
    Future<void> commitMobile() => FirestoreWebGuard.runChatWriteWithRecovery(() async {
          final batch = _db.batch();
          batch.set(msgRef, messageData);
          batch.set(tRef, threadPatch, SetOptions(merge: true));
          await batch.commit();
        });
    if (kIsWeb) {
      await AdminFeedFirestoreBridge.upsertDocRef(
        docRef: msgRef,
        data: messageData,
        isNewDoc: true,
        directWrite: () => msgRef.set(messageData),
      );
      await AdminFeedFirestoreBridge.upsertDocRef(
        docRef: tRef,
        data: threadPatch,
        isNewDoc: false,
        directWrite: () => tRef.set(threadPatch, SetOptions(merge: true)),
      );
    } else {
      await runFirestorePublishWithRecovery(commitMobile);
    }
    unawaited(mergeDmThreadIndexIfNeeded(tenantId, threadId));
    unawaited(
      ChurchChatLocalConversations.recordFromOutbound(
        tenantId: tenantId,
        myUid: senderUid,
        threadId: threadId,
        preview: preview,
        messageType: messageType,
        peerUid: peerUid,
        displayName: peerDisplayName,
      ),
    );
  }

  /// Reparo no dispositivo + callable (threads antigos sem `participantUids` / `lastMessageAt`).
  static Future<int> syncDmThreadsIndex(String tenantId) async {
    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
    var n = await repairDmThreadsClient(tenantId);
    try {
      final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '')
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
      var preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
        kind: t,
        fileName: (msg['fileName'] ?? '').toString(),
      );
      if (t == 'text') {
        preview = (msg['text'] ?? '').toString().trim();
      }
      if (preview.length > 120) preview = '${preview.substring(0, 117)}…';

      final patch = <String, dynamic>{
        'hasConversation': true,
      };
      if (data['lastMessageAt'] == null) patch['lastMessageAt'] = created;
      if ((data['lastMessagePreview'] ?? data['lastMessage'] ?? '')
          .toString()
          .trim()
          .isEmpty &&
          preview.isNotEmpty) {
        patch['lastMessagePreview'] = preview;
        patch['lastMessage'] = preview;
      }
      if ((data['lastMessageType'] ?? '').toString().trim().isEmpty) {
        patch['lastMessageType'] = t;
      }
      final sender = (msg['senderUid'] ?? '').toString().trim();
      if ((data['lastSenderUid'] ?? '').toString().trim().isEmpty &&
          sender.isNotEmpty) {
        patch['lastSenderUid'] = sender;
      }
      return patch;
    } catch (_) {
      return null;
    }
  }

  static Future<int> repairDmThreadsClient(String tenantId) async {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    Future<void> absorb(Query<Map<String, dynamic>> q) async {
      try {
        final snap = await q.get();
        for (final doc in snap.docs) {
          if (doc.id.startsWith('dm_')) byId[doc.id] = doc;
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('repairDmThreadsClient query: $e');
        }
      }
    }

    await absorb(chatThreadsParticipantQuery(tenantId, uid));
    await absorb(chatThreadsQueryForUser(tenantId, uid));

    try {
      final fb = await loadDmThreadsSnapshotFallback(
        tenantId: tenantId,
        uid: uid,
      );
      for (final doc in fb.docs) {
        byId[doc.id] = doc;
      }
    } catch (_) {}

    var n = 0;
    WriteBatch? batch = _db.batch();
    var batchCount = 0;
    for (final doc in byId.values) {
      final data = doc.data();
      var patch = dmThreadIndexPatch(doc.id, data);
      final msgPatch = await _lastMessageIndexPatch(doc.reference, data);
      if (msgPatch != null) {
        patch ??= <String, dynamic>{};
        patch.addAll(msgPatch);
      }
      // Só remove índice de ordenação se o thread não tem mensagens (evita sumir da lista).
      final hasMessages = await doc.reference
          .collection('messages')
          .limit(1)
          .get()
          .then((s) => s.docs.isNotEmpty);
      final merged = {...data, ...?patch};
      final listable = threadHasListableConversation(merged, threadId: doc.id);
      final hadConversation = data['hasConversation'] == true ||
          merged['hasConversation'] == true;
      if (!hasMessages &&
          !hadConversation &&
          !listable &&
          data['lastMessageAt'] != null) {
        patch ??= <String, dynamic>{};
        patch['lastMessageAt'] = FieldValue.delete();
        patch['lastMessagePreview'] = FieldValue.delete();
        patch['lastMessage'] = FieldValue.delete();
      } else if ((hasMessages || hadConversation || listable) &&
          data['hasConversation'] != true) {
        patch ??= <String, dynamic>{};
        patch['hasConversation'] = true;
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
    final op = ChurchPanelTenant.resolve(tenantId.trim());
    if (op.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }
    final peerUids = <String>{};
    try {
      final profiles = await firestoreQueryGetReliable(
        ChurchUiCollections.churchDoc(op)
            .collection('chat_peer_profiles')
            .limit(YahwehPerformanceV4.chatThreadsFallbackLimit),
      );
      for (final p in profiles.docs) {
        final id = p.id.trim();
        if (id.isNotEmpty && id != uid) peerUids.add(id);
      }
    } catch (_) {}

    // Queries válidas nas regras (participant + indexada).
    try {
      for (final doc
          in (await firestoreQueryGetReliable(
            chatThreadsParticipantQuery(tenantId, uid),
          )).docs) {
        if (!doc.id.startsWith('dm_')) continue;
        final peer = otherUidInDmThread(doc.id, uid);
        if (peer != null && peer.isNotEmpty) peerUids.add(peer);
      }
    } catch (_) {}
    try {
      for (final doc in (await firestoreQueryGetReliable(
        chatThreadsQueryForUser(tenantId, uid),
      )).docs) {
        if (!doc.id.startsWith('dm_')) continue;
        final peer = otherUidInDmThread(doc.id, uid);
        if (peer != null && peer.isNotEmpty) peerUids.add(peer);
      }
    } catch (_) {}

    final threadIds = peerUids.map((p) => dmThreadId(uid, p)).toSet();
    if (threadIds.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final col = ChurchUiCollections.chats(op);
    for (final id in threadIds) {
      try {
        final snap = await firestoreQueryGetReliable(
          col.where(FieldPath.documentId, isEqualTo: id).limit(1),
        );
        for (final doc in snap.docs) {
          if (_docIsDmForUserList(doc, uid)) docs.add(doc);
        }
      } catch (_) {}
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
    QuerySnapshot<Map<String, dynamic>>? extra, [
    QuerySnapshot<Map<String, dynamic>>? participantOnly,
  ]) {
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
    absorb(extra);
    absorb(participantOnly);
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

  static final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _chatThreadsStreamByKey = {};

  /// Invalida stream em cache (troca de igreja / logout).
  static void invalidateChatThreadsStreamCache({
    String? tenantId,
    String? uid,
  }) {
    if (tenantId != null && uid != null) {
      _chatThreadsStreamByKey.remove('${tenantId.trim()}|${uid.trim()}');
      return;
    }
    _chatThreadsStreamByKey.clear();
  }

  /// Stream de conversas: uma instância por igreja+utilizador (estável como WhatsApp).
  static Stream<QuerySnapshot<Map<String, dynamic>>> chatThreadsSnapshotsForUser(
    String tenantId,
    String uid,
  ) {
    final key = '${tenantId.trim()}|${uid.trim()}';
    final cached = _chatThreadsStreamByKey[key];
    if (cached != null) return cached;
    final stream = _chatThreadsSnapshotsStreamImpl(tenantId, uid);
    _chatThreadsStreamByKey[key] = stream;
    return stream;
  }

  /// Web: lista de conversas só via cache + `.get()` — evita 2× `snapshots()` paralelos.
  static Stream<QuerySnapshot<Map<String, dynamic>>>
      _chatThreadsWebCacheFirstStream(
    String tenantId,
    String uid,
  ) {
    return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((ctrl) {
      unawaited(() async {
        try {
          final cached = await ChurchChatThreadsListCache.loadSnapshot(
            tenantId,
            uid: uid,
          );
          if (!ctrl.isClosed &&
              cached != null &&
              cached.docs.isNotEmpty) {
            ctrl.add(cached);
          }
        } catch (_) {}

        try {
          await FirestoreWebGuard.ensurePanelReadReady()
              .timeout(const Duration(seconds: 6))
              .catchError((_) {});
          final fb = await FirestoreWebGuard.runWithWebRecovery(() async {
            await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: false);
            return loadDmThreadsSnapshotFallback(
              tenantId: tenantId,
              uid: uid,
            );
          }).timeout(const Duration(seconds: 16));
          if (ctrl.isClosed) return;
          ctrl.add(fb);
          if (fb.docs.isNotEmpty) {
            unawaited(
              ChurchChatThreadsListCache.saveFromSnapshot(tenantId, fb),
            );
          }
        } catch (_) {
          if (!ctrl.isClosed) {
            ctrl.add(const MergedFirestoreQuerySnapshot([]));
          }
        }
      }());
    }).asBroadcastStream();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
      _chatThreadsSnapshotsStreamImpl(
    String tenantId,
    String uid,
  ) {
    if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
      return _chatThreadsWebCacheFirstStream(tenantId, uid);
    }
    late StreamController<QuerySnapshot<Map<String, dynamic>>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subIndexed;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subParticipant;
    QuerySnapshot<Map<String, dynamic>>? lastIndexed;
    QuerySnapshot<Map<String, dynamic>>? lastFallbackSnap;
    QuerySnapshot<Map<String, dynamic>>? lastParticipant;
    var wireAttempts = 0;
    var wiring = false;
    var fallbackInFlight = false;
    var fallbackAttempts = 0;
    QuerySnapshot<Map<String, dynamic>>? lastNonEmptyEmitted;
    Timer? suppressEmptyTimer;

    Future<void> runFallbackMerge(
      QuerySnapshot<Map<String, dynamic>> current,
    ) async {
      if (fallbackInFlight || controller.isClosed) return;
      if (fallbackAttempts >= 4) return;
      fallbackInFlight = true;
      fallbackAttempts++;
      try {
        await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
          force: fallbackAttempts > 1,
        );
        final fb = await loadDmThreadsSnapshotFallback(
          tenantId: tenantId,
          uid: uid,
        );
        if (controller.isClosed) return;
        lastFallbackSnap = fb;
        final combined =
            _mergeThreadSnapshots(uid, lastIndexed, fb, lastParticipant);
        if (combined.docs.length >= current.docs.length) {
          controller.add(combined);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('chatThreadsSnapshotsForUser fallback: $e');
        }
      } finally {
        fallbackInFlight = false;
      }
    }

    void emitMerged() {
      if (controller.isClosed) return;
      final merged = _mergeThreadSnapshots(
        uid,
        lastIndexed,
        lastFallbackSnap,
        lastParticipant,
      );
      if (merged.docs.isNotEmpty) {
        suppressEmptyTimer?.cancel();
        suppressEmptyTimer = null;
        lastNonEmptyEmitted = merged;
        controller.add(merged);
        unawaited(
          ChurchChatThreadsListCache.saveFromSnapshot(tenantId, merged),
        );
      } else if (lastNonEmptyEmitted != null &&
          lastNonEmptyEmitted!.docs.isNotEmpty) {
        controller.add(lastNonEmptyEmitted!);
        suppressEmptyTimer ??= Timer(const Duration(seconds: 3), () {
          suppressEmptyTimer = null;
          if (controller.isClosed) return;
          final again = _mergeThreadSnapshots(
            uid,
            lastIndexed,
            lastFallbackSnap,
            lastParticipant,
          );
          if (again.docs.isEmpty) {
            lastNonEmptyEmitted = null;
            controller.add(again);
          }
        });
      } else {
        controller.add(merged);
      }
      final hasListableDm =
          merged.docs.any((d) => _docIsDmForUserList(d, uid));
      if (!hasListableDm) {
        unawaited(runFallbackMerge(merged));
      }
    }

    Future<void> wire() async {
      if (wiring) return;
      wiring = true;
      try {
        await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
          force: wireAttempts > 0,
        );
        await subIndexed?.cancel();
        await subParticipant?.cancel();
        subIndexed = null;
        subParticipant = null;
        if (controller.isClosed) return;

        subIndexed = chatThreadsQueryForUser(tenantId, uid).watchSafe().listen(
          (event) {
            wireAttempts = 0;
            lastIndexed = event;
            emitMerged();
          },
          onError: (Object error, StackTrace stack) {
            if (controller.isClosed) return;
            if (FirestoreStreamUtils.isPermissionDenied(error)) {
              logChatFirestoreAccess(
                path:
                    'igrejas/$tenantId/chats?participantUids=arrayContains:$uid&orderBy=lastMessageAt',
                churchId: tenantId,
                error: error,
                stack: stack,
              );
            }
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

        subParticipant =
            chatThreadsParticipantQuery(tenantId, uid).watchSafe().listen(
          (event) {
            lastParticipant = event;
            emitMerged();
          },
          onError: (Object error, StackTrace stack) {
            if (controller.isClosed) return;
            lastParticipant = null;
            emitMerged();
            if (!FirestoreStreamUtils.isPermissionDenied(error)) {
              if (kDebugMode) {
                debugPrint('chatThreadsParticipantQuery: $error');
              }
            }
            unawaited(runFallbackMerge(
              _mergeThreadSnapshots(uid, lastIndexed, lastFallbackSnap, null),
            ));
          },
          cancelOnError: false,
        );

        unawaited(runFallbackMerge(const MergedFirestoreQuerySnapshot([])));
      } finally {
        wiring = false;
      }
    }

    controller = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
      onListen: () {
        wireAttempts = 0;
        fallbackAttempts = 0;
        unawaited(() async {
          try {
            final cached =
                await ChurchChatThreadsListCache.loadSnapshot(tenantId, uid: uid);
            if (!controller.isClosed &&
                cached != null &&
                cached.docs.isNotEmpty) {
              lastNonEmptyEmitted = cached;
              controller.add(cached);
            }
          } catch (_) {}
          if (!controller.isClosed) {
            unawaited(wire());
          }
        }());
      },
      onCancel: () {
        if (!controller.hasListener) {
          suppressEmptyTimer?.cancel();
          subIndexed?.cancel();
          subParticipant?.cancel();
          subIndexed = null;
          subParticipant = null;
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
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

  /// Leitura pontual de «a digitar» — evita `snapshots()` na conversa (teclado mais fluido).
  static Future<ChurchChatTypingActivity> fetchActiveTyping({
    required String tenantId,
    required String threadId,
    required String myUid,
  }) async {
    try {
      final snap = await typingCol(tenantId, threadId).get();
      final now = DateTime.now();
      final names = <String>[];
      var unnamed = 0;
      var recording = 0;
      for (final d in snap.docs) {
        if (d.id == myUid) continue;
        final data = d.data();
        final ts = data['updatedAt'];
        if (ts is! Timestamp) continue;
        if (now.difference(ts.toDate()).inSeconds > 5) continue;
        final lb = (data['label'] ?? '').toString().trim();
        if (lb == typingLabelRecording) {
          recording++;
        } else if (lb.isNotEmpty) {
          names.add(lb);
        } else {
          unnamed++;
        }
      }
      return ChurchChatTypingActivity(
        names: names,
        unnamed: unnamed,
        recording: recording,
      );
    } catch (_) {
      return const ChurchChatTypingActivity();
    }
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

  /// Motivo pelo qual a mensagem não pode ser reencaminhada (`null` = OK).
  static String? forwardBlockReason(Map<String, dynamic> messageData) {
    final type = (messageData['type'] ?? 'text').toString().trim();
    if (type == 'video') {
      return 'Vídeos não podem ser reencaminhados no chat.';
    }
    if (type == 'text') {
      final text = (messageData['text'] ?? '').toString().trim();
      if (text.isEmpty) return 'Mensagem vazia.';
      return null;
    }
    if (ChurchChatMessageFields.isUploadInProgress(messageData)) {
      return 'Aguarde o envio terminar antes de reencaminhar.';
    }
    final sp = _storagePathForForward(messageData);
    if (sp.isEmpty) {
      return 'Mídia ainda não disponível para reencaminhar.';
    }
    return null;
  }

  static String _storagePathForForward(Map<String, dynamic> messageData) {
    var sp = ChurchChatMessageFields.storagePath(messageData);
    if (sp.isNotEmpty) return sp;
    sp = StorageMediaService.storageObjectPathFromPathOrUrl(
          ChurchChatMessageFields.mediaUrl(messageData),
        ) ??
        '';
    return sp.trim();
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
    if (forwardBlockReason(messageData) != null) return false;
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
    final sp = _storagePathForForward(messageData);
    if (sp.isEmpty) return false;
    return sendMediaMessage(
      tenantId: tenantId,
      threadId: targetThreadId,
      storagePath: sp,
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
    final u = firebaseDefaultAuth.currentUser;
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
      final q = await           ChurchOperationalPaths.churchDoc(tenantId)
          .collection('membros')
          .where('departamentosIds', arrayContains: deptId)
          .limit(YahwehPerformanceV4.chatThreadsListLimit)
          .get();
      final out = q.docs.where((doc) => isActive(doc.data())).toList();
      out.sort(nameCmp);
      return out;
    } catch (_) {
      final all = await           ChurchOperationalPaths.churchDoc(tenantId)
          .collection('membros')
          .limit(YahwehPerformanceV4.chatThreadsListLimit)
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final op = ChurchRepository.churchId(tid.trim());
    await         ChurchOperationalPaths.churchDoc(op)
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return;
    final op = ChurchRepository.churchId(tenantId.trim());
    await         ChurchOperationalPaths.churchDoc(op)
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
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
  }) =>
      ChatPresenceEngine.fetchOnlineMap(
        churchId: tenantId,
        authUids: authUids,
      );

  /// Atualiza `lastSeenAtByUid.{uid}` no thread (DM ou grupo) para recibos de leitura na DM.
  static Future<bool> deleteMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
      }
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => messagesCol(tenantId, threadId).doc(messageId).delete(),
      );
      return true;
    } catch (e) {
      debugPrint('ChurchChatService.deleteMessage: $e');
      return false;
    }
  }

  /// «Apagar para mim» — mantém o documento; outros continuam a ver.
  static Future<bool> hideMessageForMe({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
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

  /// Mensagens recebidas (não enviadas por [myUid]) desde a última leitura — badge estilo WhatsApp.
  static Future<int> threadUnreadInboundCount({
    required String tenantId,
    required String threadId,
    required String myUid,
    Timestamp? myLastSeenInThread,
    int scanLimit = 60,
  }) async {
    final tid = tenantId.trim();
    final th = threadId.trim();
    if (tid.isEmpty || th.isEmpty || myUid.isEmpty) return 0;
    try {
      final snap = await messagesCol(tid, th)
          .orderBy('createdAt', descending: true)
          .limit(scanLimit)
          .get();
      var n = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['senderUid'] ?? '').toString() == myUid) continue;
        if (messageHiddenForMe(d, myUid)) continue;
        final created = d['createdAt'];
        if (created is! Timestamp) continue;
        if (myLastSeenInThread != null &&
            !created.toDate().isAfter(myLastSeenInThread.toDate())) {
          break;
        }
        n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markThreadLastSeen({
    required String tenantId,
    required String threadId,
  }) async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => threadRef(tid, threadId).update({
          'lastSeenAtByUid.$uid': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
      unawaited(
        markInboundMessagesDelivered(
          tenantId: tid,
          threadId: threadId,
        ),
      );
    } catch (_) {}
  }

  /// Marca mensagens recebidas como `delivered` (âœ“âœ“ cinza no remetente) ao abrir a conversa.
  static Future<void> markInboundMessagesDelivered({
    required String tenantId,
    required String threadId,
    int limit = 40,
  }) async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await messagesCol(tenantId, threadId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      final batch = _db.batch();
      var n = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['senderUid'] ?? '').toString() == uid) continue;
        final ds = (d['deliveryStatus'] ?? '').toString();
        if (ds != deliverySent) continue;
        batch.update(doc.reference, {'deliveryStatus': deliveryDelivered});
        n++;
        if (n >= 25) break;
      }
      if (n > 0) await batch.commit();
    } catch (_) {}
  }

  /// DM: quando o parceiro abriu a conversa, marca as **suas** mensagens como `read` (âœ“âœ“ azul).
  static Future<void> markOutboundMessagesReadUpTo({
    required String tenantId,
    required String threadId,
    required DateTime peerSeenAt,
  }) async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || !threadId.startsWith('dm_')) return;
    final seenMs = peerSeenAt.millisecondsSinceEpoch;
    try {
      final snap = await messagesCol(tenantId, threadId)
          .orderBy('createdAt', descending: true)
          .limit(40)
          .get();
      final batch = _db.batch();
      var n = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['senderUid'] ?? '').toString() != uid) continue;
        final ct = d['createdAt'];
        if (ct is! Timestamp) continue;
        if (ct.millisecondsSinceEpoch > seenMs) continue;
        final ds = (d['deliveryStatus'] ?? '').toString();
        if (ds == deliveryRead) continue;
        if (ds == deliverySent ||
            ds == deliveryDelivered ||
            ds.isEmpty) {
          batch.update(doc.reference, {'deliveryStatus': deliveryRead});
          n++;
          if (n >= 25) break;
        }
      }
      if (n > 0) await batch.commit();
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
    await runFirestorePublishWithRecovery<void>(() async {
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
    });
  }

  /// Atalhos do painel / membros — bootstrap + até 3 tentativas antes de abrir o hub.
  static Future<bool> ensureDmThreadResilient({
    required String tenantId,
    required String uidA,
    required String uidB,
    required String titleA,
    required String titleB,
  }) async {
    await ensureFirebaseReadyForChatSend().catchError((_) {});
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (kIsWeb && attempt > 0) {
          await FirestoreWebGuard.recoverFirestoreWebSession(
            allowHardReconnect: lastError != null &&
                FirestoreWebGuard.isClientTerminated(lastError!),
          );
        }
        await ensureDmThread(
          tenantId: tenantId,
          uidA: uidA,
          uidB: uidB,
          titleA: titleA,
          titleB: titleB,
        ).timeout(const Duration(seconds: 18));
        return true;
      } on TimeoutException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    if (kDebugMode && lastError != null) {
      debugPrint('ensureDmThreadResilient failed: $lastError');
    }
    return false;
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
    final r = await writeTextMessageFirestoreOnce(
      tenantId: tenantId,
      threadId: threadId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
    );
    if (!r.allowed) return false;
    unawaited(AnalyticsService.logMessage());
    return true;
  }

  /// Texto: **uma** gravação Firestore (`status: sent`) — sem fila intermédia.
  static Future<({String messageId, bool allowed})> writeTextMessageFirestoreOnce({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
  }) async {
    ChurchPublishFlowLog.chatStart();
    final tid = ChurchPanelTenant.resolve(tenantId);
    await ensureFirebaseReadyForChatSend();
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tid,
      threadId: threadId,
    )) {
      return (messageId: '', allowed: false);
    }
    unawaited(
      ChurchChatMemberPrefs.revealDmThreadOnOutbound(
        tenantId: tid,
        threadId: threadId,
      ),
    );
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(textRetention));
    final msgRef = messagesCol(tid, threadId).doc();
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
    final label = (senderDisplayName ?? '').trim();
    final mentions = (mentionedUids ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.length > 4)
        .toSet()
        .take(24)
        .toList();
    final preview = nf != null
        ? '↪ ${nf['preview']}'
        : (text.length > 120 ? '${text.substring(0, 117)}…' : text);

    Future<void> commitOnce({required String deliveryStatus}) =>
        _commitMessageAndThreadIndex(
          tenantId: tid,
          threadId: threadId,
          msgRef: msgRef,
          messageData: {
            'senderUid': uid,
            'senderId': uid,
            'type': 'text',
            'text': text,
            'deliveryStatus': deliveryStatus,
            'status': deliveryStatus,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': expiresAt,
            if (nr != null) 'replyTo': nr,
            if (nf != null) 'forwardedFrom': nf,
            if (label.isNotEmpty) ...{
              'senderDisplayName':
                  label.length > 100 ? label.substring(0, 100) : label,
              'senderName':
                  label.length > 100 ? label.substring(0, 100) : label,
            },
            if (mentions.isNotEmpty) 'mentionedUids': mentions,
          },
          preview: preview,
          senderUid: uid,
          messageType: 'text',
        );

    try {
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
      }
      await _ensureDmThreadDocBeforeSend(tid, threadId);
      final deliveryStatus = AppConnectivityService.instance.isOnline
          ? deliverySent
          : deliveryLocal;
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => commitOnce(deliveryStatus: deliveryStatus),
      );
      unawaited(
        markThreadLastSeen(tenantId: tid, threadId: threadId),
      );
      ChurchPublishFlowLog.chatMessageCreated();
      ChurchPublishFlowLog.chatSuccess();
      return (messageId: msgRef.id, allowed: true);
    } catch (e, st) {
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
  }

  static Future<void> finalizeTextMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
  }) async {
    await ensureFirebaseReadyForChatSend();
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final nf = normalizeForwardedFrom(forwardedFrom);
    final preview = nf != null
        ? '↪ ${nf['preview']}'
        : (text.length > 120 ? '${text.substring(0, 117)}…' : text);
    Object? last;
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        await runFirestorePublishWithRecovery(() async {
          await messagesCol(tenantId, threadId).doc(messageId).update({
            'deliveryStatus': deliverySent,
            'status': deliverySent,
          });
          await threadRef(tenantId, threadId).set(
            threadLastMessageIndexPatch(
              preview: preview,
              senderUid: uid,
              messageType: 'text',
            ),
            SetOptions(merge: true),
          );
        });
        ChurchPublishFlowLog.chatMessageUpdated();
        ChurchPublishFlowLog.chatFinalOk();
        unawaited(
          ChurchChatLocalConversations.recordFromOutbound(
            tenantId: tenantId,
            myUid: uid,
            threadId: threadId,
            preview: preview,
            messageType: 'text',
          ),
        );
        return;
      } catch (e) {
        last = e;
        if (attempt >= 5) break;
        await Future.delayed(Duration(milliseconds: 280 * attempt));
      }
    }
    throw last ?? StateError('Não foi possível concluir o envio da mensagem.');
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
    required String storagePath,
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
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    final nr = normalizeReplyTo(replyTo);
    final sp = storagePath.trim();
    final label = (senderDisplayName ?? '').trim();
    await msgRef.set({
      'senderUid': uid,
      'type': 'sticker',
      'storagePath': sp,
      'deliveryStatus': deliverySending,
      'status': deliverySending,
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
    required String storagePath,
    String stickerSource = 'upload',
  }) async {
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: 'sticker',
      fileName: null,
    );
    final sp = storagePath.trim();
    await messagesCol(tenantId, threadId).doc(messageId).update({
      'storagePath': sp,
      'mediaUrl': FieldValue.delete(),
      'stickerSource': stickerSource,
      'deliveryStatus': deliverySent,
      'status': deliverySent,
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
    required String storagePath,
    required String kind,
    String? fileName,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
  }) async {
    if (ChurchChatAttachmentUtils.blockReasonForChatKind(kind) != null) {
      return false;
    }
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: tenantId,
      threadId: threadId,
    )) {
      return false;
    }
    final uid = firebaseDefaultAuth.currentUser!.uid;
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
      'storagePath': storagePath.trim(),
      'deliveryStatus': deliverySent,
      'status': deliverySent,
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
    required String storagePath,
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
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(tenantId, threadId).doc();
    final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
      kind: 'sticker',
      fileName: null,
    );
    final nr = normalizeReplyTo(replyTo);
    final sp = storagePath.trim();
    final label = (senderDisplayName ?? '').trim();
    await msgRef.set({
      'senderUid': uid,
      'type': 'sticker',
      'storagePath': sp,
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
    await ensureFirebaseReadyForChatSend();
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'igrejas/$tenantId/chat_stickers/${uid}_${ts}_$safeName';
    final ubytes =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final url = await UnifiedUploadService.uploadImage(
      storagePath: path,
      bytes: ubytes,
      contentType: contentType,
      module: YahwehUploadModule.chat,
      skipClientPrepare: true,
    );
    return (url: url, path: path);
  }

  /// Regista figurinha importada na biblioteca da igreja.
  static Future<String?> registerStickerPackEntry({
    required String tenantId,
    required String mediaUrl,
    required String storagePath,
    String label = '',
  }) async {
    final uid = firebaseDefaultAuth.currentUser!.uid;
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
    final uid = firebaseDefaultAuth.currentUser?.uid;
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
        await firebaseStorageRef(path).delete();
      } catch (_) {}
    }
    try {
      await ref.delete();
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Id estável da mensagem — alinha `chats/…/messages/{id}` e `chat_uploads/{id}`.
  static String allocateMediaMessageId({
    required String tenantId,
    required String threadId,
  }) {
    final resolved =
        ChurchPublishContext.churchIdForPublish(tenantId.trim());
    return messagesCol(resolved, threadId).doc().id;
  }

  /// Storage canónico por messageId: `igrejas/{churchId}/chat_media/{tipo}/{messageId}.ext`
  static String buildChatMediaStoragePathForMessage({
    required String tenantId,
    required String messageId,
    required String kind,
    required String fileName,
  }) =>
      ChurchStorageLayout.buildChatMediaPathForMessage(
        tenantId: ChurchPublishContext.churchIdForPublish(tenantId.trim()),
        messageId: messageId,
        kind: kind,
        fileName: fileName,
      );

  /// Caminho Storage legado (uid+timestamp) — só retoma/migração.
  static String buildChatMediaStoragePath({
    required String tenantId,
    required String threadId,
    required String kind,
    required String fileName,
  }) {
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return ChurchStorageLayout.buildChatMediaObjectPath(
      tenantId: tenantId,
      threadId: threadId,
      kind: kind,
      uid: uid,
      timestampMs: ts,
      fileName: fileName,
    );
  }

  static String buildChatImageThumbStoragePathForMessage({
    required String tenantId,
    required String messageId,
  }) =>
      ChurchStorageLayout.buildChatMediaThumbPathForMessage(
        tenantId: ChurchPublishContext.churchIdForPublish(tenantId.trim()),
        messageId: messageId,
        suffix: 'image',
      );

  static String buildChatVideoThumbStoragePathForMessage({
    required String tenantId,
    required String messageId,
  }) =>
      ChurchStorageLayout.buildChatMediaThumbPathForMessage(
        tenantId: ChurchPublishContext.churchIdForPublish(tenantId.trim()),
        messageId: messageId,
        suffix: 'video',
      );

  static String buildChatVideoThumbStoragePath({
    required String tenantId,
    required String threadId,
    int? timestampMs,
  }) {
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    return ChurchStorageLayout.buildChatMediaThumbPath(
      tenantId: tenantId,
      uid: uid,
      timestampMs: ts,
      suffix: 'video',
    );
  }

  static String buildChatImageThumbStoragePath({
    required String tenantId,
    required String threadId,
    int? timestampMs,
  }) {
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    return ChurchStorageLayout.buildChatMediaThumbPath(
      tenantId: tenantId,
      uid: uid,
      timestampMs: ts,
      suffix: 'image',
    );
  }

  /// Extrai `timestampMs` do segmento `{uid}_{ts}_{name}` no path Storage.
  static int? timestampMsFromChatMediaPath(String path) {
    final name = path.split('/').last;
    final m = RegExp(r'^[A-Za-z0-9]+_(\d+)_').firstMatch(name);
    if (m != null) return int.tryParse(m.group(1)!);
    final legacy = RegExp(r'/(\d+)_').firstMatch(path);
    if (legacy == null) return null;
    return int.tryParse(legacy.group(1)!);
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
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    await ensureFirebaseReadyForChatSend();
    final resolvedTenant = ChurchPublishContext.churchIdForPublish(
      tenantId.trim(),
    );
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: resolvedTenant,
      threadId: threadId,
    )) {
      throw StateError('Envio bloqueado para este contacto.');
    }
    unawaited(
      ChurchChatMemberPrefs.revealDmThreadOnOutbound(
        tenantId: resolvedTenant,
        threadId: threadId,
      ),
    );
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final storagePath = buildChatMediaStoragePath(
      tenantId: resolvedTenant,
      threadId: threadId,
      kind: kind,
      fileName: fileName ?? _defaultFileNameForKind(kind),
    );
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final msgRef = messagesCol(resolvedTenant, threadId).doc();
    final gid = (albumGroupId ?? '').trim();
    final aCount = albumCount < 1 ? 1 : albumCount;
    var preview = gid.isNotEmpty && aCount > 1
        ? ChurchChatAlbumUtils.threadPreviewForAlbum(
            aCount,
            hasVideo: kind == 'video',
          )
        : ChurchChatAttachmentUtils.previewForThreadLastMessage(
            kind: kind,
            fileName: fileName,
          );
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
    if (nf != null) {
      preview = '↪ ${nf['preview']}';
    }
    final label = (senderDisplayName ?? '').trim();
    await _ensureDmThreadDocBeforeSend(resolvedTenant, threadId);
    await _commitMessageAndThreadIndex(
      tenantId: resolvedTenant,
      threadId: threadId,
      msgRef: msgRef,
      messageData: {
        'senderUid': uid,
        'senderId': uid,
        'type': kind,
        'deliveryStatus': deliveryUploading,
        'status': deliveryUploading,
        'uploadProgress': 0,
        'uploadCompleted': false,
        'storageVerified': false,
        'pendingMedia': true,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
        if (fileName != null && fileName.trim().isNotEmpty)
          'fileName': fileName.trim(),
        if (nr != null) 'replyTo': nr,
        if (nf != null) 'forwardedFrom': nf,
        if (gid.isNotEmpty) ...{
          'albumGroupId': gid,
          'albumIndex': albumIndex,
          'albumCount': aCount,
        },
        'storagePath': storagePath,
        if (label.isNotEmpty) ...{
          'senderDisplayName':
              label.length > 100 ? label.substring(0, 100) : label,
          'senderName':
              label.length > 100 ? label.substring(0, 100) : label,
        },
      },
      preview: preview,
      senderUid: uid,
      messageType: kind,
    );
    ChurchPublishFlowLog.chatMessageCreated();
    return (messageId: msgRef.id, storagePath: storagePath);
  }

  /// Mídia: **upload Storage concluído** → uma gravação Firestore (`status: sent`).
  /// Inclui `mediaUrl` https para visualização imediata (painel, site, chat).
  static Future<({String messageId, bool allowed})> writeMediaMessageFirestoreOnce({
    required String tenantId,
    required String threadId,
    required String kind,
    required String storagePath,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    String? fileName,
    int? fileSize,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
    int? voiceDurationMs,
    /// Id pré-alocado (mesmo de `chat_uploads/{messageId}`).
    String? messageId,
    /// Após [EcoFireStorageUpload.putData] concluído — evita re-verificação lenta na Web.
    bool skipStorageVerify = false,
  }) async {
    ChurchPublishFlowLog.chatStart();
    await ensureFirebaseReadyForChatSend();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
    }
    final resolvedTenant =
        ChurchPublishContext.churchIdForPublish(tenantId.trim());
    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: resolvedTenant,
      threadId: threadId,
    )) {
      return (messageId: '', allowed: false);
    }
    await ChurchChatMemberPrefs.revealDmThreadOnOutbound(
      tenantId: resolvedTenant,
      threadId: threadId,
    );
    if (!skipStorageVerify) {
      await assertChatMediaUploaded(
        storagePath,
        thumbStoragePath: thumbStoragePath,
      );
    }
    final uid = firebaseDefaultAuth.currentUser!.uid;
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(mediaRetention));
    final preId = (messageId ?? '').trim();
    final msgRef = preId.isNotEmpty
        ? messagesCol(resolvedTenant, threadId).doc(preId)
        : messagesCol(resolvedTenant, threadId).doc();
    final gid = (albumGroupId ?? '').trim();
    final aCount = albumCount < 1 ? 1 : albumCount;
    var preview = gid.isNotEmpty && aCount > 1
        ? ChurchChatAlbumUtils.threadPreviewForAlbum(
            aCount,
            hasVideo: kind == 'video',
          )
        : ChurchChatAttachmentUtils.previewForThreadLastMessage(
            kind: kind,
            fileName: fileName,
          );
    final nr = normalizeReplyTo(replyTo);
    final nf = normalizeForwardedFrom(forwardedFrom);
    if (nf != null) {
      preview = '↪ ${nf['preview']}';
    }
    final label = (senderDisplayName ?? '').trim();
    final data = <String, dynamic>{
      'senderUid': uid,
      'senderId': uid,
      'type': kind,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      ...ChurchChatMessageFields.mediaWritePatch(
        storagePath: storagePath,
        thumbStoragePath: thumbStoragePath,
        mediaUrl: mediaUrl,
        thumbUrl: thumbUrl,
        fileName: fileName,
        fileSize: fileSize,
        voiceDurationSeconds: voiceDurationMs != null && voiceDurationMs > 0
            ? (voiceDurationMs / 1000).ceil()
            : null,
        deliveryStatus: deliverySent,
      ),
      if (nr != null) 'replyTo': nr,
      if (nf != null) 'forwardedFrom': nf,
      if (gid.isNotEmpty) ...{
        'albumGroupId': gid,
        'albumIndex': albumIndex,
        'albumCount': aCount,
      },
      if (label.isNotEmpty) ...{
        'senderDisplayName':
            label.length > 100 ? label.substring(0, 100) : label,
        'senderName':
            label.length > 100 ? label.substring(0, 100) : label,
      },
    };
    await _ensureDmThreadDocBeforeSend(resolvedTenant, threadId);
    Object? last;
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        if (attempt > 1) {
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
          await ensureFirebaseReadyForChatSend();
          await Future<void>.delayed(Duration(milliseconds: 240 * attempt));
        }
        if (kIsWeb) {
          await FirestoreWebGuard.runChatWriteWithRecovery(
            () => _commitMessageAndThreadIndex(
              tenantId: resolvedTenant,
              threadId: threadId,
              msgRef: msgRef,
              messageData: ChurchChatMessageFields.withCanonicalAliases(data),
              preview: preview,
              senderUid: uid,
              messageType: kind,
            ),
          );
        } else {
          await _commitMessageAndThreadIndex(
            tenantId: resolvedTenant,
            threadId: threadId,
            msgRef: msgRef,
            messageData: ChurchChatMessageFields.withCanonicalAliases(data),
            preview: preview,
            senderUid: uid,
            messageType: kind,
          );
        }
        ChurchPublishFlowLog.chatMessageCreated();
        ChurchPublishFlowLog.chatFileUploaded();
        ChurchPublishFlowLog.chatFinalOk();
        return (messageId: msgRef.id, allowed: true);
      } catch (e) {
        last = e;
        if (attempt >= 5) break;
      }
    }
    throw last ?? StateError('Não foi possível gravar a mensagem no servidor.');
  }

  /// Patch permitido pelas regras Firestore (`chatMessageMediaDeliveryPatchAllowed`).
  /// Inclui `mediaUrl` https após upload Storage (Controle Total / EcoFire).
  static Map<String, dynamic> mediaUploadFinalizePatch({
    required String storagePath,
    String? thumbStoragePath,
    String? fileName,
    String? mediaUrl,
    String? thumbUrl,
  }) {
    final sp = storagePath.trim();
    final patch = <String, dynamic>{
      'storagePath': sp,
      'deliveryStatus': deliverySent,
      'status': deliverySent,
      'uploadProgress': 1,
      'uploadCompleted': true,
      'storageVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'pendingMedia': FieldValue.delete(),
      'erro': FieldValue.delete(),
      'errorMessage': FieldValue.delete(),
    };
    final url = (mediaUrl ?? '').trim();
    if (url.length > 8) {
      patch['mediaUrl'] = url;
      patch['fileUrl'] = url;
    }
    final thumbPath = (thumbStoragePath ?? '').trim();
    if (thumbPath.isNotEmpty) {
      patch['thumbStoragePath'] = thumbPath;
    }
    final thumbHttps = (thumbUrl ?? '').trim();
    if (thumbHttps.length > 8) {
      patch['thumbUrl'] = thumbHttps;
      patch['thumbnailUrl'] = thumbHttps;
    }
    if (fileName != null && fileName.trim().isNotEmpty) {
      patch['fileName'] = fileName.trim();
    }
    return ChurchChatMessageFields.withCanonicalAliases(patch);
  }

  /// Valida objeto no bucket antes de finalizar mensagem.
  static Future<void> assertChatMediaUploaded(
    String storagePath, {
    String? thumbStoragePath,
  }) async {
    await ChatPublishVerificationService.verifyStorageMetadata(
      storagePath: storagePath,
      thumbStoragePath: thumbStoragePath,
    );
  }

  /// Completa o stub após upload no Storage (upload + metadata já concluídos).
  static Future<bool> completeMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String storagePath,
    String? fileName,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    int? fileSize,
  }) async {
    final resolvedTenant =
        await ChatPublishVerificationService.resolveTenantForPublish(
      seedTenantId: tenantId,
    );
    await assertChatMediaUploaded(
      storagePath,
      thumbStoragePath: thumbStoragePath,
    );
    return completeMediaUploadMessageDirect(
      resolvedTenant: resolvedTenant,
      threadId: threadId,
      messageId: messageId,
      storagePath: storagePath,
      fileName: fileName,
      thumbStoragePath: thumbStoragePath,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      fileSize: fileSize,
    );
  }

  /// Grava `sent` no doc já resolvido (sem re-verificar Storage — caller validou).
  static Future<bool> completeMediaUploadMessageDirect({
    required String resolvedTenant,
    required String threadId,
    required String messageId,
    required String storagePath,
    String? fileName,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    int? fileSize,
  }) async {
    final patch = mediaUploadFinalizePatch(
      storagePath: storagePath,
      thumbStoragePath: thumbStoragePath,
      fileName: fileName,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
    );
    if (fileSize != null && fileSize > 0) {
      patch['fileSize'] = fileSize;
      patch['size'] = fileSize;
    }
    final ref = ChatPublishVerificationService.messageDocRef(
      igrejaId: resolvedTenant,
      threadId: threadId,
      messageId: messageId,
    );
    Future<void> writeMessage() async {
      try {
        await FirestoreWebGuard.runChatWriteWithRecovery(() => ref.update(patch));
      } on FirebaseException catch (e) {
        if (patch.containsKey('thumbStoragePath') && e.code == 'permission-denied') {
          patch.remove('thumbStoragePath');
          await ref.update(patch);
        } else {
          rethrow;
        }
      }
    }

    await AdminFeedFirestoreBridge.upsertDocRef(
      docRef: ref,
      data: patch,
      isNewDoc: false,
      useUpdate: true,
      directWrite: writeMessage,
    );
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      final kind = (await ref.get()).data()?['type']?.toString() ?? 'image';
      final preview = ChurchChatAttachmentUtils.previewForThreadLastMessage(
        kind: kind,
        fileName: fileName,
      );
      try {
        final tRef = threadRef(resolvedTenant, threadId);
        final threadPatch = threadLastMessageIndexPatch(
          preview: preview,
          senderUid: uid,
          messageType: kind,
        );
        await AdminFeedFirestoreBridge.upsertDocRef(
          docRef: tRef,
          data: threadPatch,
          isNewDoc: false,
          directWrite: () => tRef.set(threadPatch, SetOptions(merge: true)),
        );
        unawaited(
          ChurchChatLocalConversations.recordFromOutbound(
            tenantId: resolvedTenant,
            myUid: uid,
            threadId: threadId,
            preview: preview,
            messageType: kind,
          ),
        );
      } catch (_) {}
    }
    return true;
  }

  /// Android/iOS: rede instável pode falhar o `update` após o Storage já ter recebido o ficheiro.
  static Future<bool> completeMediaUploadMessageWithRetry({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String storagePath,
    String? fileName,
    String? thumbStoragePath,
    int? fileSize,
    int maxAttempts = 5,
    bool skipStorageVerify = false,
  }) async {
    await ensureFirebaseReadyForChatSend();
    if (!skipStorageVerify) {
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded();
    }
    Object? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (attempt > 2 && !skipStorageVerify) {
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
          await ensureFirebaseReadyForChatSend();
        }
        await ChatStrictPublishService.finalizeMediaMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
          storagePath: storagePath,
          fileName: fileName,
          thumbStoragePath: thumbStoragePath,
          fileSize: fileSize,
          skipStorageVerify: skipStorageVerify,
          skipServerRecheck: skipStorageVerify,
        );
        return true;
      } catch (e) {
        last = e;
        if (attempt >= maxAttempts) break;
        await Future.delayed(
          Duration(milliseconds: 280 * attempt),
        );
      }
    }
    try {
      await markMediaUploadFailed(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        errorMessage: last?.toString(),
      );
    } catch (_) {}
    throw last ?? StateError('Não foi possível concluir o envio no servidor.');
  }

  static String _defaultFileNameForKind(String kind) => switch (kind) {
        'image' => 'foto.webp',
        'video' => 'video.mp4',
        'audio' => 'audio.m4a',
        _ => 'media',
      };

  /// Marca stub como aguardando rede (reenvio automático).
  static Future<void> markMediaUploadQueued({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      final ref = await _messageDocResolved(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );
      await ref.update({
        'deliveryStatus': deliveryQueued,
        'status': deliveryQueued,
        'uploadProgress': 0,
        'uploadCompleted': false,
      });
    } catch (_) {}
  }

  static Future<void> markMediaUploadActive({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      final ref = await _messageDocResolved(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );
      await ref.update({
        'deliveryStatus': deliveryUploading,
        'status': deliveryUploading,
        'uploadProgress': 0,
        'uploadCompleted': false,
      });
    } catch (_) {}
  }

  static final Map<String, double> _uploadProgressPatchCache = {};

  /// Atualiza progresso no stub (0–1; regras: só `uploadProgress` enquanto `uploading`).
  static Future<void> patchMediaUploadProgress({
    required String tenantId,
    required String threadId,
    required String messageId,
    required double progress,
    bool force = false,
  }) async {
    final clamped = progress.clamp(0.0, 1.0);
    final key = '$tenantId/$threadId/$messageId';
    final last = _uploadProgressPatchCache[key];
    if (!force &&
        last != null &&
        clamped < 1 &&
        (clamped - last).abs() < 0.04) {
      return;
    }
    _uploadProgressPatchCache[key] = clamped;
    if (clamped >= 1) {
      _uploadProgressPatchCache.remove(key);
    }
    try {
      final ref = await _messageDocResolved(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );
      await ref.update({
        'uploadProgress': clamped,
        'deliveryStatus': deliveryUploading,
        'status': deliveryUploading,
      });
    } catch (_) {}
  }

  /// Falha definitiva — nunca deixar `uploading` eterno.
  static Future<void> markMediaUploadFailed({
    required String tenantId,
    required String threadId,
    required String messageId,
    String? errorMessage,
  }) async {
    final msg = (errorMessage ?? 'Falha ao enviar mídia.').trim();
    final short = msg.length > 240 ? msg.substring(0, 240) : msg;
    try {
      final ref = await _messageDocResolved(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );
      await ref.update({
        'deliveryStatus': 'failed',
        'status': 'failed',
        'uploadProgress': 0,
        'uploadCompleted': false,
        'storageVerified': false,
        'pendingMedia': false,
        'erro': short,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<DocumentReference<Map<String, dynamic>>> _messageDocResolved({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    final resolved =
        await ChatPublishVerificationService.resolveTenantForPublish(
      seedTenantId: tenantId,
    );
    return ChatPublishVerificationService.messageDocRef(
      igrejaId: resolved,
      threadId: threadId,
      messageId: messageId,
    );
  }

  /// Remove stub se o upload falhar de forma irrecuperável.
  static Future<void> abandonMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      final ref = await _messageDocResolved(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );
      await ref.delete();
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
    await ensureFirebaseReadyForChatSend();
    final path = storagePathOverride ??
        buildChatMediaStoragePath(
          tenantId: tenantId,
          threadId: threadId,
          kind: _kindFromContentType(contentType),
          fileName: fileName,
        );
    final ubytes =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final ct = contentType.toLowerCase();
    late final String url;
    if (skipClientPrepare) {
      url = await ChurchChatMediaStorage.putBytes(
        storagePath: path,
        bytes: ubytes,
        contentType: contentType,
        onProgress: onProgress,
      );
    } else if (ct.startsWith('image/')) {
      final chatJpegFast =
          ct.contains('jpeg') || ct == 'image/jpg' || ct == 'image/pjpeg';
      url = await UnifiedUploadService.uploadImage(
        storagePath: path,
        bytes: ubytes,
        contentType: contentType,
        module: YahwehUploadModule.chat,
        chatJpegFast: chatJpegFast,
        skipClientPrepare: skipClientPrepare,
        onProgress: onProgress,
        onUploadTaskCreated: onUploadTaskCreated,
      );
    } else {
      url = await ChurchChatMediaStorage.putBytes(
        storagePath: path,
        bytes: ubytes,
        contentType: contentType,
        onProgress: onProgress,
      );
    }
    await assertChatMediaUploaded(path);
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
    await ensureFirebaseReadyForChatSend();
    final path = storagePathOverride ??
        buildChatMediaStoragePath(
          tenantId: tenantId,
          threadId: threadId,
          kind: _kindFromContentType(contentType),
          fileName: fileName,
        );
    final url = await ChurchChatMediaStorage.putFile(
      storagePath: path,
      localPath: localPath,
      contentType: contentType,
      onProgress: onProgress,
    );
    await assertChatMediaUploaded(path);
    return (url: url, path: path);
  }

  static String _kindFromContentType(String contentType) {
    final ct = contentType.toLowerCase();
    if (ct.startsWith('image/')) return 'image';
    if (ct.startsWith('video/')) return 'video';
    if (ct.startsWith('audio/')) return 'audio';
    return 'document';
  }

  static Future<void> hideThreadForMe({
    required String tenantId,
    required String threadId,
  }) async {
    final uid = firebaseDefaultAuth.currentUser!.uid;
    await threadRef(tenantId, threadId).set(
      {
        'hiddenForUids': FieldValue.arrayUnion([uid]),
      },
      SetOptions(merge: true),
    );
  }

  /// Apaga thread de grupo (`dept_*`) e mensagens — só roles autorizados (regras Firestore).
  static Future<bool> deleteGroupThread({
    required String tenantId,
    required String threadId,
  }) async {
    final tid = threadId.trim();
    if (!tid.startsWith('dept_')) return false;
    try {
      await ensureFirebaseReadyForChatSend();
      final op = ChurchRepository.churchId(tenantId.trim());
      final resolved = op.trim().isEmpty ? tenantId.trim() : op.trim();

      final messages = messagesCol(resolved, tid);
      while (true) {
        final snap = await messages.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      try {
        final typing = threadRef(resolved, tid).collection('typing');
        final typingSnap = await typing.limit(200).get();
        if (typingSnap.docs.isNotEmpty) {
          final batch = _db.batch();
          for (final doc in typingSnap.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (_) {}

      await threadRef(resolved, tid).delete();
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('deleteGroupThread: $e');
      }
      return false;
    }
  }
}

