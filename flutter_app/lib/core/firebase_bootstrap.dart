import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/firebase_options.dart';

/// Garante [Firebase.initializeApp] antes de Firestore/Storage/Auth.
///
/// Web, Android e iOS — obrigatório antes de publicar aviso/evento, chat ou upload.
Completer<void>? _bootstrapCompleter;

bool _hasDefaultFirebaseApp() {
  try {
    Firebase.app();
    return true;
  } catch (_) {
    return false;
  }
}

bool _looksLikeNoFirebaseAppError(Object e) {
  final low = e.toString().toLowerCase();
  return low.contains('no firebase app') ||
      low.contains('firebase.initializeapp') ||
      low.contains('no-app') ||
      low.contains('core/no-app');
}

/// Remove app DEFAULT zombi para permitir novo [Firebase.initializeApp].
Future<void> _resetDefaultFirebaseApp() async {
  _bootstrapCompleter = null;
  try {
    if (_hasDefaultFirebaseApp()) {
      await Firebase.app().delete();
    }
  } catch (_) {}
}

/// Aguarda o bootstrap completo (inicialização + Storage/Auth/Firestore utilizáveis).
Future<void> ensureFirebaseInitialized() async {
  if (_hasDefaultFirebaseApp()) {
    try {
      await _validateFirebasePluginsReady();
      return;
    } catch (e) {
      if (!_looksLikeNoFirebaseAppError(e)) rethrow;
      await _resetDefaultFirebaseApp();
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
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        if (attempt > 1) await _resetDefaultFirebaseApp();
        await _initializeFirebaseDefaultApp();
        await _validateFirebasePluginsReady();
        c.complete();
        return;
      } catch (e) {
        if (_looksLikeNoFirebaseAppError(e)) {
          await _resetDefaultFirebaseApp();
        }
        _bootstrapCompleter = null;
        if (attempt >= 4) {
          c.completeError(e);
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 280 * attempt));
      }
    }
  } catch (e, st) {
    if (!c.isCompleted) c.completeError(e, st);
    rethrow;
  }
}

/// Upload mural/chat: confirma Storage/Auth após init (evita «No Firebase App» no nativo).
Future<void> ensureFirebaseReadyForMediaUpload() async {
  Object? last;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      await ensureFirebaseInitialized();
      await _validateFirebasePluginsReady();
      return;
    } catch (e) {
      last = e;
      if (attempt >= 3 || !_looksLikeNoFirebaseAppError(e)) rethrow;
      await _resetDefaultFirebaseApp();
      await Future.delayed(Duration(milliseconds: 220 * attempt));
    }
  }
  throw last ?? StateError('Firebase indisponível');
}

/// Executa [fn] só após Firebase pronto — use em `unawaited` de publicação em background.
Future<T> runFirebaseBackgroundTask<T>(
  Future<T> Function() fn, {
  String? debugLabel,
}) async {
  Object? last;
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      await ensureFirebaseReadyForMediaUpload();
      return await fn();
    } catch (e, st) {
      last = e;
      if (_looksLikeNoFirebaseAppError(e)) {
        await _resetDefaultFirebaseApp();
      } else {
        _bootstrapCompleter = null;
      }
      if (kDebugMode && debugLabel != null) {
        debugPrint('runFirebaseBackgroundTask($debugLabel) tentativa $attempt: $e');
      }
      if (attempt >= 4) {
        Error.throwWithStackTrace(last, st);
      }
      await Future.delayed(Duration(milliseconds: 350 * attempt));
    }
  }
  throw last ?? StateError('Firebase indisponível');
}

Future<void> _initializeFirebaseDefaultApp() async {
  if (_hasDefaultFirebaseApp()) return;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app' && _hasDefaultFirebaseApp()) return;
    if (kDebugMode) {
      debugPrint('ensureFirebaseInitialized FirebaseException: $e');
    }
    rethrow;
  } catch (e) {
    final low = e.toString().toLowerCase();
    if ((low.contains('duplicate') || low.contains('already exists')) &&
        _hasDefaultFirebaseApp()) {
      return;
    }
    if (kDebugMode) {
      debugPrint('ensureFirebaseInitialized falhou: $e');
    }
    rethrow;
  }

  if (!_hasDefaultFirebaseApp()) {
    throw StateError(
      'Firebase não inicializou. Feche o app por completo e abra de novo.',
    );
  }
}

Future<void> _validateFirebasePluginsReady() async {
  if (!_hasDefaultFirebaseApp()) {
    throw StateError(
      'Firebase não inicializou. Feche o app por completo e abra de novo.',
    );
  }
  try {
    final app = Firebase.app();
    FirebaseFirestore.instanceFor(app: app);
    final auth = FirebaseAuth.instanceFor(app: app);
    // ignore: unnecessary_statements
    auth.app;
    final storage = FirebaseStorage.instanceFor(app: app);
    // ignore: unnecessary_statements
    storage.ref('_bootstrap_ping').fullPath;
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
