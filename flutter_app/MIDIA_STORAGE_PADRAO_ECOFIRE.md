# Mídia (foto/vídeo) — padrão alinhado ao EcoFire

Referência no disco: `C:\Ecofire_Independente\flutter_app` (`StorageUploadService`, `AdminNetworkImage`, `EcoFireStorage`).

## O que o YAHWEH passou a usar

| EcoFire | Gestão YAHWEH |
|--------|----------------|
| `EcoFireStorage.bucket` + URL `alt=media` | `lib/core/constants/yahweh_storage.dart` → `YahwehStorage.bucket`, `downloadUrlForObjectPath` |
| `StorageUploadService` + `getDownloadURL` após falha | `lib/services/storage_media_service.dart` → `freshPlayableMediaUrl`, `freshImageUrl`, `downloadUrlFromPathOrUrl` |
| `CachedNetworkImage` + fallback Storage | Painel: `SafeNetworkImage` / `FirebaseStorageMemoryImage` com **retry de token** após falha |
| Vídeo web com URL válida | `resolveFirebaseStorageVideoPlayUrl` agora **renova token na web também** (antes retornava a URL crua e o `<video>` quebrava) |

## Regras de ouro (iguais ao EcoFire)

1. **Sempre** salvar no Firestore a URL retornada por `Reference.getDownloadURL()` após o upload (não montar URL manual sem token).
2. Se uma mídia antiga falhar, chamar `StorageMediaService.freshPlayableMediaUrl(url)` ou `freshImageUrl(url)` antes de desistir.
3. Na **web**, `web/index.html` inclui `preconnect` para `firebasestorage.googleapis.com` e o host `*.firebasestorage.app`.

## Firebase Console

- **Storage → Rules**: leitura pública só onde fizer sentido (ex.: site público); o painel usa usuário autenticado + SDK.
- **CORS**: para buckets novos, o Google costuma aplicar CORS adequado para `getDownloadURL`; evite URLs copiadas sem token de builds antigos.
