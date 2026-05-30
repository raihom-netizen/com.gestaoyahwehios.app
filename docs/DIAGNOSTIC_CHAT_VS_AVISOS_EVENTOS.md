# Diagnóstico definitivo — Chat (OK) vs Avisos/Eventos (falhavam no nativo)

**Sintoma:** `Firebase core (core/no-app): No Firebase App '[DEFAULT]'`  
**Conclusão:** o projeto Firebase está correto. O Chat na Web usa o pipeline certo; **Avisos/Eventos tinham código à parte** que chamava `FirebaseStorage.instance` / `FirebaseFirestore.instance` **sem** o mesmo bootstrap do Chat.

---

## 1. Por que o Chat funciona

| Passo | Ficheiro | Linha (aprox.) | O quê |
|-------|----------|----------------|-------|
| 1 | `main.dart` | ~464 | `await FirebaseBootstrapService.initialize()` + `DefaultFirebaseOptions.currentPlatform` |
| 2 | `optimistic_chat_media_upload.dart` | ~104–107 | `AppFinalizeBootstrap.ensureSessionForPublish` |
| 3 | idem | ~107 | `runFirebaseBackgroundTask` → `ensureReady` + retry |
| 4 | `church_chat_service.dart` | ~2012+ | `ensureFirebaseReadyForMediaUpload` |
| 5 | idem | upload | `UnifiedUploadService` → `MediaUploadService` / `putFile` |
| 6 | Storage path | `church_storage_layout.dart` | `igrejas/{tenant}/chat_media/…` |
| 7 | Firestore | `church_chat_service.dart` | `messages` após URL |

**Isolate:** `compute()` só em `ios_publish_image_pipeline.dart` para **comprimir** WebP; o upload Firebase corre **depois**, na thread principal — correto.

---

## 2. Por que Avisos/Eventos falhavam (causas encontradas)

### A) UI de Eventos — upload **sem bootstrap** (causa forte)

| Ficheiro | Linha | Problema |
|----------|-------|----------|
| `events_manager_page.dart` | ~585–600 | `FirebaseStorage.instance.ref` + `putData` (capa template) |
| `events_manager_page.dart` | ~670–679 | Idem (outro botão template) |

**Web:** muitas vezes já tinha sessão quente → passava.  
**Android/iOS:** primeiro acesso ao Storage neste ecrã → `core/no-app` se o plugin ainda não vinculou o app DEFAULT.

**Correção:** `UnifiedUploadService.uploadJpegBytes` (mesmo pipeline do Chat).

### B) Campo estático em serviço de eventos (anti-padrão)

| Ficheiro | Linha | Problema |
|----------|-------|----------|
| `evento_gallery_service.dart` | 24 (antes) | `final _firestore = FirebaseFirestore.instance` no **singleton** |

Avaliado no arranque do singleton = risco de `instance` antes de `initializeApp`.

**Correção:** `FirebaseFirestore get _firestore => firebaseDefaultFirestore` + `ensureFirebaseReadyForMediaUpload` no upload.

### C) Outbox do mural

| Ficheiro | Linha | Problema |
|----------|-------|----------|
| `mural_publish_outbox_service.dart` | 44 | `_docRef` usava `FirebaseFirestore.instance` |

**Correção:** `firebaseDefaultFirestore`.

### D) UI do mural — leituras Firestore

| Ficheiro | Linhas | Problema |
|----------|--------|----------|
| `instagram_mural.dart` | 299, 1206, 3302 | `FirebaseFirestore.instance` direto |

**Correção:** `firebaseDefaultFirestore` (getter após bootstrap no `main`).

### E) Publicação principal (já estava alinhada)

| Ficheiro | Fluxo |
|----------|--------|
| `feed_media_publish_strict.dart` | `runGuarded` + upload → URLs → Firestore |
| `IosPublishImagePipeline` | `compute` (só compressão) → `UnifiedUploadService` |

A falha do utilizador muitas vezes **não** era este caminho, e sim **B** ou upload paralelo (template/vídeo).

---

## 3. Tabela comparativa (Web = referência)

