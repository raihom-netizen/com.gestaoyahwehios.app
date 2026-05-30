import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/church_chat_stuck_cleanup_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Migração única: limpa fila Firestore antiga quando passamos ao modo CT (só disco).
abstract final class PendingUploadsMigration {
  PendingUploadsMigration._();

  static const _prefsKey = 'firestore_pending_queue_cleared_v2';

  static Future<void> migrateAwayFromFirestoreQueueIfNeeded() async {
    if (FirebaseUploadPolicy.firestorePendingQueueEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) == true) return;

    final tenant = await PendingUploadsFirestoreService.resolveTenantForCurrentUser();
    if (tenant != null && tenant.isNotEmpty) {
      unawaited(PendingUploadsFirestoreService.cancelAllOpenForTenant(tenant));
      unawaited(
        PendingUploadsFirestoreService.pruneUnrecoverableOpenForTenant(tenant),
      );
      unawaited(ChurchChatStuckCleanupService.purgeAllForTenant(tenant));
    }
    await prefs.setBool(_prefsKey, true);
  }
}
