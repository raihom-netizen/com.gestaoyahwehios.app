import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/firebase_options.dart';

/// Garante [Firebase.initializeApp] antes de Firestore/Storage/Auth.
///
/// **Web, Android e iOS** — usar antes de qualquer operação Firebase (publicar aviso/evento,
/// chat, upload Storage, perfis). No iOS, `Firebase.apps.isNotEmpty` pode ser verdadeiro sem
/// o app Dart `[DEFAULT]` — por isso validamos com [Firebase.app].
Future<void>? _initFuture;

bool _hasDefaultFirebaseApp() {
  try {
    Firebase.app();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> ensureFirebaseInitialized() async {
  Object? last;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      await _ensureFirebaseInitializedOnce();
      return;
    } catch (e) {
      last = e;
      _initFuture = null;
      if (attempt >= 3) break;
      await Future.delayed(Duration(milliseconds: 320 * attempt));
    }
  }
  throw last ??
      StateError(
        'Firebase não inicializou. Reinicie o app ou atualize para a versão mais recente.',
      );
}

Future<void> _ensureFirebaseInitializedOnce() async {
  if (_hasDefaultFirebaseApp()) return;

  if (_initFuture != null) {
    await _initFuture!;
    if (_hasDefaultFirebaseApp()) return;
    _initFuture = null;
  }

  final fut = _initializeFirebaseDefaultApp();
  _initFuture = fut;
  try {
    await fut;
  } catch (e) {
    _initFuture = null;
    rethrow;
  }
  _initFuture = null;

  if (!_hasDefaultFirebaseApp()) {
    throw StateError(
      'Firebase não inicializou. Reinicie o app ou atualize para a versão mais recente.',
    );
  }
}

/// Upload mural/chat: confirma Storage/Auth após [ensureFirebaseInitialized].
Future<void> ensureFirebaseReadyForMediaUpload() async {
  await ensureFirebaseInitialized();
  try {
    FirebaseStorage.instance.ref('_bootstrap_ping').fullPath;
    final _ = FirebaseAuth.instance.app;
  } catch (e) {
    final low = e.toString().toLowerCase();
    if (low.contains('no firebase app') ||
        low.contains('firebase.initializeapp')) {
      _initFuture = null;
      await _ensureFirebaseInitializedOnce();
      FirebaseStorage.instance.ref('_bootstrap_ping').fullPath;
    } else {
      rethrow;
    }
  }
}

Future<void> _initializeFirebaseDefaultApp() async {
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
}

bool get isFirebaseReady => _hasDefaultFirebaseApp();
