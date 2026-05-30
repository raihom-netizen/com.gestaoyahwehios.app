import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

export 'firebase_bootstrap_accessor.dart' show FirebaseBootstrap;

export 'firebase_bootstrap_service.dart' show
    FirebaseBootstrapException,
    FirebaseBootstrapResult,
    FirebaseBootstrapService,
    FirebaseHealthReport;

export 'firebase_user_facing_error.dart' show formatFirebaseErrorForUser;

export 'firebase_publish_guard.dart' show ensureFirebaseReadyToPublish;

/// Compatibilidade — toda a lógica está em [FirebaseBootstrapService].
Future<void> ensureFirebaseInitialized() =>
    FirebaseBootstrapService.ensureReady(requireAuthSession: false);

Future<void> ensureFirebaseReadyForMediaUpload({bool force = false}) =>
    FirebaseBootstrapService.ensureReadyForMediaUpload(force: force);

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
