import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Firebase directo — init único + Storage put + Firestore write.
///
/// **Nunca** chama [FirebaseBootstrap.reset] nem `_softReinit` (evita `core/no-app`).
abstract final class EcoFireDirectFirebase {
  EcoFireDirectFirebase._();

  /// Garante app [DEFAULT] — reexecuta `initializeApp` só se necessário.
  static Future<FirebaseApp> ensureDefaultApp() async {
    await FirebaseBootstrap.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase não inicializou (core/no-app). FIREBASE APPS=${Firebase.apps.length}',
      );
    }
    final app = Firebase.app();
    FirebaseBootstrapService.refreshCachedApp();
    return app;
  }

  /// Bucket Storage ligado ao app [DEFAULT].
  static Future<void> ensureStorageLinked() async {
    final app = await ensureDefaultApp();
    final bucket = FirebaseStorage.instanceFor(app: app).bucket;
    if (bucket.isEmpty) {
      throw StateError('Firebase Storage indisponível (bucket vazio).');
    }
    FirebaseBootstrapService.probeStorageLinked();
  }

  /// Sessão Auth válida antes de upload/gravação.
  static Future<void> ensureAuthSession({bool strict = true}) async {
    await ensureDefaultApp();
    var user = FirebaseAuth.instanceFor(app: Firebase.app()).currentUser;
    if (user == null || user.isAnonymous) {
      user = await FirebaseBootstrapService.resolveAuthenticatedUser();
    }
    if (user == null || user.isAnonymous) {
      await FirebaseAuthTokenGuard.refreshIfStale();
      user = FirebaseAuth.instanceFor(app: Firebase.app()).currentUser;
    }
    if (user == null || user.isAnonymous) {
      if (strict) {
        throw StateError(
          'Sessão expirada. Toque em «Trocar de conta» e entre novamente.',
        );
      }
      return;
    }
    try {
      await user.getIdToken(false).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Antes de `putData` / `putFile` em `igrejas/{churchId}/…`.
  static Future<void> ensureForStoragePut({bool requireAuth = true}) async {
    await ensureStorageLinked();
    if (requireAuth) {
      await ensureAuthSession(strict: true);
    }
  }

  /// Antes de `set`/`update` Firestore (publicar aviso, evento, chat…).
  static Future<void> ensureForFirestoreWrite({bool requireAuth = true}) async {
    await ensureDefaultApp();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      await FirestoreWebGuard.ensureFirestoreClientAlive().catchError((_) {});
    }
    if (requireAuth) {
      await ensureAuthSession(strict: true);
    }
  }

  /// Leitura painel Web — mesma produção que Android/iOS.
  static Future<void> ensureForPanelRead() async {
    await ensureDefaultApp();
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      await FirestoreWebGuard.ensureFirestoreClientAlive().catchError((_) {});
    }
  }

  /// Referência Storage no app [DEFAULT].
  static Future<Reference> storageRef(String path) async {
    final app = await ensureDefaultApp();
    return FirebaseStorage.instanceFor(app: app).ref(path);
  }
}
