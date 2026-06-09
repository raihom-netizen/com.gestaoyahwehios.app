import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Caixa de entrada interna — além do push (avisos, eventos, escalas, chat…).
abstract final class InternalNotificationInboxService {
  InternalNotificationInboxService._();

  static CollectionReference<Map<String, dynamic>> _inbox(String uid) =>
      firebaseDefaultFirestore
          .collection('usuarios')
          .doc(uid)
          .collection('caixa_entrada');

  static Future<void> deliver({
    required String uid,
    required String type,
    required String title,
    String? body,
    String? tenantId,
    String? deepLink,
    Map<String, dynamic>? meta,
  }) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    try {
      await _inbox(u).add({
        'type': type,
        'title': title,
        if (body != null && body.isNotEmpty) 'body': body,
        if (tenantId != null) 'tenantId': tenantId,
        if (deepLink != null) 'deepLink': deepLink,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        if (meta != null) 'meta': meta,
      });
    } catch (_) {}
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watch(String uid, {int limit = 80}) {
    return _inbox(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .watchSafe();
  }

  static Future<void> markRead(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.update({'read': true, 'readAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  static Future<int> unreadCount(String uid) async {
    try {
      final q = await _inbox(uid).where('read', isEqualTo: false).count().get();
      return q.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Stream<int> watchUnreadCount(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return Stream.value(0);
    return watch(u, limit: 120).map((snap) {
      var n = 0;
      for (final d in snap.docs) {
        if (d.data()['read'] != true) n++;
      }
      return n;
    });
  }

  static Future<void> markAllRead(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    try {
      final snap = await _inbox(u)
          .where('read', isEqualTo: false)
          .limit(120)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = firebaseDefaultFirestore.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Espelha push FCM na caixa pessoal (feed unificado no sino).
  static Future<void> deliverFromRemoteMessage({
    required String uid,
    required String type,
    required String title,
    String? body,
    String? tenantId,
    Map<String, dynamic>? meta,
  }) async {
    await deliver(
      uid: uid,
      type: type,
      title: title,
      body: body,
      tenantId: tenantId,
      meta: meta,
    );
  }
}
