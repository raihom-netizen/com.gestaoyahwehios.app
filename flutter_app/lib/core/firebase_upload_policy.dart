/// Política de upload/gravação alinhada ao **Controle Total**.
///
/// - **Storage:** `putData` / `putFile` directo com retry (sem fila Firestore).
/// - **Offline (só mobile):** manifesto em disco ([StorageUploadPersistenceService]).
/// - **Firestore:** metadados nas coleções de negócio (`avisos`, `eventos`, `chat_threads/...`).
abstract final class FirebaseUploadPolicy {
  FirebaseUploadPolicy._();

  /// `false` = não criar `igrejas/{tenant}/pending_uploads` (evita banner «25 pendentes»).
  static const bool firestorePendingQueueEnabled = false;

  /// Fila em memória ao falhar rede (sem espelho Firestore quando [firestorePendingQueueEnabled] é false).
  static const bool memoryQueueOnNetworkError = true;
}
