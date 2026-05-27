import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/firebase_options.dart';

/// Garante [Firebase.initializeApp] antes de Firestore/Storage/Auth.
///
/// **Web, Android e iOS** — usar antes de qualquer operação Firebase (publicar aviso/evento,
/// chat, upload Storage, perfis). O `main.dart` antigo engolia falhas de init e o app abria
/// sem Firebase → «No Firebase App [DEFAULT] has been created» ao publicar.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app' && Firebase.apps.isNotEmpty) return;
    if (kDebugMode) {
      debugPrint('ensureFirebaseInitialized FirebaseException: $e');
    }
    rethrow;
  } catch (e) {
    final low = e.toString().toLowerCase();
    if ((low.contains('duplicate') || low.contains('already exists')) &&
        Firebase.apps.isNotEmpty) {
      return;
    }
    if (kDebugMode) {
      debugPrint('ensureFirebaseInitialized falhou: $e');
    }
    rethrow;
  }
}

bool get isFirebaseReady => Firebase.apps.isNotEmpty;
