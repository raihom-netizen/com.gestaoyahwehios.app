import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Estado efectivo da persistência Firestore (Android / iOS / Web).
abstract final class FirestoreOfflineConfig {
  FirestoreOfflineConfig._();

  static bool persistenceEnabled = false;
  static bool webIndexedDbFallback = false;
}

/// Configura o Firestore **antes** de qualquer leitura/escrita.
///
/// Alinhado ao **Controle Total** (`Controletotalapp_Independente/flutter_app/lib/main.dart`):
/// - **Web:** `persistenceEnabled: false` + `webExperimentalForceLongPolling: true`
///   (evita INTERNAL ASSERTION / API Firestore JS a não responder após login).
/// - **Mobile:** cache ilimitado + persistência nativa.
/// - Cache de módulos na Web: [ChurchRepository.listCacheFirst] + Hive (não IndexedDB SDK).
void configureFirestoreForOfflineAndSpeed() {
  if (!isFirebaseReady) {
    debugPrint(
      'configureFirestoreForOfflineAndSpeed: Firebase ainda nao pronto — ignorado.',
    );
    return;
  }

  final db = firebaseDefaultFirestore;

  if (kIsWeb) {
    try {
      db.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
        webExperimentalForceLongPolling: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = false;
      FirestoreOfflineConfig.webIndexedDbFallback = false;
    } catch (e, st) {
      debugPrint('configureFirestoreForOfflineAndSpeed (web CT): $e\n$st');
      _applyFallbackSettings(db);
    }
    return;
  }

  try {
    db.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      ignoreUndefinedProperties: true,
    );
    FirestoreOfflineConfig.persistenceEnabled = true;
    FirestoreOfflineConfig.webIndexedDbFallback = false;
  } catch (e, st) {
    debugPrint('configureFirestoreForOfflineAndSpeed (mobile): $e\n$st');
    _applyFallbackSettings(db);
  }
}

void _applyFallbackSettings(FirebaseFirestore db) {
  try {
    if (kIsWeb) {
      db.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
        webExperimentalForceLongPolling: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = false;
      FirestoreOfflineConfig.webIndexedDbFallback = true;
    } else {
      db.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 200 * 1024 * 1024,
        ignoreUndefinedProperties: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = true;
    }
  } catch (e2) {
    debugPrint('configureFirestoreForOfflineAndSpeed fallback: $e2');
  }
}
