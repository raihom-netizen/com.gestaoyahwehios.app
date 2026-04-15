import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Configura o Firestore **antes** de qualquer leitura/escrita.
///
/// - **Persistência + cache amplo**: leituras repetidas e listas ficam mais rápidas;
///   escritas feitas offline entram na fila e sincronizam quando a rede voltar.
/// - **ignoreUndefinedProperties**: merges mais limpos ao atualizar documentos.
/// - **Web**: deteção de long-polling (redes/proxies instáveis) e cache multi‑aba.
void configureFirestoreForOfflineAndSpeed() {
  try {
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        ignoreUndefinedProperties: true,
        webExperimentalAutoDetectLongPolling: true,
      );
    } else {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        ignoreUndefinedProperties: true,
      );
    }
  } catch (e, st) {
    debugPrint('configureFirestoreForOfflineAndSpeed: $e\n$st');
    try {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 200 * 1024 * 1024,
        ignoreUndefinedProperties: true,
      );
    } catch (e2) {
      debugPrint('configureFirestoreForOfflineAndSpeed fallback: $e2');
    }
  }
}
