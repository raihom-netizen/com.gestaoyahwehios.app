import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_migration.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Pilares de finalização: estabilidade (Firebase + sessão), velocidade (reenvio de filas).
abstract final class AppFinalizeBootstrap {
  AppFinalizeBootstrap._();

  static bool _resumeBusy = false;

  /// Arranque da app — já chamado em [main]; idempotente.
  static void bindOnColdStart() {
    YahwehMediaUploadPipeline.bindOnAppStart();
    MuralPublishOutboxService.resumePendingOnAppStart();
    ChurchChatMediaOutboxService.resumePendingOnAppStart();
    unawaited(StorageUploadPersistenceService.resumePendingOnAppStart());
    unawaited(PendingUploadsMigration.migrateAwayFromFirestoreQueueIfNeeded());
    if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      unawaited(PendingUploadsFirestoreService.resumeForCurrentUserTenant());
    }
  }

  /// Volta do background — Firebase + filas (chat, mural, pending_uploads).
  static Future<void> onAppResume() async {
    if (_resumeBusy) return;
    _resumeBusy = true;
    try {
      if (!FirebaseBootstrapService.isReady()) {
        await FirebaseBootstrapService.initialize();
      }
      // Controle Total: ao voltar do background só renova token — não `reconnect()`
      // (resetava Firebase e quebrava upload de foto/áudio da câmara ou galeria).
      await _refreshAuthTokenSilently();
      bindOnColdStart();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppFinalizeBootstrap.onAppResume: $e');
      }
    } finally {
      _resumeBusy = false;
    }
  }

  /// Antes de publicar aviso/evento/chat — evita erros genéricos por sessão fria.
  static Future<void> ensureSessionForPublish({String? logLabel}) async {
    await ensureFirebaseReadyToPublish(logLabel: logLabel ?? 'publish');
    await _refreshAuthTokenSilently();
  }

  static Future<void> _refreshAuthTokenSilently() async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      final user = firebaseDefaultAuth.currentUser;
      if (user == null) return;
      await user.getIdToken(false);
    } catch (_) {
      try {
        await firebaseDefaultAuth.currentUser?.getIdToken(true);
      } catch (_) {}
    }
  }
}
