import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_app_config.dart';
import 'package:gestao_yahweh/core/offline/offline_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/background_upload_worker.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/services/master_dashboard_cache_service.dart';

/// Orquestra offline-first: Firestore persistence → Hive/SyncEngine → sync silenciosa.
///
/// Padrão Controle Total: nativo funciona sem internet; ao voltar online,
/// `enableNetwork` + `waitForPendingWrites` + flush de filas + revalidate BG
/// **sem** spinners (painel igreja + Master).
abstract final class OfflineFirstCoordinator {
  OfflineFirstCoordinator._();

  static bool _bound = false;
  static StreamSubscription<bool>? _onlineSub;
  static DateTime? _lastSilentSyncAt;

  /// Chamar **uma vez** após [FirebaseBootstrap.ensureInitialized], **antes** de leituras Firestore.
  static Future<void> initialize() async {
    configureFirestoreForOfflineAndSpeed();
    try {
      await OfflineBootstrap.init();
    } catch (e, st) {
      if (kDebugMode) debugPrint('OfflineFirstCoordinator.init: $e\n$st');
    }
    _bindSilentSync();
    if (AppConnectivityService.instance.isOnline) {
      unawaited(_flushSilently(reason: 'cold_start'));
    }
  }

  static void _bindSilentSync() {
    if (_bound) return;
    _bound = true;
    _onlineSub?.cancel();
    _onlineSub = AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) {
        unawaited(_flushSilently(reason: 'connectivity_online'));
      }
    });
  }

  /// Sincronização em background — sem banners, sem bloquear UI.
  static Future<void> _flushSilently({required String reason}) async {
    final last = _lastSilentSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _lastSilentSyncAt = DateTime.now();
    try {
      YahwehFlowLog.sync('OFFLINE_FIRST', reason);
      try {
        await firebaseDefaultFirestore.enableNetwork();
      } catch (_) {}
      try {
        await firebaseDefaultFirestore
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 25));
      } catch (_) {}
      await SyncEngine.flushAll(reason: reason);
      await BackgroundUploadWorker.drainAll(reason: reason);
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      // Revalidate leituras em BG (igreja + master) — paint já veio do Hive/prefs.
      unawaited(_revalidateCachesSilently());
      YahwehFlowLog.success('OFFLINE_FIRST');
    } catch (e, st) {
      YahwehFlowLog.error('OFFLINE_FIRST', e, st);
    }
  }

  static Future<void> _revalidateCachesSilently() async {
    try {
      final tid = ChurchContext.resolveChurchId();
      if (tid.isNotEmpty) {
        await YahwehModuleCaches.revalidateSilent(tid);
      }
    } catch (_) {}
    try {
      MasterDashboardCacheService.revalidateInBackground();
    } catch (_) {}
    try {
      if (!kIsWeb) {
        unawaited(MasterChurchesListService.loadFast(force: false));
      }
    } catch (_) {}
  }

  /// Volta do background — re-sync silenciosa.
  static Future<void> onAppResumed() async {
    if (AppConnectivityService.instance.isOnline) {
      await _flushSilently(reason: 'app_resume');
    } else {
      // Offline: só aquece UI a partir do disco (sem rede).
      final tid = ChurchContext.resolveChurchId();
      if (tid.isNotEmpty) {
        unawaited(YahwehModuleCaches.warmUpTenant(tid));
      }
    }
  }

  static bool get firestorePersistenceEnabled =>
      FirestoreOfflineConfig.persistenceEnabled;
}
