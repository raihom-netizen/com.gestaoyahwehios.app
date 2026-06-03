# Manual Arquitetural Completo — Gestão Igreja (Flutter + Firebase)

> **Objetivo:** plataforma multiplataforma (Android, iOS, Web) ultra-performática, resiliente a falhas, offline-first e sincronização silenciosa — padrão **Controle Total** / **WhatsApp**.

Use este documento como referência permanente para o Cursor e para revisões de código.

---

## 0. Princípios inegociáveis

1. **O app nunca cai** — falhas de rede não bloqueiam UI; dados locais aparecem primeiro.
2. **Escrita instantânea** — texto e metadados vão para cache/Firestore local antes de confirmar servidor.
3. **Sync silenciosa** — filas Hive + `SyncEngine.flushAll` em background; sem spinners globais de «sincronização».
4. **Sessão eterna** — logout só manual em Configurações → «Trocar de conta».
5. **Biometria obrigatória** — após sessão válida, painel só após `local_auth` (mobile).
6. **Mídia compactada** — nunca enviar foto original de câmara/galeria sem passar por 1024×1024 @ 70%.
7. **Quota Auth** — nunca `getIdToken(true)` forçado em leituras/streams.

---

## 1. Arquitetura offline-first

### 1.1 Firestore persistence

- **Ficheiro:** `lib/core/firestore_app_config.dart`
- **Arranque:** `OfflineFirstCoordinator.initialize()` em `main.dart` (após `FirebaseBootstrap.ensureInitialized`).
- **Configuração alvo:**

```dart
FirebaseFirestore.instance.settings = Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  ignoreUndefinedProperties: true,
  webExperimentalAutoDetectLongPolling: kIsWeb,
);
```

- **Fallback web:** se IndexedDB falhar (Internal Assertion / WatchChangeAggregator), desactivar persistence e usar long-polling + cache Hive (`FirestoreOfflineConfig.webIndexedDbFallback`).
- **Recuperação web antes de publicar:** `FirestoreWebGuard.recoverFirestoreWebSession()` via `AppFinalizeBootstrap.ensureSessionForPublish()`.

### 1.2 Orquestração

| Componente | Responsabilidade |
|------------|------------------|
| `OfflineFirstCoordinator` | persistence + `OfflineBootstrap` + flush silencioso (cold start, online, resume) |
| `OptimisticFirestoreWrite` | escritas textuais instantâneas na UI |
| `TenantOfflineWrite` | fila Hive quando offline (todas as plataformas) |
| `SyncEngine` | drenagem da fila quando online |
| `ResilientDataNotifier` / `ResilientPanelQueryFutureBuilder` | UI não trava com erro de rede |

### 1.3 Conectividade

- `AppConnectivityService` emite `onlineStream` → `OfflineFirstCoordinator` faz flush sem banner.
- `AppFinalizeBootstrap.onAppResume()` chama `OfflineFirstCoordinator.onAppResumed()` (não duplicar flush em loop — `_resumeBusy` guard).

---

## 2. Login persistente e biometria

### 2.1 Sessão

- **Ficheiros:** `auth_service.dart`, `main.dart`, `auth_gate.dart`, `church_sign_out_navigation.dart`
- Na inicialização: `FirebaseAuth.instance.currentUser != null` → navegar directo para `/painel` (mobile; web com sessão em `/` redirecciona).
- `AuthService.configurePersistentSession()` + `hasActiveSession`.
- **Logout manual exclusivo:** Configurações → «Trocar de conta» → `signOut()` + limpar prefs locais → Login (Google, Apple, e-mail/senha).

### 2.2 Biometria

- **Ficheiros:** `biometric_lock_page.dart`, `biometric_service.dart`
- Com sessão activa, ao abrir app: popup imediato `local_auth` (digital / Face ID).
- Painel **só** após sucesso; falha = «Tentar de novo» (sem `signOut` automático).
- `BiometricService.shouldRequireBiometricUnlock()` no `AuthGate`.

### 2.3 Permissões nativas

**Android** (`AndroidManifest.xml`):

- `INTERNET`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `CAMERA`

**iOS** (`Info.plist`):

- `NSFaceIDUsageDescription`
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

---

## 3. Compressão extrema e uploads

### 3.1 Imagens

- **Constantes:** `lib/core/media_upload_limits.dart`
- **Pipeline:** `MediaService`, `YahwehMediaUploadPipeline`, `upload_storage_task.dart`
- **Regra:** `maxWidth: 1024`, `maxHeight: 1024`, qualidade **70%** (WebP quando aplicável).
- Meta: ~200 KB por foto (vs 5–10 MB originais).

### 3.2 Progresso e timeout

- `LinearProgressIndicator` / barra no balão via `UploadTask.snapshotEvents` e `GlobalUploadProgress`.
- Timeout **30 s** para imagens ≤ 3 MB (`upload_storage_task.dart`).
- Erros amigáveis: `formatUploadErrorForUser` + SnackBar.

### 3.3 Firebase Storage (web)

