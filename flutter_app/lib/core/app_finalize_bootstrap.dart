import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
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
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Pilares de finalização: estabilidade (Firebase + sessão), velocidade (reenvio de filas).
abstract final class AppFinalizeBootstrap {
  AppFinalizeBootstrap._();

  static bool _resumeBusy = false;

  /// Arranque da app — já chamado em [main]; idempotente.
  static void bindOnColdStart() {
    YahwehMediaUploadPipeline.bindOnAppStart();
    if (kIsWeb) {
      Future<void>.delayed(const Duration(seconds: 10), () {
        unawaited(_bindQueuesAfterFirebaseCore());
      });
    } else {
      unawaited(_bindQueuesAfterFirebaseCore());
    }
  }

  static Future<void> _bindQueuesAfterFirebaseCore() async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      if (kIsWeb) {
        await FirestoreWebGuard.recoverFirestoreWebSession(
          allowHardReconnect: true,
        );
      }
      await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
      YahwehFlowLog.sync('BOOT', 'queues');
      await runAutomaticRecovery();
      SystemHealthService.bindPeriodicProbe();
    } catch (e, st) {
      YahwehFlowLog.error('BOOT', e, st);
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap.bindOnColdStart: $e\n$st');
      }
    }
  }

  /// Modo recuperação automática — reenvia pendentes sem intervenção do utilizador.
  static Future<void> runAutomaticRecovery() async {
    YahwehFlowLog.sync('RECOVERY', 'start');
    await BackgroundUploadWorker.drainAll(reason: 'automatic_recovery');
    YahwehFlowLog.success('RECOVERY');
  }

  /// Volta do background — Firebase + filas (chat, mural, pending_uploads).
  static Future<void> onAppResume() async {
    if (_resumeBusy) return;
    _resumeBusy = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      await FirebaseAuthTokenGuard.refreshIfStale();
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      if (kIsWeb) {
        await FirestoreWebGuard.recoverFirestoreWebSession(
          allowHardReconnect: true,
        );
      }
      await _bindQueuesAfterFirebaseCore();
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
