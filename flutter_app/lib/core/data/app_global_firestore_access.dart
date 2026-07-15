import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Firestore **global** (raiz) — `config/`, `users/`, `suggestions/`.
///
/// Não confundir com [ChurchRepository] (`igrejas/{churchId}/…`).
/// Telas do painel igreja e master usam isto em vez de `FirebaseFirestore.instance`.
abstract final class AppGlobalFirestoreAccess {
  AppGlobalFirestoreAccess._();

  static FirebaseFirestore get db => firebaseDefaultFirestore;

  static DocumentReference<Map<String, dynamic>> configDoc(String docId) =>
      db.collection('config').doc(docId.trim());

  static CollectionReference<Map<String, dynamic>> get suggestions =>
      db.collection('suggestions');

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      db.collection('users').doc(uid.trim());

  static CollectionReference<Map<String, dynamic>> planItems() =>
      configDoc('plans').collection('items');

  static Future<DocumentSnapshot<Map<String, dynamic>>> getConfig(
    String docId, {
    Source source = Source.serverAndCache,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(
        () => configDoc(docId).get(GetOptions(source: source)),
      );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchConfig(
    String docId,
  ) =>
      FirestoreStreamUtils.documentWatchBootstrap(configDoc(docId));

  static Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String uid) =>
      FirestoreWebGuard.runWithWebRecovery(
        () => userDoc(uid).get(const GetOptions(source: Source.serverAndCache)),
      );

  static Future<void> mergeUser(String uid, Map<String, dynamic> data) =>
      runFirestorePublishWithRecovery(
        () => userDoc(uid).set(
          sanitizeFirestoreData(data) as Map<String, dynamic>,
          SetOptions(merge: true),
        ),
      );

  static Future<DocumentReference<Map<String, dynamic>>> addSuggestion(
    Map<String, dynamic> data,
  ) async {
    late DocumentReference<Map<String, dynamic>> ref;
    final safe = sanitizeFirestoreData(data) as Map<String, dynamic>;
    await runFirestorePublishWithRecovery(() async {
      ref = await suggestions.add(safe);
    });
    return ref;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchUserSuggestions(
    String uid,
  ) =>
      suggestions.where('userId', isEqualTo: uid).limit(20).watchSafe();

  static Future<QuerySnapshot<Map<String, dynamic>>> listPlanItems() =>
      FirestoreReadResilience.getQuery(
        planItems(),
        cacheKey: 'config_plans_items',
      );

  static Future<void> setPlanItem(String planId, Map<String, dynamic> data) =>
      runFirestorePublishWithRecovery(
        () => planItems().doc(planId.trim()).set(
              sanitizeFirestoreData(data) as Map<String, dynamic>,
              SetOptions(merge: true),
            ),
      );
}
