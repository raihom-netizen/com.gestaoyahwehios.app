import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_session_stability.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';

/// Monitora rede (Wi‑Fi / dados / ethernet). Não prova “internet até o Google” —
/// cobre o caso usual de avião / sem sinal. Firestore já persiste e sincroniza escritas offline.
class AppConnectivityService {
  AppConnectivityService._();
  static final AppConnectivityService instance = AppConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _onlineCtrl =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  bool get isOnline => _online;

  Stream<bool> get onlineStream => _onlineCtrl.stream;

  static bool _listIndicatesOnline(List<ConnectivityResult> list) {
    if (list.isEmpty) return true;
    return list.any((r) => r != ConnectivityResult.none);
  }

  Future<void> start() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _setOnline(_listIndicatesOnline(initial));
    } catch (_) {
      _setOnline(true);
    }
    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((list) {
      _setOnline(_listIndicatesOnline(list));
    });
  }

  void _setOnline(bool online) {
    if (online == _online) return;
    final wasOffline = !_online;
    _online = online;
    if (!_onlineCtrl.isClosed) _onlineCtrl.add(online);
    // Volta a sincronizar filas do Firestore após modo avião / sem sinal.
    if (online) {
      YahwehFlowLog.online('NETWORK');
    } else {
      YahwehFlowLog.offline('NETWORK');
    }
    if (online && wasOffline) {
      YahwehFlowLog.sync('NETWORK', 'resume_queues');
      AppSessionStability.onConnectivityRestored();
      unawaited(
        firebaseDefaultFirestore.enableNetwork().catchError((Object e, StackTrace s) {
          YahwehFlowLog.error('NETWORK', e, s);
        }),
      );
      if (kIsWeb) {
        unawaited(FirestoreWebGuard.recoverFirestoreWebSession(allowHardReconnect: true));
      }
      unawaited(SyncEngine.flushAll(reason: 'connectivity_online'));
      if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
        unawaited(PendingUploadsFirestoreService.resumeForCurrentUserTenant());
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _onlineCtrl.close();
  }
}