- **Não** usar `Image.network` directo para URLs `firebasestorage.googleapis.com` no painel web.
- Usar `SafeNetworkImage` / `StorageFriendlyImage` (`lib/ui/widgets/safe_network_image.dart`).

---

## 4. Requisitos por módulo

| Módulo | Limite / comportamento | Ficheiros-chave |
|--------|------------------------|-----------------|
| **Avisos** | até **5 fotos** compactadas em lote; publicação Firestore-first | `instagram_mural.dart`, `kMaxAvisoFeedPhotosPerPost` |
| **Eventos** | **10 fotos** + **2 vídeos** ≤ **90 s** cada (validar duração antes do upload) | `events_manager_page.dart`, `publication_engine.dart` |
| **Chat Igreja** | texto instantâneo (cache Firestore); mídia assíncrona com stub + progresso no balão | `church_chat_service.dart`, `church_chat_media_outbox_service.dart` |
| **Património** | até **5 fotos**/bem, cadastro rápido | constantes património + `MediaService` |
| **Financeiro** | comprovantes (imagem/PDF) em `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext` | `church_storage_layout.dart`, `finance_comprovante_publish_service.dart` |
| **Membros** | edição instantânea; foto perfil local imediata + upload BG → `photoUrl` | `MemberProfilePhotoBytesCache`, fluxo perfil membro |
| **Certificados / cartões** | PDF local (`pdf` package), sem round-trip pesado ao servidor | serviços de emissão PDF |
| **Painel / Agendas** | cache `_panel_cache`, aniversariantes, totais, líderes; streams optimizadas | `dashboard_page.dart`, warmup painel |

### 4.1 Chat estilo WhatsApp

- Stub Firestore antes de transcode de vídeo.
- Estados: `creating` → `uploading` → `sent` / `published`.
- Outbox disco: `ChurchChatMediaOutboxService` — reenvio automático no resume.
- Grupos: cache Hive, cap loading ~6 s, resync sem apagar outbox recuperável.

### 4.2 Publicar aviso/evento

- Sempre `AppFinalizeBootstrap.ensureSessionForPublish()` antes de gravar (web).
- Firestore primeiro; mídia em background; push FCM ao concluir mídia quando aplicável.

---

## 5. Otimização de memória

Implementar `dispose()` rigoroso em:

- Relatórios, Fornecedores, listagens longas, Chat (thread/hub)
- Encerrar: `TextEditingController`, `ScrollController`, `StreamSubscription`, `AnimationController`, timers.

Evitar:

- `Column(mainAxisSize: MainAxisSize.min)` com filho `Expanded` no mesmo eixo (overflow).
- Streams duplicadas no mesmo documento sem `broadcast` / cache partilhado.

---

## 6. Regras de segurança Firebase (Firestore + Storage)

### 6.1 Onde está o código exacto

**Não invente regras genéricas** — o projeto já tem regras de produção (~1700 linhas Firestore) alinhadas ao chat, mural, membros, financeiro e offline-first:

| Ficheiro | Console Firebase |
|----------|------------------|
| `firestore.rules` (raiz do repo) | Firestore → Regras |
| `storage.rules` (raiz do repo) | Storage → Regras |

### 6.2 Como publicar (recomendado)

Na raiz do repositório (PowerShell):

```powershell
.\scripts\deploy_firebase_rules.ps1
```

Isto publica **Firestore + índices + Storage** de uma vez, com retry em erros 503.

Colar manualmente no console só se não tiver CLI — copie **o ficheiro inteiro** (`Ctrl+A` no VS Code/Cursor).

### 6.3 Princípios das regras actuais

**Firestore**

- `isSignedIn()` — qualquer operação exige `request.auth != null` (excepto rotas públicas explícitas).
- `canAccessTenant(tenantId)` / `memberLinkedToTenant(tenantId)` — membro ou gestor da igreja.
- **Chat:** `igrejas/{id}/chats/{threadId}` + subcoleção `messages` — participante do thread ou membro ligado; patches de `lastMessage`, `deliveryStatus`, `uploadProgress`.
- **Mural:** `canWriteMuralFeed` — gestor, pastoral, secretariado, tesoureiro, líder de departamento.
- **Offline:** escritas optimistas locais sincronizam quando online — regras validam **payload**, não exigem `request.time` especial.

**Storage**

- Write autenticado + limite de tamanho + MIME flexível (`octet-stream` / vazio para Flutter).
- Paths canónicos:
  - `igrejas/{id}/avisos/`, `eventos/`, `noticias/` — até 120 MB (mídia mural)
  - `igrejas/{id}/chat_media/` — chat (200 MB, áudio/PDF/Office)
  - `igrejas/{id}/patrimonio/` — fotos até 20 MB
  - `igrejas/{id}/financeiro/YYYY_MM/` — comprovantes imagem/PDF (15 MB) **← novo path Controle Total**
  - `igrejas/{id}/membros/` — fotos perfil
- Catch-all final: `match /{allPaths=**} { allow read, write: if false; }` — nega o resto.

### 6.4 Erros comuns `permission-denied`

