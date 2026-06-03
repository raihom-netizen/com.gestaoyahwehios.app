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

/// Padrão Controle Total: **um** `initializeApp` + (opcional) token JWT.
/// Sem health check, fila, reconnect nem segunda inicialização.
Future<void> ensureFirebaseCore({bool requireAuth = false}) async {
  await fb_core.FirebaseBootstrap.ensureInitialized();
  FirebaseBootstrapService.refreshCachedApp();
  if (Firebase.apps.isEmpty) {
    throw StateError(
      'Firebase não inicializou (core/no-app). FIREBASE APPS=0',
    );
  }
  if (!requireAuth) return;
  final user = FirebaseBootstrapService.auth.currentUser;
  if (user == null || user.isAnonymous) {
    throw StateError(
      'Sessão expirada. Saia e entre de novo no painel antes de publicar.',
    );
  }
  await user.getIdToken(false).timeout(const Duration(seconds: 12));
}

Future<void> ensureFirebaseReadyForMediaUpload({bool force = false}) =>
    ensureFirebaseCore(requireAuth: true);

/// Painel / feeds — só núcleo Firebase (sem token).
Future<void> ensureFirebaseReadyForPanelRead() =>
    ensureFirebaseCore(requireAuth: false);

/// Avisos/eventos/mural/património/foto membro.
Future<void> ensureFirebaseReadyForPublishUpload() =>
    ensureFirebaseCore(requireAuth: true);

/// Chat texto/mídia — mesmo núcleo (Firestore + Storage directos).
Future<void> ensureFirebaseReadyForChatSend() =>
    ensureFirebaseCore(requireAuth: true);

/// Mídia do chat — sem [runFirebaseBackgroundTask] (menos latência no caminho quente).
Future<void> runChatMediaUploadTask(
  Future<void> Function() fn, {
  String? debugLabel,
}) async {
  await ensureFirebaseCore(requireAuth: true);
  await fn();
}

/// Upload Storage — init + token (path ignorado; mantido por compatibilidade).
Future<void> ensureUploadBootstrapForStoragePath(String storagePath) async {
  await ensureFirebaseCore(requireAuth: true);
}

/// Tarefas de upload/chat — bootstrap + reconnect automático em `core/no-app`.
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

FirebaseFirestore get firebaseDefaultFirestore =>
    FirebaseBootstrapService.firestore;

FirebaseAuth get firebaseDefaultAuth => FirebaseBootstrapService.auth;

FirebaseStorage get firebaseDefaultStorage =>
    FirebaseBootstrapService.storage;

Reference firebaseStorageRef(String path) =>
    FirebaseBootstrapService.storageRef(path);

bool get isFirebaseReady => FirebaseBootstrapService.isReady();
