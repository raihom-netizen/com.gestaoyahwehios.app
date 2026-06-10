import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';

/// Política de upload/gravação alinhada ao **Controle Total** / **EcoFire**.
///
/// - **Storage:** `putData` / `putFile` directo com retry (sem fila Firestore).
/// - **Offline (só mobile):** manifesto em disco ([StorageUploadPersistenceService]).
/// - **Firestore:** metadados nas coleções de negócio (`avisos`, `eventos`, `chats/.../messages`).
abstract final class FirebaseUploadPolicy {
  FirebaseUploadPolicy._();

  /// `false` = não criar `igrejas/{tenant}/pending_uploads` (evita banner «25 pendentes»).
  static const bool firestorePendingQueueEnabled = false;

  /// Fila em memória ao falhar rede — desligada no modo EcoFire.
  static bool get memoryQueueOnNetworkError => !EcoFireFlow.disableUploadQueues;
}
