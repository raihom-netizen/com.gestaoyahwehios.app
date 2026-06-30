import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart' as fb_core;
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;

export 'firebase/firebase_bootstrap.dart' show FirebaseBootstrap;
export 'firebase/firebase_service.dart' show FirebaseService;
export 'firebase/firebase_retry.dart' show firebaseRetry;
export 'firebase_bootstrap_accessor.dart' show FirebaseBootstrapGateway;

export 'firebase_bootstrap_service.dart' show
    FirebaseBootstrapException,
    FirebaseBootstrapResult,
    FirebaseBootstrapService,
    FirebaseHealthReport;

export 'firebase_user_facing_error.dart'
    show formatFirebaseErrorForUser, isFirebaseNoAppError;

export 'firebase_publish_guard.dart' show ensureFirebaseReadyToPublish;

/// Compatibilidade — toda a lógica está em [FirebaseBootstrapService].
Future<void> ensureFirebaseInitialized() =>
    fb_core.FirebaseBootstrap.ensureInitialized();

/// Núcleo Firebase — Ecofire: init único antes de Storage/Firestore.
Future<void> ensureFirebaseCore({bool requireAuth = false}) async {
  if (EcoFireFlow.directStorageUpload) {
    await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: requireAuth);
    if (kIsWeb && requireAuth) {
      await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
    }
    return;
  }

  Object? last;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (attempt > 0) {
        FirebaseBootstrapService.resetPublishWarmState();
        await Future<void>.delayed(
          Duration(milliseconds: 200 + 180 * attempt),
        );
      }

      // Fast path: só se Storage ainda estiver ligado (Android após background).
      if (FirebaseBootstrapService.isReady() &&
          FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
        try {
          FirebaseBootstrapService.probeStorageLinked();
          if (!requireAuth) return;
          final user = await FirebaseBootstrapService.resolveAuthenticatedUser();
          if (user == null) {
            throw StateError(
              'Sessão indisponível no momento. Tente novamente em instantes.',
            );
          }
          try {
            await FirebaseAuthTokenGuard.refreshIfStale();
          } catch (_) {}
          return;
        } catch (_) {
          FirebaseBootstrapService.resetPublishWarmState();
        }
      }

      // Caminho resiliente padrão: garante app DEFAULT + Storage ligado.
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: requireAuth,
        maxAttempts: 5,
      );

      // Warmup Ecofire apenas após o núcleo estar estável.
      if (requireAuth) {
        await EcoFirePublishBootstrap.ensureHard(
          logLabel: 'ensureFirebaseCore',
          strict: true,
        );
      }

      if (requireAuth) {
        final user = await FirebaseBootstrapService.resolveAuthenticatedUser();
        if (user == null) {
          throw StateError(
            'Sessão indisponível no momento. Tente novamente em instantes.',
          );
        }
      }
      return;
    } catch (e) {
      last = e;
      if (attempt < 4 && isFirebaseNoAppError(e)) {
        try {
          await fb_core.FirebaseBootstrap.ensureInitialized();
          await FirebaseBootstrapService.ensureAlwaysOn(
            refreshAuthToken: requireAuth,
          );
          continue;
        } catch (_) {}
        continue;
      }
      rethrow;
    }
  }
  if (last != null) {
    if (last is Exception) throw last;
    throw StateError(last.toString());
  }
  throw StateError('Firebase indisponível.');
}

Future<void> ensureFirebaseReadyForMediaUpload({bool force = false}) =>
    ensureFirebaseCore(requireAuth: true);

/// Painel / feeds — só núcleo Firebase (sem token).
Future<void> ensureFirebaseReadyForPanelRead() async {
  try {
    await ensureFirebaseCore(requireAuth: false).timeout(
      kIsWeb ? const Duration(seconds: 5) : const Duration(seconds: 15),
    );
  } catch (_) {}
}

/// Avisos/eventos/mural/património/foto membro.
Future<void> ensureFirebaseReadyForPublishUpload() =>
    ensureFirebaseCore(requireAuth: true);

/// Chat texto/mídia — mesmo núcleo (Firestore + Storage directos).
Future<void> ensureFirebaseReadyForChatSend() =>
    ensureFirebaseCore(requireAuth: true);

/// Mídia do chat — leve (sem [runGuarded] com vários retries).
Future<void> runChatMediaUploadTask(
  Future<void> Function() fn, {
  String? debugLabel,
}) async {
  Object? last;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await ensureFirebaseCore(requireAuth: true);
      await fn();
      return;
    } catch (e) {
      last = e;
      if (attempt == 0 && isFirebaseNoAppError(e)) {
        await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
        await FirebaseAuthTokenGuard.refreshIfStale();
        continue;
      }
      rethrow;
    }
  }
  throw last ?? StateError('Firebase indisponível');
}

/// Upload Storage — init + token (path ignorado; mantido por compatibilidade).
Future<void> ensureUploadBootstrapForStoragePath(String storagePath) async {
  await ensureFirebaseCore(requireAuth: true);
}

/// Tarefas de upload/chat — bootstrap silencioso em `core/no-app`.
Future<T> runFirebaseBackgroundTask<T>(
  Future<T> Function() fn, {
  String? debugLabel,
}) =>
    FirebaseBootstrapService.runGuarded(
      fn,
      debugLabel: debugLabel ?? 'storage_background',
      requireAuth: true,
    );

FirebaseApp get firebaseDefaultApp => FirebaseBootstrapService.defaultApp;

/// Acesso Firestore/Auth/Storage — app [DEFAULT] (sem `.instance` solto).
FirebaseFirestore get firebaseDefaultFirestore =>
    FirebaseBootstrapService.firestore;

FirebaseAuth get firebaseDefaultAuth => FirebaseBootstrapService.auth;

FirebaseStorage get firebaseDefaultStorage =>
    FirebaseBootstrapService.storage;

Reference firebaseStorageRef(String path) =>
    FirebaseBootstrapService.storageRef(path);

bool get isFirebaseReady => FirebaseBootstrapService.isReady();
