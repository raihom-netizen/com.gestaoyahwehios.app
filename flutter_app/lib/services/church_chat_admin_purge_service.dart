import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Limpeza total do chat no Firestore (Cloud Function — só gestor/pastor/admin).
abstract final class ChurchChatAdminPurgeService {
  ChurchChatAdminPurgeService._();

  static Future<({
    int deletedMessages,
    int clearedThreads,
    int deletedUploads,
    int deletedPending,
  })> purgeAllMessagesForTenant(String tenantId) async {
    await ensureFirebaseReadyForPublishUpload();
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw StateError('Igreja inválida.');
    }
    final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1').httpsCallable(
      'purgeChurchChatMessagesAdmin',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    final res = await fn.call<Map<String, dynamic>>({'tenantId': tid});
    final data = res.data ?? {};
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return (
      deletedMessages: n(data['deletedMessages']),
      clearedThreads: n(data['clearedThreads']),
      deletedUploads: n(data['deletedUploads']),
      deletedPending: n(data['deletedPending']),
    );
  }
}
