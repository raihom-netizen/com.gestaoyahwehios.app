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

/// Offline-first (Controle Total): equivalente Flutter ao `persistentLocalCache` JS.
///
/// - **Mobile (Android/iOS):** `persistenceEnabled: true` + cache ilimitado.
/// - **Web:** IndexedDB ~80MB + long-polling (paridade multi-tab via SDK Firestore web).
/// - **Leituras cache-first:** [ChurchRepository.listCacheFirst] + [TenantStaleWhileRevalidate].
/// - **Escritas optimistas:** [OptimisticFirestoreWrite] / [TenantOfflineWrite] + [SyncEngine].
void configureFirestoreForOfflineAndSpeed() {

  if (!isFirebaseReady) {

    debugPrint(

      'configureFirestoreForOfflineAndSpeed: Firebase ainda nao pronto — ignorado.',

    );

    return;

  }

  final db = firebaseDefaultFirestore;

  try {

    // Offline-first: Web com cache 80MB + long-polling; fallback se IndexedDB falhar.
    db.settings = Settings(

      persistenceEnabled: true,

      cacheSizeBytes: kIsWeb ? 80 * 1024 * 1024 : Settings.CACHE_SIZE_UNLIMITED,

      ignoreUndefinedProperties: true,

      webExperimentalAutoDetectLongPolling: kIsWeb,

    );

    FirestoreOfflineConfig.persistenceEnabled = true;

    FirestoreOfflineConfig.webIndexedDbFallback = false;

  } catch (e, st) {

    debugPrint('configureFirestoreForOfflineAndSpeed: $e\n$st');

    _applyFallbackSettings(db);

  }

}



void _applyFallbackSettings(FirebaseFirestore db) {

  try {

    if (kIsWeb) {

      db.settings = const Settings(

        persistenceEnabled: false,

        ignoreUndefinedProperties: true,

        webExperimentalAutoDetectLongPolling: true,

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

