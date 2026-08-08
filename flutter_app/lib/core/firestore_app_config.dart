import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Estado efectivo da persistência Firestore (Android / iOS / Web).
abstract final class FirestoreOfflineConfig {
  FirestoreOfflineConfig._();

  static bool persistenceEnabled = false;
  static bool webIndexedDbFallback = false;
  static bool settingsApplied = false;
}

/// Configura o Firestore **antes** de qualquer leitura/escrita.
///
/// - **Web:** `persistenceEnabled: false` (cache **em memória**, sem IndexedDB)
///   + `webExperimentalForceLongPolling: true`.
///   Motivo: a persistência IndexedDB do SDK JS 12.x é a origem do bug
///   `INTERNAL ASSERTION FAILED: Unexpected state` / `WatchChangeAggregator`
///   (alvo de watch gravado com versão inválida `ve:-1`). Quando dispara,
///   envenena o cliente Firestore da sessão inteira — todos os módulos
///   (Financeiro, Chat, Eventos, Fornecedores, Patrimônio, Escalas…) passam a
///   voltar vazios/erro — e o estado corrompido **sobrevive a reloads** no
///   IndexedDB, além de conflitar entre abas. Sem persistência IndexedDB o
///   estado corrompido deixa de existir e as leituras vão sempre ao servidor
///   (dados corretos, como no iOS/Android). Velocidade de reabertura fica por
///   conta do cache próprio do app ([ChurchRepository.listCacheFirst] + Hive),
///   que **não** depende do IndexedDB do SDK.
/// - **Mobile:** cache ilimitado + persistência nativa (SQLite, sem esse bug).
void configureFirestoreForOfflineAndSpeed() {
  if (FirestoreOfflineConfig.settingsApplied) return;
  if (!isFirebaseReady) {
    debugPrint(
      'configureFirestoreForOfflineAndSpeed: Firebase ainda nao pronto — ignorado.',
    );
    return;
  }

  final db = firebaseDefaultFirestore;

  if (kIsWeb) {
    try {
      // Web: cache EM MEMÓRIA (sem IndexedDB) + long polling. Estabilidade acima
      // de tudo — elimina o INTERNAL ASSERTION de persistência do SDK JS.
      db.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
        webExperimentalForceLongPolling: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = false;
      FirestoreOfflineConfig.webIndexedDbFallback = false;
      FirestoreOfflineConfig.settingsApplied = true;
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
    FirestoreOfflineConfig.settingsApplied = true;
  } catch (e, st) {
    debugPrint('configureFirestoreForOfflineAndSpeed (mobile): $e\n$st');
    _applyFallbackSettings(db);
  }
}

void _applyFallbackSettings(FirebaseFirestore db) {
  try {
    if (kIsWeb) {
      // Fallback web: cache em memória (sem IndexedDB) — mesma blindagem.
      db.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
        webExperimentalForceLongPolling: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = false;
      FirestoreOfflineConfig.webIndexedDbFallback = false;
      FirestoreOfflineConfig.settingsApplied = true;
    } else {
      db.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 200 * 1024 * 1024,
        ignoreUndefinedProperties: true,
      );
      FirestoreOfflineConfig.persistenceEnabled = true;
      FirestoreOfflineConfig.settingsApplied = true;
    }
  } catch (e2) {
    debugPrint('configureFirestoreForOfflineAndSpeed fallback: $e2');
  }
}