| Sintoma | Causa provável | Acção |
|---------|----------------|-------|
| Chat mensagem texto | Utilizador sem `participantUids` / `memberLinkedToTenant` | Verificar doc `membros` + `authUid` |
| Upload Storage chat | Path fora de `chat_media/` ou > 200 MB | Usar `ChurchStorageLayout` |
| Publicar aviso | Role não em `canWriteMuralFeed` | Verificar `users/{uid}.role` ou `roles[]` |
| Financeiro comprovante | Path legado `comprovantes/` vs `financeiro/` | Usar `financeComprovantePath()` |
| Web após idle | Sessão Auth expirada | `ensureSessionForPublish()` antes de gravar |

Consola: [Firebase Console — gestaoyahweh-21e23](https://console.firebase.google.com/project/gestaoyahweh-21e23/overview)

---

## 7. Dependências (`pubspec.yaml`)

Bloco consolidado (§ manual arquitetural):

```yaml
# Firebase (offline-first + auth persistente)
firebase_core: ^3.15.0
firebase_auth: ^5.7.0
cloud_firestore: ^5.6.0
firebase_storage: ^12.4.0

# Mídia, biometria, PDF
image_picker: ^1.2.2
flutter_image_compress: ^2.1.0
image: ^4.5.4
video_compress: ^3.1.2
local_auth: ^2.3.0
pdf: ^3.12.0
printing: ^5.14.3
```

> **Nota:** Firebase SDK 6.x existe mas implica migração breaking — manter série 5.x até release dedicada.

Após alterar: `cd flutter_app` → `flutter pub get`.

---

## 8. Arquitectura de pastas e Clean Code

```
lib/
├── core/           # offline, firestore config, bootstrap
├── repositories/   # fachadas UI → serviços (NOVO)
│   ├── auth_repository.dart      → AuthService
│   └── storage_repository.dart   → FeedPostMediaUpload + YahwehMediaUploadPipeline
├── services/       # lógica Firebase, upload, chat, mural
├── ui/pages/       # só UI + navegação — sem queries Firestore directas
└── ui/widgets/
```

**Regras**

- Telas **não** chamam `FirebaseFirestore.instance` / `FirebaseStorage.instance` directamente.
- Preferir `AuthRepository`, `StorageRepository`, `ChurchDataService`, `OptimisticFirestoreWrite`.
- Uploads múltiplos: `StorageRepository.uploadPhotosParallel` ou `FeedPostMediaUpload.uploadParallel` (já usado em avisos, eventos, património) — paralelismo limitado via `Future.wait` em lotes, não sequencial.

**Já implementado**

- Avisos/eventos: `mural_fast_publish_service.dart`, `mural_post_media_payload.dart`
- Património: `patrimonio_publish_service.dart` (`Future.wait` por chunk)
- Chat: outbox + stub Firestore assíncrono

---

## 9. Versão e deploy

### 9.1 Controlo de versão

Alinhar sempre (marketing fixo **11.2.295** salvo pedido explícito):

1. `flutter_app/lib/app_version.dart`
2. `flutter_app/pubspec.yaml` — `version: 11.2.295+N`
3. `flutter_app/web/version.json`

Incrementar `+N` quando houver código a entregar; obrigatório em publicação lojas.

### 9.2 Scripts

| Pedido | Comando |
|--------|---------|
| Só web | `.\scripts\deploy_web_hosting.ps1` (CanvasKit) ou `deploy_web_hosting_html_dom.ps1` |
| Só regras | `.\scripts\deploy_firebase_rules.ps1` |
| Completo | `.\scripts\deploy_completo.ps1` |

URL produção: **https://gestaoyahweh-21e23.web.app** — após deploy, **Ctrl+F5** / limpar dados PWA.

---

## 10. Comando mestre (colar no Composer)

```text
Atue como Arquiteto de Software e Desenvolvedor Sênior Flutter/Firebase.
Transforme o Gestão Igreja em plataforma offline-first (Android, iOS, Web)
com sync silenciosa, login persistente, biometria, compressão 1024/70%,
uploads com progresso/timeout 30s, e módulos conforme prompt_mestre_cursor.md.
Priorize código existente (OfflineFirstCoordinator, OptimisticFirestoreWrite,
AuthService, YahwehMediaUploadPipeline). Não regredir quota Auth nem web persistence
sem fallback documentado. Responda em português; diff mínimo e focado.
```

---

## 11. Checklist de validação pós-alteração

- [ ] `dart analyze` nos ficheiros tocados (zero `error`)
- [ ] Cold start com sessão → biometria → painel
- [ ] Modo avião: criar aviso texto → aparece na UI → sync ao voltar online
- [ ] Chat: enviar foto → bolha com progresso → URL final
- [ ] Evento: vídeo > 90 s rejeitado antes do upload
- [ ] Web: publicar aviso sem «Future not completed»
- [ ] `version.json` build alinhado ao rodapé do painel

---

*Última revisão arquitectural: build 11.2.295+1751 — offline-first coordinator, persistence explícita, qualidade imagem 70%.*
