/// Política de mídia Storage + Firestore (painel, membros, eventos, patrimônio, certificados).
///
/// 1. **CORS no bucket** (obrigatório para Chrome/web): na raiz do repositório use [cors.json]
///    e aplique com `gsutil cors set cors.json gs://gestaoyahweh-21e23.firebasestorage.app`
///    ou `.\scripts\apply_firebase_storage_cors.ps1`.
///
/// 2. **Uploads**: usar [MediaUploadService] / [FirebaseStorageService] que já chamam
///    [Reference.getDownloadURL] após `putData`/`putFile`.
///
/// 3. **Firestore**: gravar apenas URLs **https** nos campos de exibição (`fotoUrl`, `logoUrl`,
///    `imageUrl`, etc.). Para normalizar legado `gs://` ou path antes de gravar de novo,
///    use [StorageMediaService.publishableHttpsUrlForFirestore].
///
/// 4. **UI**: não usar [Image.network] direto para `firebasestorage.googleapis.com` / `*.firebasestorage.app`
///    no painel **nem no site público**; usar [ResilientNetworkImage], [SafeNetworkImage],
///    [FreshFirebaseStorageImage], [StableStorageImage] (logo, membros `foto_perfil`, mural/avisos,
///    eventos, património, vídeo-posters, marketing). Vídeos hospedados: [StorageMediaService] /
///    widgets em `premium_storage_video/`.
///
/// 5. **Pré-carregar**: usar `preloadNetworkImages` (`ui/widgets/safe_network_image.dart`), não
///    `precacheImage(NetworkImage(...))` com URLs que possam ser Storage na web.
library church_media_publish_policy;

export 'package:gestao_yahweh/services/media_upload_service.dart';
export 'package:gestao_yahweh/services/storage_media_service.dart';
