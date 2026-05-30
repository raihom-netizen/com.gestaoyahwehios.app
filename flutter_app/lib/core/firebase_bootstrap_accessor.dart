import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

/// Ponto único de acesso Firebase no app — use [FirebaseBootstrap.instance].
///
/// Evita `FirebaseFirestore.instance` / `FirebaseAuth.instance` dispersos.
final class FirebaseBootstrap {
  FirebaseBootstrap._();
  static final FirebaseBootstrap instance = FirebaseBootstrap._();

  bool get isReady => FirebaseBootstrapService.isReady();
  FirebaseHealthReport? get lastHealth => FirebaseBootstrapService.lastHealth;

  Future<FirebaseBootstrapResult> initialize() =>
      FirebaseBootstrapService.initialize();

  Future<FirebaseHealthReport> healthCheck({
    bool requireAuthSession = false,
    String? logLabel,
  }) =>
      FirebaseBootstrapService.healthCheck(
        requireAuthSession: requireAuthSession,
        logLabel: logLabel,
      );

  Future<void> reconnect({bool requireAuthSession = false}) =>
      FirebaseBootstrapService.reconnect(
        requireAuthSession: requireAuthSession,
      );

  Future<void> restart() => FirebaseBootstrapService.restart();

  Future<void> ensureReady({
    bool requireAuthSession = false,
    bool forceHealthCheck = false,
  }) =>
      FirebaseBootstrapService.ensureReady(
        requireAuthSession: requireAuthSession,
        forceHealthCheck: forceHealthCheck,
      );

  Future<void> ensureReadyForMediaUpload({bool force = false}) =>
      FirebaseBootstrapService.ensureReadyForMediaUpload(force: force);

  Future<T> runGuarded<T>(
    Future<T> Function() fn, {
    String? debugLabel,
    bool requireAuth = true,
  }) =>
      FirebaseBootstrapService.runGuarded(
        fn,
        debugLabel: debugLabel,
        requireAuth: requireAuth,
      );

  FirebaseApp get app => FirebaseBootstrapService.defaultApp;
  FirebaseFirestore get firestore => FirebaseBootstrapService.firestore;
  FirebaseAuth get auth => FirebaseBootstrapService.auth;
  FirebaseStorage get storage => FirebaseBootstrapService.storage;
  Reference storageRef(String path) => FirebaseBootstrapService.storageRef(path);

  FirebaseFunctions functions({String region = 'us-central1'}) =>
      FirebaseFunctions.instanceFor(app: app, region: region);
}
