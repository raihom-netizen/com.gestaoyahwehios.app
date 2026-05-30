import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Configura o Firestore **antes** de qualquer leitura/escrita.
///
/// Equivalente V4 a `enablePersistence` + `PersistenceSettings(synchronizeTabs: true)` na web.
/// - **Mobile (igual Controle Total)**: `persistenceEnabled: true` + cache ilimitado —
///   leituras/escritas locais sincronizam com o servidor mais depressa.
/// - **Web (igual Controle Total)**: sem IndexedDB; long-polling estável.
///   Pré-carga opcional das coleções principais: serviço `church_tenant_offline_warmup_service.dart`.
/// - **ignoreUndefinedProperties**: merges mais limpos ao atualizar documentos.
/// - **Web**: deteção de long-polling (redes/proxies instáveis) e cache multi‑aba.
void configureFirestoreForOfflineAndSpeed() {
  if (!isFirebaseReady) {
    debugPrint(
      'configureFirestoreForOfflineAndSpeed: Firebase ainda nao pronto — ignorado.',
    );
    return;
  }
  final db = firebaseDefaultFirestore;
  try {
    if (kIsWeb) {
      // Controle Total: sem IndexedDB na web — login Google/Apple mais estável; long-polling fixo.
      db.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
        webExperimentalForceLongPolling: true,
      );
    } else {
      db.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        ignoreUndefinedProperties: true,
      );
    }
  } catch (e, st) {
    debugPrint('configureFirestoreForOfflineAndSpeed: $e\n$st');
    try {
      db.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 200 * 1024 * 1024,
        ignoreUndefinedProperties: true,
      );
    } catch (e2) {
      debugPrint('configureFirestoreForOfflineAndSpeed fallback: $e2');
    }
  }
}
