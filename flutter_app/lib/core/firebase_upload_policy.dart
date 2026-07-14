import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';

/// Política de upload/gravação alinhada ao **Controle Total** / **EcoFire**.
///
/// - **Storage:** `putData` directo com retry (sem fila Firestore; sem `putFile`).
/// - **Offline (só mobile):** manifesto em disco ([StorageUploadPersistenceService]).
/// - **Firestore:** metadados nas coleções de negócio (`avisos`, `eventos`, `chats/.../messages`).
abstract final class FirebaseUploadPolicy {
  FirebaseUploadPolicy._();

  /// `true` = criar `igrejas/{tenant}/pending_uploads` para recuperar uploads
  /// pendentes se o utilizador fechar o app durante envio.
  static const bool firestorePendingQueueEnabled = true;

  /// Fila em memória ao falhar rede — desligada no modo EcoFire.
  static bool get memoryQueueOnNetworkError => !EcoFireFlow.disableUploadQueues;
}
