import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/firebase_options.dart';

/// Garante [Firebase.initializeApp] antes de Firestore/Storage/Auth.
///
/// **Não** apagar o app DEFAULT durante upload/publicação (corrompe Auth/Storage no nativo).
Completer<void>? _bootstrapCompleter;
FirebaseApp? _cachedDefaultApp;

bool _hasDefaultFirebaseApp() {
  try {
    Firebase.app();
    return true;
  } catch (_) {
    return false;
  }
}

FirebaseApp _resolveDefaultApp() {
  if (_cachedDefaultApp != null) {
    try {
      // Confirma que o handle nativo ainda existe.
      _cachedDefaultApp!.name;
      return _cachedDefaultApp!;
    } catch (_) {
      _cachedDefaultApp = null;
    }
  }
  final app = Firebase.app();
  _cachedDefaultApp = app;
  return app;
}

/// App DEFAULT validado — usar em `instanceFor(app: …)` e Storage.
FirebaseApp get firebaseDefaultApp => _resolveDefaultApp();

FirebaseFirestore get firebaseDefaultFirestore =>
    FirebaseFirestore.instanceFor(app: firebaseDefaultApp);

FirebaseAuth get firebaseDefaultAuth =>
    FirebaseAuth.instanceFor(app: firebaseDefaultApp);

FirebaseStorage get firebaseDefaultStorage =>
    FirebaseStorage.instanceFor(app: firebaseDefaultApp);

Reference firebaseStorageRef(String path) => firebaseDefaultStorage.ref(path);

bool _looksLikeNoFirebaseAppError(Object e) {
  final low = e.toString().toLowerCase();
  return low.contains('no firebase app') ||
      low.contains('firebase.initializeapp') ||
      low.contains('no-app') ||
      low.contains('core/no-app') ||
      low.contains('has not been initialized');
}

/// Reinicialização **sem** `delete()` — segura com sessão Auth aberta.
Future<void> _softReinitializeFirebase() async {
  _bootstrapCompleter = null;
  _cachedDefaultApp = null;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app' && _hasDefaultFirebaseApp()) {
      _cachedDefaultApp = Firebase.app();
      return;
    }
    rethrow;
  } catch (e) {
    final low = e.toString().toLowerCase();
    if ((low.contains('duplicate') || low.contains('already exists')) &&
        _hasDefaultFirebaseApp()) {
      _cachedDefaultApp = Firebase.app();
      return;
    }
    rethrow;
  }
  _cachedDefaultApp = Firebase.app();
}

/// Último recurso (arranque zombi) — só após falhas repetidas.
Future<void> _hardResetDefaultFirebaseApp() async {
  _bootstrapCompleter = null;
  _cachedDefaultApp = null;
  try {
    if (_hasDefaultFirebaseApp()) {
      await Firebase.app().delete();
    }
  } catch (_) {}
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  _cachedDefaultApp = Firebase.app();
}

/// Aguarda o bootstrap completo (inicialização + plugins utilizáveis).
Future<void> ensureFirebaseInitialized() async {
  if (_hasDefaultFirebaseApp()) {
    try {
      await _validateFirebasePluginsReady();
      return;
    } catch (e) {
      if (!_looksLikeNoFirebaseAppError(e)) rethrow;
      await _softReinitializeFirebase();
      await _validateFirebasePluginsReady();
      return;
    }
  }

  final inflight = _bootstrapCompleter;
  if (inflight != null) {
    await inflight.future;
    return;
  }

  final c = Completer<void>();
  _bootstrapCompleter = c;
  try {
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        if (!_hasDefaultFirebaseApp()) {
          await _softReinitializeFirebase();
        } else if (attempt > 1) {
          await _softReinitializeFirebase();
        }
        await _validateFirebasePluginsReady();
        c.complete();
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ensureFirebaseInitialized tentativa $attempt: $e');
        }
        if (attempt >= 4 && _looksLikeNoFirebaseAppError(e)) {
          await _hardResetDefaultFirebaseApp();
        } else if (_looksLikeNoFirebaseAppError(e)) {
          await _softReinitializeFirebase();
        }
        _bootstrapCompleter = null;
        if (attempt >= 5) {
          c.completeError(e);
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  } catch (e, st) {
    if (!c.isCompleted) c.completeError(e, st);
    rethrow;
  }
}

/// Upload mural/chat/avisos — Auth + Storage no mesmo app DEFAULT (sem `delete`).
Future<void> ensureFirebaseReadyForMediaUpload() async {
  Object? last;
  for (var attempt = 1; attempt <= 5; attempt++) {
    try {
      await ensureFirebaseInitialized();
      await _validateFirebasePluginsReady(requireAuthSession: true);
      return;
    } catch (e) {
      last = e;
      if (kDebugMode) {
        debugPrint('ensureFirebaseReadyForMediaUpload $attempt: $e');
      }
      if (attempt >= 5) break;
      if (_looksLikeNoFirebaseAppError(e)) {
        await _softReinitializeFirebase();
      }
      await Future.delayed(Duration(milliseconds: 180 * attempt));
    }
  }
  throw last ??
      StateError(
        'Serviços Firebase indisponíveis. Verifique a ligação e tente de novo.',
      );
}

/// Executa [fn] só após Firebase pronto — publicação em background (avisos/eventos).
Future<T> runFirebaseBackgroundTask<T>(
  Future<T> Function() fn, {
  String? debugLabel,
}) async {
  Object? last;
  for (var attempt = 1; attempt <= 5; attempt++) {
    try {
      await ensureFirebaseReadyForMediaUpload();
      return await fn();
    } catch (e, st) {
      last = e;
      if (_looksLikeNoFirebaseAppError(e)) {
        await _softReinitializeFirebase();
      }
      if (kDebugMode && debugLabel != null) {
        debugPrint('runFirebaseBackgroundTask($debugLabel) $attempt: $e');
      }
      if (attempt >= 5) {
        Error.throwWithStackTrace(last, st);
      }
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
  }
  throw last ?? StateError('Firebase indisponível');
}

Future<void> _validateFirebasePluginsReady({
  bool requireAuthSession = false,
}) async {
  if (!_hasDefaultFirebaseApp()) {
    throw StateError(
      'Firebase não inicializou. Reinicie o app e tente de novo.',
    );
  }
  final app = _resolveDefaultApp();
  try {
    FirebaseFirestore.instanceFor(app: app);
    final auth = FirebaseAuth.instanceFor(app: app);
    final storage = FirebaseStorage.instanceFor(app: app);
    // Não usar `ref().fullPath` — no Android pode disparar falso «no-app».
    // ignore: unnecessary_statements
    storage.bucket;
    if (requireAuthSession) {
      final user = auth.currentUser;
      if (user == null || user.isAnonymous) {
        throw StateError(
          'Sessão expirada. Saia e entre de novo no painel antes de publicar.',
        );
      }
      try {
        await user.getIdToken(false).timeout(const Duration(seconds: 12));
      } catch (e) {
        if (_looksLikeNoFirebaseAppError(e)) rethrow;
        // Rede lenta: token em cache ainda pode bastar para Storage.
      }
    }
    _cachedDefaultApp = app;
  } catch (e) {
    if (_looksLikeNoFirebaseAppError(e)) {
      throw StateError(
        'Serviços Firebase não iniciaram. Feche o app por completo e abra de novo.',
      );
    }
    rethrow;
  }
}

bool get isFirebaseReady => _hasDefaultFirebaseApp();
