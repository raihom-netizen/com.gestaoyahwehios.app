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

**Uma vez por máquina** — alinhar Google Cloud ao projeto (token para preflight/REST; evita «Sem gcloud token»):

```powershell
.\scripts\setup_google_cloud_automatico.ps1
```

Usa `gestaoyahweh-21e23`, `gcloud auth login`, ADC e, se existir localmente, chave em `ANDROID/*-firebase-adminsdk*.json` ou `secrets/`.

Na raiz do repositório (PowerShell):

```powershell
.\scripts\deploy_firebase_rules.ps1
```

Isto publica **Firestore + índices + Storage** com:

1. **GCP auth** — `ensure_google_cloud_auth.ps1` (PATH gcloud + token utilizador/ADC/conta de serviço).
2. **Preflight** — compara local vs remoto (REST read-only); se igual, **não chama** `firebaserules.googleapis.com/test` (evita 503).
3. **Fallback REST** — se CLI `/test` falhar com 503, publica `firestore.rules` via API Rules (retry 503).
4. **Retry background** — `deploy_firebase_rules_background.ps1` (log em `.deploy-state/firebase-rules-background.log`).

```powershell
.\scripts\deploy_firebase_rules.ps1 -ForcePublish
# Deploy completo (web+AAB+iOS continuam se regras falharem):
.\scripts\deploy_completo.ps1
```

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
├── repositories/   # fachadas UI → serviços
│   ├── auth_repository.dart      → AuthService
│   └── storage_repository.dart   → StorageService
├── services/       # auth_service.dart, storage_service.dart, chat, mural
├── ui/pages/       # só UI + navegação — sem queries Firestore directas
└── ui/widgets/
```

**Regras**

- Telas **não** chamam `FirebaseFirestore.instance` / `FirebaseStorage.instance` directamente.
- Preferir `AuthService`, `StorageService`, `AuthRepository`, `StorageRepository`, `ChurchDataService`, `OptimisticFirestoreWrite`.
- Uploads múltiplos: `StorageRepository.uploadPhotosParallel` ou `FeedPostMediaUpload.uploadParallel` (já usado em avisos, eventos, património) — paralelismo limitado via `Future.wait` em lotes, não sequencial.

**Já implementado**

- Avisos/eventos: `mural_fast_publish_service.dart`, `mural_post_media_payload.dart`
- Património: `patrimonio_publish_service.dart` (`Future.wait` por chunk)
- Chat: outbox + stub Firestore assíncrono

---

## 9. Compatibilidade Flutter Web

- Seleção/compressão: **`XFile.readAsBytes()`** / `Uint8List` — ver `lib/core/web_safe_media.dart`.
- Upload: **`putData`** via `uploadStoragePutDataWithRetry` / `StorageService.uploadBytes` — `putFile` só mobile (`upload_bytes_core` redirecciona na Web).
- `MediaHandlerService` usa imports condicionais (`media_handler_service_io` / `_web`).

## 10. Cache de imagens na UI

- Firebase (membros, património, chat, eventos): **`SafeNetworkImage`** ou **`ResilientNetworkImage`** (delegam a `CachedNetworkImage` quando seguro).
- **`Image.network`** apenas como último recurso interno em `safe_network_image.dart` (CORS web).
- Preview local (picker): **`MemoryImage(Uint8List)`**, nunca `FileImage`/`NetworkImage` para blob na Web.

## 11. Chat realtime + paginação

- **`ChurchChatService.recentMessagesStream`** — `snapshots()` + `orderBy(messageTimestampField)` (`createdAt`) **desc** + `limit(20)`.
- Histórico: **`loadOlderMessagesPage`** ao scroll (`church_chat_thread_page.dart`).
- Texto optimista + mídia assíncrona (stub + progresso no balão).

---

## 12. Fila de upload em background (Upload Queue)

- **Objetivo:** mídias pesadas (2 vídeos 90s em Eventos, 10 fotos) **não cancelam** ao fechar/minimizar o app.
- **Serviço:** `lib/services/background_upload_worker.dart` — drena em série: mural outbox → `pending_uploads` (disco) → chat outbox → sync offline.
- **Persistência:** `StorageUploadPersistenceService` copia bytes para `pending_uploads/` + manifest SharedPreferences; `MuralPublishOutboxService.registerJob` para avisos/eventos.
- **Arranque/resume:** `AppFinalizeBootstrap.runAutomaticRecovery()` → `BackgroundUploadWorker.drainAll()`.
- **Mobile:** fila local sobrevive ao fecho; retoma no cold start e ao voltar do background (`AppSessionStability.onGlobalResume`). WorkManager opcional futuro para Android com app morto.

## 13. Compressão nativa de vídeo (H.264/AAC)

- **Pacote:** `video_compress` — `includeAudio: true`, codec H.264 + AAC.
- **Qualidade:** `lib/core/media_video_compress_quality.dart` — 720p default; **480p** se ficheiro > 50 MB.
- **Eventos:** `MediaService.prepareEventVideoForUpload` (sempre transcode) + `EventoGalleryService` antes do upload.
- **Limite:** duração máxima eventos = `kMediaEventVideoMaxSeconds` (90s); rejeitar antes de comprimir.

## 14. Contadores denormalizados (dashboard_stats)

- **Documento:** `igrejas/{tenantId}/dashboard_stats/summary` — campos `members`, `avisos`, `eventos`.
- **Leitura:** `ChurchTenantDashboardDocService.readOnce` — cache-first, **sem** `count()` na coleção `membros`.
- **Escrita:** `DashboardStatsCounterService.onMemberCreated/onMemberDeleted` — `FieldValue.increment` síncrono ao criar/apagar membro; espelha `_panel_cache/dashboard_summary.membersTotalCount`.

## 15. Empty states e retry na UI

- **Widget:** `lib/ui/widgets/unavailable_media_widget.dart` — «Imagem indisponível» + botão «Tentar novamente».
- **Uso:** `defaultImageErrorWidget`, `MediaView`, `SafeNetworkImage` / `ResilientNetworkImage` (fallback de erro).
- **Regra:** nunca tela branca por 404 Storage ou falha de cache — sempre placeholder amigável.

## 16. Chat — retenção seletiva de Storage (90 dias)

- **Serviço:** `ChurchChatStorageRetentionService` — remove mídia de chat comum > 90 dias.
- **Preserva:** `preserveMedia`, threads oficiais/anúncio, paths `/avisos/` e `/eventos/`, mensagens favoritas (star → `preserveMedia: true`).
- **Execução:** `BackgroundUploadWorker.drainAll` (≈1×/20h por tenant); texto da mensagem mantém-se.

## 17. Paginação em listas (lazy loading)

- **Padrão:** `YahwehPerformanceV4.defaultPageSize` = **20** — Membros, Patrimônio, Financeiro, Fornecedores, Eventos.
- **Helper:** `LazyFirestoreListController` + botão «Carregar mais» nas telas grandes.
- **Regra:** nunca `.get()` / `.limit(500+)` na lista principal sem paginação.

## 18. Conflitos offline (Last Write Wins)

- **Carimbo:** `FirestoreLastWriteWins` — `updatedAt: FieldValue.serverTimestamp()` + `clientWriteSeq` em toda escrita via `TenantOfflineWrite`.
- **Política:** última gravação com timestamp do servidor prevalece; evita corrupção em edições simultâneas offline.

## 19. Compartilhar via WhatsApp (`share_plus`)

- **Serviço:** `YahwehShareService` — PDF em memória ou texto sem guardar manualmente.
- **Widget:** `YahwehShareButton` / `shareAvisoWhatsApp` — Certificados, Cartão, Avisos, Relatórios financeiros.
- **Pacote:** `share_plus` — folha nativa; utilizador escolhe WhatsApp.

## 20. Versão e deploy

### 20.1 Controlo de versão

Alinhar sempre (marketing fixo **11.2.295** salvo pedido explícito):

1. `flutter_app/lib/app_version.dart`
2. `flutter_app/pubspec.yaml` — `version: 11.2.295+N`
3. `flutter_app/web/version.json`

Incrementar `+N` quando houver código a entregar; obrigatório em publicação lojas.

### 20.2 Scripts

| Pedido | Comando |
|--------|---------|
| Só web | `.\scripts\deploy_web_hosting.ps1` (CanvasKit) ou `deploy_web_hosting_html_dom.ps1` |
| Só regras | `.\scripts\deploy_firebase_rules.ps1` |
| Completo | `.\scripts\deploy_completo.ps1` |

URL produção: **https://gestaoyahweh-21e23.web.app** — após deploy, **Ctrl+F5** / limpar dados PWA.

---

## 21. Comando mestre (Composer — opcional)

> **Cursor já está configurado:** regras `prompt-mestre-arquitetura.mdc` e `configuracao-mestre-automatica.mdc` têm `alwaysApply: true`. Ver também `AGENTS.md`.

Para reforçar numa tarefa específica, use `@prompt_mestre_cursor.md` ou cole:

```text
Implementação alinhada ao prompt_mestre_cursor.md — offline-first, AuthService, StorageService,
sem regressões de quota Auth. Responda em português; diff mínimo.
```

---

## 22. Checklist de validação pós-alteração

- [ ] `dart analyze` nos ficheiros tocados (zero `error`)
- [ ] Cold start com sessão → biometria → painel
- [ ] Modo avião: criar aviso texto → aparece na UI → sync ao voltar online
- [ ] Chat: enviar foto → bolha com progresso → URL final
- [ ] Evento: vídeo > 90 s rejeitado antes do upload
- [ ] Web: publicar aviso sem «Future not completed»
- [ ] Web: picker usa bytes (`XFile`); upload `putData`; preview `MemoryImage`
- [ ] Upload pesado: fechar app → reabrir → fila retoma (`BackgroundUploadWorker`)
- [ ] Evento: vídeo comprime para 720p/480p antes do envio
- [ ] Dashboard: total membros vem de `dashboard_stats/summary` (sem count live)
- [ ] Chat: mídia > 90d apagada do Storage; favoritas preservadas
- [ ] Listas: 20 itens iniciais + «Carregar mais» (membros, patrimônio, financeiro, fornecedores, eventos)
- [ ] Offline: duas edições no mesmo doc — LWW com `updatedAt` servidor
- [ ] Compartilhar: PDF/texto abre folha nativa (WhatsApp)

---

## 23. Veredicto de conformidade (build 11.2.295+1764)

| § | Requisito | Estado | Implementação |
|---|-----------|--------|---------------|
| 0 | Auth sem `getIdToken(true)` em leituras | **OK** | `FirebaseAuthTokenGuard` + `FirestoreStreamUtils` nos módulos §12–19 e aprovações |
| 8 | UI → serviços (não Firestore cru) | **OK** | `ChurchTenantResilientReads`, serviços dedicados (upload, stats, share, retention) |
| 12 | Fila upload background serial | **OK** | `BackgroundUploadWorker` + `AppFinalizeBootstrap` |
| 13 | Vídeo 720p/480p H.264 | **OK** | `MediaService.prepareEventVideoForUpload` |
| 14 | Contadores `dashboard_stats` | **OK** | `DashboardStatsCounterService` (membros, mural, cadastro público) |
| 15 | Empty states + retry mídia | **OK** | `UnavailableMediaWidget`, `defaultImageErrorWidget` |
| 16 | Retenção chat 90d | **OK** | `ChurchChatStorageRetentionService` + `preserveMedia` |
| 17 | Paginação lazy 20 | **OK** | `LazyLoadMoreFooter` + certificados/finance/liderança |
| 18 | LWW offline | **OK** | `firestore_last_write_wins` em `tenant_offline_write` |
| 19 | Partilha WhatsApp | **OK** | `YahwehShareService` |
| — | Cadastro público + foto | **OK** | Firestore-first; `MemberProfilePhotoUpdateService` BG (`requireAuth: false` visitante) |
| — | Certificados lista membros | **OK** | `membrosRecent` 20+«Carregar mais» (não `.get()` ilimitado) |
| — | Financeiro gráficos home | **OK** | `financeChartsSampleLimit` (100) em vez de 2500 |

| — | Cartão membro | **OK** | Índice signatários + paginação 40 + cache foto PDF + CF `refreshCarteiraSignatoriesIndex` |
| — | Património leituras | **OK** | Lista 20+lazy; formulário/tabs via `ChurchTenantResilientReads` (cache-first, sem `Source.server`) |
| — | Chat igreja envio | **OK** | Texto otimista local; mídia stub+bytes paralelos; thumb+full paralelo; outbox prioridade; pickers sem await Firebase |

**Políticas documentadas:** exportações admin usam `adminExportBatchLimit` (500); gráficos/dashboard master usam constantes `master*` em `YahwehPerformanceV4`.

---

| — | Deploy Firebase / GCP | **OK** | `setup_google_cloud_automatico.ps1`, `ensure_google_cloud_auth.ps1`, preflight REST, fallback Rules API |

*Última revisão arquitectural: build 11.2.295+1764 — Cursor auto-configurado via `.cursor/rules/prompt-mestre-arquitetura.mdc` + `AGENTS.md`.*
