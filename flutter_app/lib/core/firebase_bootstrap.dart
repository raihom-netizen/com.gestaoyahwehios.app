import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart' as fb_core;
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

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

Future<void> ensureFirebaseReadyForMediaUpload({bool force = false}) =>
    FirebaseBootstrapService.ensureReadyForMediaUpload(force: force);

/// Painel / feeds — Firestore pronto (sem refresh de token).
Future<void> ensureFirebaseReadyForPanelRead() =>
    FirebaseBootstrapService.ensureReadyForPanelRead();

/// Avisos/eventos/mural — init + token (sem FCM nem backoff longo).
Future<void> ensureFirebaseReadyForPublishUpload() =>
    FirebaseBootstrapService.ensureReadyForPublishUpload();

/// Chat (texto/mídia): sessão + token — sem health check completo nem backoff de reconexão.
Future<void> ensureFirebaseReadyForChatSend() =>
    FirebaseBootstrapService.ensureReadyForChatSend();

/// Upload Storage: chat usa bootstrap leve; resto mantém verificação completa.
Future<void> ensureUploadBootstrapForStoragePath(String storagePath) async {
  final p = storagePath.toLowerCase();
  if (p.contains('chat_media') || p.contains('/chat/')) {
    await ensureFirebaseReadyForChatSend();
  } else {
    await ensureFirebaseReadyForMediaUpload();
  }
}

Future<T> runFirebaseBackgroundTask<T>(
  Future<T> Function() fn, {
  String? debugLabel,
}) =>
    FirebaseBootstrapService.runGuarded(
      fn,
      debugLabel: debugLabel,
      requireAuth: true,
    );

FirebaseApp get firebaseDefaultApp => FirebaseBootstrapService.defaultApp;

FirebaseFirestore get firebaseDefaultFirestore =>
    FirebaseBootstrapService.firestore;

FirebaseAuth get firebaseDefaultAuth => FirebaseBootstrapService.auth;

FirebaseStorage get firebaseDefaultStorage =>
    FirebaseBootstrapService.storage;

Reference firebaseStorageRef(String path) =>
    FirebaseBootstrapService.storageRef(path);

bool get isFirebaseReady => FirebaseBootstrapService.isReady();
