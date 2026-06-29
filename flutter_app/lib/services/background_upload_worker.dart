import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_auto_recovery_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_migration.dart';
import 'package:gestao_yahweh/services/church_chat_storage_retention_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';

/// Fila global de uploads em background — um job de cada vez.
///
/// Mobile: ficheiros ficam em `pending_uploads` (disco) + outboxes locais;
/// ao reabrir ou voltar do background, [drainAll] retoma sem cancelar.
abstract final class BackgroundUploadWorker {
  BackgroundUploadWorker._();

  static bool _drainBusy = false;
  static bool _drainCoalesce = false;

  /// Agenda drenagem (idempotente — vários pedidos viram uma só execução).
  static void scheduleDrain({String reason = 'enqueue'}) {
    unawaited(drainAll(reason: reason));
  }

  /// Processa filas locais: chat → mural → património/membro/financeiro → Storage → Hive sync.
  static Future<void> drainAll({String reason = 'manual'}) async {
    if (_drainBusy) {
      _drainCoalesce = true;
      return;
    }
    _drainBusy = true;
    YahwehFlowLog.sync('UPLOAD_QUEUE', reason);
    try {
      await EcoFireResilientPublish.refreshSessionForDrain();
      if (WebPanelStability.allowAutomaticRecovery) {
        await ChurchChatAutoRecoveryService.recoverOnSessionStart();
      }
      await ChurchChatMediaOutboxService.resumeRecoverableNow();

      await MuralPublishOutboxService.drainPendingJobs();
      await ModuleMediaOutboxService.drainPendingJobs();
      if (!kIsWeb) {
        await StorageUploadPersistenceService.resumePendingOnAppStart();
      }

      await PendingUploadsMigration.migrateAwayFromFirestoreQueueIfNeeded();
      if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
        await PendingUploadsFirestoreService.resumeForCurrentUserTenant();
      }

      if (AppConnectivityService.instance.isOnline) {
        await SyncEngine.flushAll(reason: 'upload_queue_$reason');
      }
      YahwehFlowLog.success('UPLOAD_QUEUE');

      final tenant =
          await PendingUploadsFirestoreService.resolveTenantForCurrentUser();
      if (tenant != null && tenant.isNotEmpty) {
        unawaited(ChurchChatStorageRetentionService.maybeRunForTenant(tenant));
      }
    } catch (e, st) {
      YahwehFlowLog.error('UPLOAD_QUEUE', e, st);
      if (kDebugMode) {
        debugPrint('BackgroundUploadWorker.drainAll: $e\n$st');
      }
    } finally {
      _drainBusy = false;
      if (_drainCoalesce) {
        _drainCoalesce = false;
        unawaited(drainAll(reason: 'coalesced'));
      }
    }
  }

  /// Arranque / resume — substitui chamadas paralelas dispersas.
  static Future<void> bindOnAppStart() async {
    MuralPublishOutboxService.bindConnectivityResume();
    ModuleMediaOutboxService.bindConnectivityResume();
    ChurchChatMediaOutboxService.bindConnectivityResume();
    await drainAll(reason: 'cold_start');
  }

}