| Aspeto | Chat | Avisos/Eventos (antes) | Avisos/Eventos (agora) |
|--------|------|------------------------|-------------------------|
| `initializeApp` + options | `main` + bootstrap | `main` (igual) | Igual |
| Antes do upload | `ensureFirebaseReadyForMediaUpload` | Parcial / ausente na UI | **Igual ao Chat** |
| Upload imagem | `UnifiedUploadService` / `MediaUploadService` | Misto + `FirebaseStorage.instance` na UI | **UnifiedUploadService** |
| Upload nativo grande | `putFile` | `readAsBytes` + `putData` | `putFile` quando há path |
| Firestore pós-upload | mensagem `sent` | `published` strict | Igual web |
| Log `Firebase.apps` | adicionado no flush | não tinha | `logFirebaseAppsBeforeOperation` |
| Crashlytics no upload | sim | parcial | **unified_upload_*** |

---

## 4. O que NÃO é a causa

- Projeto Firebase errado (Web OK prova que options/bucket/regras estão certos).
- `compute()` nos avisos **não** chama Firebase (só comprime bytes).
- Chat e feed usam **Auth** e **Storage** do mesmo projeto `gestaoyahweh-21e23`.

---

## 5. Verificações pedidas (checklist técnico)

- [x] Busca `final x = FirebaseFirestore.instance` em campo de classe → `evento_gallery_service.dart` corrigido.
- [x] `Firebase.initializeApp` só com `DefaultFirebaseOptions.currentPlatform` → só em `firebase_bootstrap_service.dart`.
- [x] Log `Firebase.apps` antes do upload → `firebase_apps_diagnostic.dart`.
- [x] Crashlytics em uploads → `UnifiedUploadService` + outbox/strict.
- [x] Copiar padrão Chat → `UnifiedUploadService` + `runGuarded` / `runFirebaseBackgroundTask`.

---

## 6. Teste de paridade (Fase 9)

Mesmos passos em **Web, Android, iOS**:

1. Chat: foto + PDF  
2. Aviso: 1 e 3 fotos  
3. Evento: 1 foto + vídeo curto  
4. (Opcional) Template de evento com foto — era o bug das linhas 585/670  

**Logs debug (nativo):** procurar `[FirebaseApps]` — deve mostrar `[DEFAULT]`, nunca `apps=[]`.

---

## 7. Ficheiros alterados nesta correção definitiva

- `lib/core/firebase_apps_diagnostic.dart` (novo)
- `lib/services/unified_upload_service.dart` (+ `uploadJpegBytes`, Crashlytics, log apps)
- `lib/ui/pages/events_manager_page.dart` (remove `FirebaseStorage.instance`)
- `lib/services/evento_gallery_service.dart`
- `lib/services/mural_publish_outbox_service.dart`
- `lib/ui/widgets/instagram_mural.dart`
- `lib/services/video_handler_service_io.dart`
- `lib/services/feed_media_publish_strict.dart`
- `lib/services/optimistic_chat_media_upload.dart` (log paridade)

## 8. Pacote padronizado (build 1657+)

| Ficheiro | Função |
|----------|--------|
| `lib/core/firebase/firebase_bootstrap.dart` | `FirebaseBootstrap.ensureInitialized()` — `initializeApp` + options **uma vez** |
| `lib/core/firebase/firebase_service.dart` | `FirebaseService.firestore/storage/auth()` — sem campos estáticos `.instance` |
| `lib/core/firebase/firebase_retry.dart` | `firebaseRetry()` — 3 tentativas, backoff 2s/4s |
| `main.dart` | `ensureInitialized()` **antes** de `FirebaseBootstrapService.initialize()` |
| `feed_media_publish_strict.dart` | `EVENT_START` → upload → `UPLOAD_OK` → `FIRESTORE_OK` / `EVENT_ERROR` |

**Ficheiro que gerava `core/no-app` no nativo (confirmado):** `events_manager_page.dart` (~585–679) — `FirebaseStorage.instance` na capa de template **fora** do bootstrap do Chat. Corrigido com `UnifiedUploadService.uploadJpegBytes`.

Build: **11.2.295+1657**
