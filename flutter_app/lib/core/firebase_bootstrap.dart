import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
