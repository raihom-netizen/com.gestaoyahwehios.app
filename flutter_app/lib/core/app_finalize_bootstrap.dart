import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/offline/offline_first_coordinator.dart';
import 'package:gestao_yahweh/services/background_upload_worker.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Pilares de finalização: estabilidade (Firebase + sessão), velocidade (reenvio de filas).
abstract final class AppFinalizeBootstrap {
  AppFinalizeBootstrap._();

  static bool _resumeBusy = false;
  static bool _queuesBound = false;

  /// Arranque da app — já chamado em [main]; idempotente.
  static void bindOnColdStart() {
    YahwehMediaUploadPipeline.bindOnAppStart();
    if (EcoFireFlow.disableComplexBootstrap) {
      unawaited(_bindEcoFireMinimal());
      return;
    }
    if (kIsWeb) {
      Future<void>.delayed(const Duration(seconds: 10), () {
        unawaited(_bindQueuesAfterFirebaseCore(manualRecovery: false));
      });
    } else {
      unawaited(_bindQueuesAfterFirebaseCore(manualRecovery: true));
    }
  }

  static Future<void> _bindEcoFireMinimal() async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      if (kIsWeb) {
        FirestoreWebGuard.applyWebFirestoreSettings();
      }
      EcoFireFlow.log('bootstrap minimal OK');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap._bindEcoFireMinimal: $e\n$st');
      }
    }
  }

  static Future<void> _bindQueuesAfterFirebaseCore({
    bool manualRecovery = false,
  }) async {
    if (kIsWeb && WebPanelStability.isSessionExpired) return;
    final beginBootstrap = WebPanelStability.tryBeginBootstrap();
    if (kIsWeb && !beginBootstrap && _queuesBound) return;
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
      YahwehFlowLog.sync('BOOT', 'queues');
      _queuesBound = true;
      if (manualRecovery || (!kIsWeb && WebPanelStability.allowAutomaticRecovery)) {
        await runAutomaticRecovery();
      }
      SystemHealthService.bindPeriodicProbe();
      if (beginBootstrap) WebPanelStability.markBootstrapEnd(ok: true);
    } catch (e, st) {
      if (beginBootstrap) WebPanelStability.markBootstrapEnd(ok: false);
      YahwehFlowLog.error('BOOT', e, st);
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap.bindOnColdStart: $e\n$st');
      }
    }
  }

  /// Modo recuperação automática — reenvia pendentes sem intervenção do utilizador.
  static Future<void> runAutomaticRecovery() async {
    if (EcoFireFlow.disableAutomaticRecovery) return;
    if (!WebPanelStability.allowAutomaticRecovery) {
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap: recovery automático ignorado (web/sessão).');
      }
      return;
    }
    YahwehFlowLog.sync('RECOVERY', 'start');
    await BackgroundUploadWorker.drainAll(reason: 'automatic_recovery');
    YahwehFlowLog.success('RECOVERY');
  }

  /// Volta do background — Firebase + filas (chat, mural, pending_uploads).
  static Future<void> onAppResume() async {
    if (_resumeBusy) return;
    if (EcoFireFlow.disableComplexBootstrap && kIsWeb) {
      try {
        await FirebaseBootstrap.ensureInitialized();
        await FirebaseAuthTokenGuard.refreshIfStale();
      } catch (_) {}
      return;
    }
    if (kIsWeb && WebPanelStability.isSessionExpired) return;
    _resumeBusy = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      await FirebaseAuthTokenGuard.refreshIfStale();
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      } else {
        await _bindQueuesAfterFirebaseCore(manualRecovery: true);
      }
      await OfflineFirstCoordinator.onAppResumed();
    } catch (e, st) {
      YahwehFlowLog.error('BOOT', e, st);
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap.onAppResume: $e\n$st');
      }
    } finally {
      _resumeBusy = false;
    }
  }

  /// Antes de publicar aviso/evento/chat — evita erros genéricos por sessão fria.
  static Future<void> ensureSessionForPublish({String? logLabel}) async {
    await ensureFirebaseReadyToPublish(logLabel: logLabel ?? 'publish');
    if (kIsWeb) {
      try {
        await FirestoreWebGuard.prepareForChatWrite();
      } catch (_) {}
    }
  }
}
