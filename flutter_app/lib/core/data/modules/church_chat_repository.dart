import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Chat igreja — threads, mensagens, realtime controlado (1 listener por thread).
final class ChurchChatRepository extends ChurchModuleRepositoryBase {
  const ChurchChatRepository()
      : super(
          moduleLabel: 'Chat',
          subcollection: ChurchDataPaths.chats,
        );

  static const ChurchChatRepository instance = ChurchChatRepository();

  CollectionReference<Map<String, dynamic>> threadsCol(String churchId) =>
      ChurchFirestoreAccess.collectionRef(churchId, ChurchDataPaths.chats);

  CollectionReference<Map<String, dynamic>> messagesCol(
    String churchId,
    String threadId,
  ) =>
      threadsCol(churchId).doc(threadId).collection('messages');

  Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      listThreads({
    String? churchIdHint,
    int limit = 50,
  }) =>
      list(churchIdHint: churchIdHint, limit: limit);

  Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      listMessagesOnce({
    required String threadId,
    String? churchIdHint,
    int limit = FirebasePerformanceLimits.chatMessagesPage,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) {
      return ChurchDataListResult(
        churchId: '',
        collectionPath: '',
        items: const [],
        readAt: DateTime.now(),
        error: 'churchId vazio',
      );
    }
    try {
      final snap = await messagesCol(id, threadId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return churchDataListFromSnapshot(
        churchId: id,
        collectionPath: '${pathFor(id)}/$threadId/messages',
        snap: snap,
      );
    } catch (e) {
      return ChurchDataListResult(
        churchId: id,
        collectionPath: '${pathFor(id)}/$threadId/messages',
        items: const [],
        readAt: DateTime.now(),
        error: '$e',
      );
    }
  }

  /// Realtime: mobile `snapshots()`; Web polling 6s (1 listener por thread).
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMessages({
    required String threadId,
    required void Function(QuerySnapshot<Map<String, dynamic>> snap) onData,
    String? churchIdHint,
    int limit = FirebasePerformanceLimits.chatMessagesPage,
  }) {
    final id = churchId(churchIdHint);
    if (!kIsWeb) {
      return messagesCol(id, threadId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .listen(onData);
    }
    return Stream.periodic(const Duration(seconds: 6)).asyncMap((_) async {
      final r = await listMessagesOnce(
        threadId: threadId,
        churchIdHint: id,
        limit: limit,
      );
      return MergedFirestoreQuerySnapshot(r.items);
    }).listen(onData);
  }

  Future<void> sendTextMessage({
    required String threadId,
    required Map<String, dynamic> payload,
    String? churchIdHint,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.runChatWriteWithRecovery(() async {
        await messagesCol(churchId(churchIdHint), threadId).add(payload);
      });
      return;
    }
    await messagesCol(churchId(churchIdHint), threadId).add(payload);
  }
}
