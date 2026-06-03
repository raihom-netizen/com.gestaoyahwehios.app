import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firestore_app_config.dart';
import 'package:gestao_yahweh/core/offline/offline_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';

/// Orquestra offline-first: Firestore persistence → Hive/SyncEngine → sync silenciosa.
abstract final class OfflineFirstCoordinator {
  OfflineFirstCoordinator._();

  static bool _bound = false;
  static StreamSubscription<bool>? _onlineSub;

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
    try {
      YahwehFlowLog.sync('OFFLINE_FIRST', reason);
      await SyncEngine.flushAll(reason: reason);
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      YahwehFlowLog.success('OFFLINE_FIRST');
    } catch (e, st) {
      YahwehFlowLog.error('OFFLINE_FIRST', e, st);
    }
  }

  /// Volta do background — re-sync silenciosa.
  static Future<void> onAppResumed() async {
    if (AppConnectivityService.instance.isOnline) {
      await _flushSilently(reason: 'app_resume');
    }
  }

  static bool get firestorePersistenceEnabled =>
      FirestoreOfflineConfig.persistenceEnabled;
}
