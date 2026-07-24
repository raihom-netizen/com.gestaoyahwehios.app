/// Feature **YAHWEH CHAT** — mensageiro nativo (Firebase only).
///
/// Arquitetura:
/// - `domain/` — models + contratos
/// - `data/` — repositórios Firestore/Storage
/// - `presentation/` — telas (próximos passos)
///
/// Paths: `igrejas/{churchId}/chats/{chatId}/messages`
/// Departamentos = grupos (`dept_{departmentId}`).
/// Canais oficiais = publicação restrita (pastor/admin/secretário).
library;

export 'domain/domain.dart';
export 'data/data.dart';
export 'presentation/presentation.dart';
