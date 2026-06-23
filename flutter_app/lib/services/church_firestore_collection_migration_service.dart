import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Dispara migraÃ§Ã£o Cloud Function: `noticias`â†’`eventos`, `chat_threads`â†’`chats`.
abstract final class ChurchFirestoreCollectionMigrationService {
  ChurchFirestoreCollectionMigrationService._();

  static final Set<String> _inFlight = <String>{};

  static Future<void> ensureTenantMigrated(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    if (_inFlight.contains(tid)) return;
    _inFlight.add(tid);
    try {
      await ensureFirebaseInitialized();
      final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '')
          .httpsCallable(
        'migrateTenantFirestoreCollections',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );
      final res = await fn.call<Map<String, dynamic>>(<String, dynamic>{
        'tenantId': tid,
        'deleteSource': true,
      });
      if (kDebugMode) {
        debugPrint('ChurchFirestoreCollectionMigration: $tid â†’ ${res.data}');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChurchFirestoreCollectionMigration fail $tid: $e\n$st');
      }
    } finally {
      _inFlight.remove(tid);
    }
  }
}

