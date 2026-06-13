import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/offline/firebase_remote_repository.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/offline/offline_firestore_executor.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_chat_auto_recovery_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';

/// Arranque da camada offline-first (Hive + SyncEngine).
abstract final class OfflineBootstrap {
  OfflineBootstrap._();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    YahwehFlowLog.start('OFFLINE');
    try {
      await HiveLocalStore.instance.init();
      await TenantModuleHiveCache.init();
      OfflineFirestoreExecutor.registerAll(FirebaseRemoteRepository.instance);
      _registerModuleFlushers();
      YahwehFlowLog.success('OFFLINE');
    } catch (e, st) {
      YahwehFlowLog.error('OFFLINE', e, st);
      if (kDebugMode) debugPrint('OfflineBootstrap.init: $e\n$st');
    }
  }

  static void _registerModuleFlushers() {
    SyncEngine.registerModuleFlusher('chat', () async {
      await ChurchChatAutoRecoveryService.recoverOnSessionStart();
      ChurchChatMediaOutboxService.resumePendingOnAppStart();
    });
    SyncEngine.registerModuleFlusher('mural', () async {
      await MuralPublishOutboxService.drainPendingJobs();
    });
    SyncEngine.registerModuleFlusher('module_media', () async {
      await ModuleMediaOutboxService.drainPendingJobs();
    });
    SyncEngine.registerModuleFlusher('storage', () async {
      if (EcoFireFlow.disableUploadQueues) return;
      await StorageUploadPersistenceService.resumePendingOnAppStart();
    });
    SyncEngine.registerModuleFlusher('bootstrap', () async {
      if (EcoFireFlow.disableComplexBootstrap) return;
      if (kIsWeb) return;
      await AppFinalizeBootstrap.onAppResume();
    });
    for (final mod in const [
      'membros',
      'eventos',
      'avisos',
      'patrimonio',
      'financeiro',
      'escalas',
      'visitantes',
      'pedidos_oracao',
      'departamentos',
      'tenant',
    ]) {
      SyncEngine.registerModuleFlusher(mod, () async {
        await SyncEngine.repository.flushModule(mod);
      });
    }
  }
}
