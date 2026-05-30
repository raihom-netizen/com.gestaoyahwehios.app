# Paridade Web × Android × iOS — Gestão YAHWEH

**Referência oficial:** Web (comportamento correto).  
**Objetivo:** Android e iOS usam os **mesmos serviços** e o **mesmo bootstrap** Firebase.

---

## Resumo executivo

| Módulo | Web | Android / iOS | Serviço canónico |
|--------|-----|---------------|------------------|
| **Chat** | OK | OK (referência nativa) | `OptimisticChatMediaUpload` → `ChurchChatService` → **`UnifiedUploadService`** |
| **Avisos** | OK | Falhas `core/no-app` (corrigido) | `FeedMediaPublishStrict` → `MuralPostMediaPayload` → **`UnifiedUploadService`** |
| **Eventos** | OK | Idem avisos | `FeedMediaPublishService` / `saveStubAndSchedulePhotos` → **`UnifiedUploadService`** |
| **Bootstrap** | `main` → `FirebaseBootstrapService.initialize()` | Igual | `ensureFirebaseReadyForMediaUpload()` antes de Storage/Firestore |

**Causa raiz (sintoma):** Chat e feed **não** usavam o mesmo guard de Firebase. Chat chamava `ensureFirebaseInitialized()` (sem sessão); avisos/eventos e `pending_uploads` tocavam `FirebaseFirestore.instance` / getters do mural **antes** do bootstrap em alguns caminhos nativos.

**Correção:** `UnifiedUploadService` + `firebaseDefaultFirestore` / `firebaseDefaultAuth` + `ensureFirebaseReadyForMediaUpload()` em **todos** os uploads.

---

## FASE 1 — Fluxos mapeados

### Chat (funciona na Web)

```
UI thread/hub
  → OptimisticChatMediaUpload.flush
  → AppFinalizeBootstrap.ensureSessionForPublish
  → runFirebaseBackgroundTask
  → ChurchChatService.uploadChatBytes | uploadChatFile
  → UnifiedUploadService (WEB: putData | NATIVO: putFile)
  → MediaUploadService / YahwehMediaUploadPipeline
  → firebaseStorageRef(path)  // igrejas/{tenant}/chat_media/...
  → Firestore: igrejas/{tenant}/chat_threads/{threadId}/messages
```

**Storage:** `igrejas/{tenantId}/chat_media/{threadId}/…`  
**Firestore:** `chat_threads`, `messages`, `chat_member_prefs`  
**Functions:** FCM / `onChatMessage` (notificações)

### Avisos / Eventos (Web OK; nativos alinhados)

```
UI mural / eventos
  → AppFinalizeBootstrap.ensureSessionForPublish
  → FirebaseBootstrapService.runGuarded
  → FeedMediaPublishStrict.publishWithPhotosFirst
  → MuralPostMediaPayload.uploadNewPhotos*
  → IosPublishImagePipeline (compress WebP) — nativo
  → UnifiedUploadService.uploadImage
  → Storage: tenants/{tenantId}/media/avisos|eventos/…  (novos uploads)
  → Firestore: igrejas/{tenantId}/avisos | noticias  (só após URLs)
```

**Diferença de path Storage (intencional):** chat em `igrejas/…/chat_media/`; mural novo em `tenants/…/media/…` (regras `storage.rules` aceitam ambos). **Leitura** aceita URLs legadas `igrejas/…`.

### Upload / download

| Operação | Serviço |
|----------|---------|
| Imagem feed | `UnifiedUploadService.uploadImage` |
| Vídeo feed/chat | `UnifiedUploadService.uploadVideo` / chat prepare |
| PDF/DOC/XLS chat | `UnifiedUploadService.uploadFile` |
| Fila offline | `StorageUploadQueueService` + `PendingUploadsFirestoreService` |
| Retry | 3–4 tentativas, backoff 1s/2s/4s |

---

## FASE 2 — Camada única (não duplicar por plataforma)

| Ficheiro | Papel |
|----------|--------|
| `lib/core/firebase_bootstrap_service.dart` | Único `Firebase.initializeApp` |
| `lib/services/unified_upload_service.dart` | **Upload** imagem/vídeo/ficheiro (WEB/ANDROID/IOS) |
| `lib/services/yahweh_media_upload_pipeline.dart` | Compressão + fila + analytics |
| `lib/services/media_upload_service.dart` | putData/putFile + retry |
| `lib/services/feed_media_publish_strict.dart` | Publicação atómica mural |
| `lib/services/optimistic_chat_media_upload.dart` | Chat otimista |
| `lib/services/church_chat_service.dart` | API chat (delega a Unified) |

**Proibido:** ramo `if (android) { upload diferente }` excepto `kIsWeb` para `putData` vs `putFile` **dentro** de `UnifiedUploadService`.

---

## FASE 3–4 — Storage e Firestore

- **Bucket:** projeto `gestaoyahweh-21e23` (mesmo em todas as plataformas).
- **Novos avisos/eventos:** `tenants/{tenantId}/media/avisos|eventos/…`
- **Chat:** `igrejas/{tenantId}/chat_media/…`
- **Firestore publicação feed:** um único `set` com `publishState: published` **depois** de todas as URLs (`FeedMediaPublishStrict`).

---

## FASE 7–8 — Firebase init e logs

Antes de qualquer operação:

```dart
await ensureFirebaseReadyForMediaUpload();
// Firebase.apps.isNotEmpty + sessão Auth válida
```

Logs (`logFirebasePublishPhase`):

- `WEB|ANDROID|IOS` + `UPLOAD_START` / `UPLOAD_END` / `UPLOAD_ERROR`
- `INICIO_FIRESTORE` / `FIM_FIRESTORE` / `ERRO_FIRESTORE`

---

## FASE 9 — Checklist de paridade (manual)

Executar **os mesmos** passos em Web, Android e iOS:

### Chat

- [ ] Texto
- [ ] Foto
- [ ] Vídeo
- [ ] PDF

### Avisos

- [ ] Sem imagem
- [ ] 1 imagem
- [ ] 3 imagens

### Eventos

- [ ] Sem mídia
- [ ] 1 imagem
- [ ] 3 imagens

**Esperado:** WEB = ANDROID = IOS = OK, sem `core/no-app`.

---

## Comparação Chat (OK) vs Avisos (falhavam)

| Aspeto | Chat (antes) | Avisos (antes) | Depois (alinhado) |
|--------|--------------|----------------|-------------------|
| Bootstrap upload | `ensureFirebaseInitialized` | getters `FirebaseFirestore.instance` no mural | `ensureFirebaseReadyForMediaUpload` |
| Upload nativo | `uploadChatFile` → putFile | `readAsBytes` + putData | `UnifiedUploadService` putFile/path |
| Sessão | `runFirebaseBackgroundTask` | `runGuarded` + `ensureSessionForPublish` | Ambos |
| Publicação FS | stub → sent | strict published após URLs | Igual web |

---

## Versão

Build com estas alterações: **11.2.295+1655** (ver `app_version.dart`).

Deploy nativo: novo AAB/IPA após validação do checklist acima.
