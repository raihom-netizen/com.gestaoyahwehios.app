# BKP MEMÓRIA — Ponto de partida Gestão YAHWEH (baseline produção)

> **Atualizado:** 2026-06-30  
> **Versão de referência:** `11.2.305+2034` (marketing fixo `11.2.305`; build `2034`)  
> **Projeto Firebase:** `gestaoyahweh-21e23`  
> **Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
> **Web produção:** https://gestaoyahweh-21e23.web.app  
> **Memória:** ficheiro único na raiz do repo — **não** copiar para `D:\Temporarios` (só artefactos AAB/ZIP/log de deploy vão para lá).

---

## 0. Como usar este arquivo (memória do agente / equipe)

1. **Antes de qualquer melhoria ou correção:** ler este documento + `.cursor/rules/` + `prompt_mestre_cursor.md`.
2. **Nunca retroagir:** evoluir serviços existentes; **proibido** `*ServiceV2`, novos resolvers paralelos, paths `tenants/` ou `church_aliases` no painel pós-login.
3. **Mídia (fotos, vídeos, áudio, PDF):** ordem **Storage → validar → Firestore uma vez**; gate obrigatório; **jamais** `Firestore.terminate()` no fluxo normal.
4. **Chat igreja:** `ChurchChatService` + `ChatStrictPublishService`; paths `igrejas/{churchId}/chats/...`; Storage `chat_media/`; **não** gravar `downloadURL` solto sem `storagePath`.
5. **Aceite:** `DEBUG CHURCH` 3 plataformas + `.\scripts\auditoria_acessos_firestore_storage.ps1` antes de declarar concluído.
6. **Deploy:** só com pedido explícito do usuário (`deploy_completo.ps1`).

**Docs irmãos (detalhe):**
- `docs/PADRAO_MESTRE_WISDOMAPP_YAHWEH_TOTAL.md`
- `docs/MAPEAMENTO_MIDIA_WISDOMAPP_IMPLEMENTACAO_CIRURGICA.md`
- `docs/MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`

---

## 1. Versão e ficheiros de build

| Campo | Valor |
|-------|--------|
| Marketing | `11.2.305` |
| Build | `2034` |
| `pubspec` | `flutter_app/pubspec.yaml` → `version: 11.2.305+2034` |
| Dart SSOT | `flutter_app/lib/app_version.dart` |
| Web JSON | `flutter_app/web/version.json` |
| Force update | Firestore `config/appVersion` → `minBuildNumber: 2034`, `forceUpdate: true`, `webRefresh: true` |

**Changelog resumido build 2034 (deploy 30/06/2026):**
- **EcoFire upload P0:** `ecofire_direct_firebase.dart` — init único sem `FirebaseBootstrap.reset()`; fim `core/no-app` ao publicar avisos/eventos/chat/financeiro/patrimônio/membros.
- **Pipeline:** `YahwehModuleMediaGate` → `EcoFireDirectFirebase` → comprimir → Storage `igrejas/{id}/…` → `getDownloadURL()` → Firestore.
- **Biometria:** `biometric_service.dart` — pref `biometric_disabled_by_user`; não reativa digital se utilizador desligou.
- **Storage audit:** tabela completa módulos em `church_storage_layout.dart` (doações/cartas/escala = sem Storage por desenho).
- **Deploy completo:** regras + índices + functions + web hosting + AAB + ZIP iOS Codemagic; commit `0a2a2f1` em `main`.

**Changelog resumido build 2017:**
- Paridade WISDOMAPP: gate mídia todos módulos, polling web 12s, índices `ativo+publicado+createdAt`, `public_church_slugs`, cache público anónimo, warmup web 16/40 membros.
- CF `gyPublicMemberSignup` na Web (cadastro membro público).
- Bridge Web: `AdminFeedFirestoreBridge` + `ChurchFunctionsService`.
- Cache-first: `YahwehModuleCaches` (17 módulos), shell lazy 2 módulos.
- Painel: card **Seus links públicos** antes de Aniversariantes (`igreja_dashboard_moderno.dart`).

---

## 2. Regras de ouro — NÃO REGREDIR

### 2.1 Tenant único (Firestore + Storage)

```
churchId resolvido UMA vez
  → Firestore: igrejas/{churchId}/...
  → Storage:   igrejas/{churchId}/...
```

**Proibido no painel igreja pós-login:**
- `collection('tenants')`, `church_aliases`, `church_roots`
- `TenantResolverService.resolveOperationalChurchDocId` em módulos do painel
- `FirebaseFirestore.instance` / `FirebaseStorage.instance` soltos em `lib/ui/`
- Novos resolvers — usar **`ChurchRepository.churchId(hint)`** como em `members_page.dart`

**Permitido na raiz Firestore:** `users/`, `admins/`, `app_public/`, `public_church_slugs/` (só leitura pública; write só CF).

### 2.2 Mídia — ordem strict (todos os módulos)

```
1. YahwehModuleMediaGate.ensureReadyForPick / prepareForPublishUpload
2. EcoFireDirectFirebase.ensureForStoragePut()   ← init único (NÃO resetar Firebase)
3. Comprimir (WebP/JPEG; vídeo H.264 720p eventos; áudio m4a chat)
4. Upload Storage (ChurchStorageLayout path canónico) via YahwehMediaUploadPipeline / EcoFireMediaUpload
5. Validar metadata Storage
6. Gravar Firestore UMA vez (URLs + storagePath)
7. UI sucesso → distribuição background (push, site, WhatsApp)
```

**Flag activa:** `EcoFireFlow.directStorageUpload` → todos os `uploadPreparedBytes` passam por `EcoFireMediaUpload`.

**Proibido (causa `core/no-app`):**
- `FirebaseBootstrap.reset()` ou `_softReinit` em fluxo de publicar/upload
- Múltiplas chamadas destrutivas a `EcoFirePublishBootstrap` / `runGuarded` em paralelo no upload

**Proibido:**
- Doc Firestore completo com mídia **antes** do Storage OK (exceto stub chat `sending` explícito)
- `mediaUploadState: uploading` eterno no Firestore
- `Image.network` direto para URLs Firebase na Web — usar **`SafeNetworkImage`**
- Upload ad-hoc `putData` na UI sem pipeline/gate (exceto Master divulgação CMS — evoluir para pipeline)

### 2.3 Chat igreja — não quebrar

| Item | Canónico |
|------|----------|
| Firestore | `igrejas/{churchId}/chats/{chatId}/messages/{msgId}` |
| Storage | `igrejas/{churchId}/chat_media/{images\|videos\|audio\|docs}/` + `thumbs/` |
| Texto | Uma escrita Firestore; UI otimista |
| Mídia | Storage → `writeMediaMessageFirestoreOnce` via `ChatStrictPublishService` |
| Campos | `tipo`, `storagePath`, `status` — preferir `storagePath` sobre URL solta |
| Web gate | `YahwehModuleMediaGate` + `module: YahwehMediaModule.chat` |
| Polling web msgs | 12s (`ChurchPanelReadTimeouts.webPollInterval`) |
| Lista | Paginação 20–30; **sem** player inline na lista |

### 2.4 Web Firestore — estabilidade

- **Proibido** `snapshots()` em listas longas na Web → usar `.watchSafe()` / `queryWatchBootstrap` → polling **12s**
- Antes de gravar Web: `FirestoreWebGuard.prepareForPublishWrite()` + `runWithWebRecovery(maxAttempts: 4)`
- Cap leitura painel: **14s** (`ChurchPanelReadTimeouts.queryCap`)
- Skeleton: só se lista vazia; **nunca** apagar cache RAM/Hive antes da rede responder

### 2.5 Offline-first

- Cache → tela abre → refresh silencioso
- `SyncEngine` + `TenantOfflineWrite` + `OptimisticFirestoreWrite`
- Falha de rede **não** substitui tela inteira por erro se há dados locais

---

## 3. Gates (gatinhos) — API única

### 3.1 `YahwehModuleMediaGate` (`lib/core/yahweh_module_media_gate.dart`)

| Método | Quando |
|--------|--------|
| `ensureReadyForPick` | Antes de câmera/galeria/file picker |
| `ensureReadyForPublish` | Antes de gravar metadados |
| `prepareForPublishUpload` | Antes de upload+publish (avisos, eventos, patrimônio, financeiro, membros, cadastro) |
| `ensureReadyForPublicMedia` | Site público / divulgação / cadastro visitante |
| `recoverNoAppAfterPublishError` | Após `core/no-app` ou client terminated |
| `recoverAfterTerminatedIfWeb` | Web pós-erro SDK |

**Módulos enum `YahwehMediaModule`:** `eventos`, `avisos`, `membros`, `patrimonio`, `financeiro`, `chat`, `cadastro`, `divulgacao`.

### 3.2 Por módulo — gate + publish strict

| Módulo | Pick gate | Publish gate | Serviço strict / pipeline |
|--------|-----------|--------------|---------------------------|
| **Avisos** | `MediaHandlerService` + gate | `prepareForPublishUpload` | `AvisoStrictPublishService` → `ChurchFeedLinearPublishService` / `PublicationEngine` |
| **Eventos** | idem | idem | `EventoStrictPublishService` |
| **Patrimônio** | idem | idem | `PatrimonioStrictPublishService` |
| **Financeiro** | `FinanceComprovanteAttachService` | `_ensureFinanceWriteReady` | `FinanceComprovantePublishService`; CF Web `gyUploadFinanceComprovante` |
| **Membros foto** | `MemberProfilePhotoPickService` | `prepareForPublishUpload` | `MemberProfilePhotoSaveService` / `YahwehCentralEngineService` |
| **Cadastro igreja logo** | `MediaHandlerService` | `prepareForPublishUpload` | `YahwehCentralEngineService.executeSingleLogoSave` |
| **Chat** | `YahwehModuleMediaGate.chat` | `ChatStrictPublishService` | `ChurchChatMediaSendService` + `ChatAudioService` |
| **Cadastro membro público** | gate `membros` | CF Web `gyPublicMemberSignup` | **não** `gyAdminUpsertFeedPost` para visitante anónimo |
| **Divulgação Master** | gate `divulgacao` | `prepareForPublishUpload` | `admin_divulgacao_media_page.dart` |
| **Marketing clientes** | gate `divulgacao` | idem | `admin_marketing_clientes_tab.dart` |

### 3.3 Bridge Web (Firestore writes pesados)

| Ficheiro | Função |
|----------|--------|
| `lib/utils/admin_feed_firestore_bridge.dart` | `upsertTenantDoc`, `encodeMap`, timeout 45s Web |
| `lib/services/church_functions_service.dart` | `adminUpsertFeedPost`, `publicMemberSignup`, `uploadFinanceComprovante` |

**CFs correspondentes** (`functions/src/gyMediaAttachments.ts`):
- `gyAdminUpsertFeedPost` — avisos, eventos, membros, fornecedor_compromissos, chats/messages (auth gestor)
- `gyPublicMemberSignup` — cadastro membro público Web (auth opcional)
- `gyUploadFinanceComprovante` — comprovante financeiro Web
- `gyAdminDeleteFeedPosts` — exclusão lote feed

---

## 4. Firestore — estrutura canónica

```
igrejas/{churchId}/
├── membros/{id}
├── avisos/{id}          (ou mural_avisos — alinhar ao módulo ativo)
├── eventos/{id}
├── patrimonio/{id}
├── finance/{id}         (UI: financeiro)
├── chats/{chatId}/messages/{msgId}
├── departamentos/, cargos/, visitantes/, escalas/, agenda/
├── fornecedores/, fornecedor_compromissos/
├── _performance_cache/public_feed   (CF generatePublicFeedCache)
├── _panel_cache/*                   (dashboard)
└── config/mercado_pago, etc.

public_church_slugs/{slugKey}   → read público; write só CF/index
app_public/                     → site divulgação Master
users/{uid}                     → perfil global Auth
```

**Gateway único painel:** `ChurchRepository` + `ChurchUiCollections` + load services `church_*_load_service.dart`.

**Cache RAM/prefs:** `YahwehModuleCaches` (`lib/core/cache/yahweh_module_caches.dart`) — membros, avisos, eventos, financeiro, patrimônio, chat-adjacent, etc.

**Shell:** `igreja_clean_shell.dart` — máx. **2** módulos materializados (`church_shell_lazy_module_policy.dart`).

---

## 5. Storage — árvore canónica

```
igrejas/{churchId}/
├── membros/{folder}/foto_perfil.jpg
├── avisos/imagens/
├── eventos/imagens|videos|thumbs/ + eventos/templates/
├── patrimonio/{itemId}/foto_N.webp
├── financeiro/YYYY_MM/{lancamentoId}.ext
├── chat_media/{images|videos|audio|docs}/ + thumbs/
├── configuracoes/logo_igreja.png + assinatura.*
├── cartao_membro/logo.jpg
├── certificados/logo_atual.jpg + templates/certificados/
├── certificados_gestor/{uid}_{ts}.p12
├── fornecedores/{fornecedorId}/compromissos/{id}_comprovante.ext
└── marketing_destaque/capa.jpg   (Master clientes)

public/gestao_yahweh/{fotos|videos|pdf}/   (Master divulgação CMS)
```

**Sem upload Storage (por desenho):** doações (MP+Firestore), cartas/transferências (PDF local + `cartas_historico`), escala, agenda pura.

**SSOT paths:** `lib/core/church_storage_layout.dart`  
**Upload:** `EcoFireDirectFirebase`, `YahwehMediaUploadPipeline`, `UnifiedUploadService`, `uploadStoragePutDataWithRetry`  
**Proibido escrita nova:** `tenants/{id}/media/...` (legado só leitura)

---

## 6. Firestore Rules — pontos críticos (2026-06-28)

Ficheiro: `firestore.rules` (publicar via `.\scripts\deploy_firebase_rules.ps1`)

| Regra | Detalhe |
|-------|---------|
| `public_church_slugs/{slugKey}` | `allow read: if true`; `allow write: if false` (CF index) |
| `igrejas/{id}` | `allow read: if true` (site público + painel) |
| `igrejas/{id}/membros` | create público pendente + gestor; update com `sameChurch` |
| `igrejas/{id}/chats` | coleção canónica chat (**não** `chat_threads`) |
| `isPlatformOperator()` | Master produto (e-mail/CPF/admins) — **não** confundir com gestor local |
| `sameChurch(tenantId)` | Tolerância formatos legado `id_`, `v_`, paths |

**Chave GCP deploy:** `gestaoyahweh-gcp-deploy-key.json` na raiz (regras GCP REST).

---

## 7. Storage Rules — pontos críticos

Ficheiro: `storage.rules`

| Path | Uso |
|------|-----|
| `igrejas/{id}/membros/**` | Fotos perfil |
| `igrejas/{id}/avisos/**` | Imagens avisos |
| `igrejas/{id}/eventos/**` | Fotos + vídeos eventos |
| `igrejas/{id}/patrimonio/**` | Fotos patrimônio |
| `igrejas/{id}/financeiro/**` | Comprovantes |
| `igrejas/{id}/chat_media/**` | Chat mídia |
| `public/**` | Site institucional global |

**CORS Web:** `.\scripts\apply_firebase_storage_cors.ps1`

---

## 8. Firestore Indexes — obrigatórios (não remover)

Ficheiro: `firestore.indexes.json` — publicar com regras.

| collectionGroup | Campos (resumo) | Uso |
|-----------------|-----------------|-----|
| **avisos** | `ativo` + `publicado` + `createdAt DESC` | Site público + mural |
| **eventos** | `ativo` + `publicado` + `createdAt DESC` | Site público + agenda |
| **avisos/eventos** | `publicado` + `createdAt DESC` | Feed painel |
| **membros** | `status`, `birthMonth`+`birthDay`, etc. | Lista + aniversariantes |
| **finance** | `data`, `tipo`, etc. | Financeiro |
| **chats/messages** | `createdAt DESC` | Chat paginado |
| **escalas** | múltiplos | Escalas |

Após deploy: confirmar índices **Enabled** no Console Firebase (pode levar minutos).

---

## 9. Cloud Functions — inventário essencial

### 9.1 Mídia / tenant / publicação (WISDOMAPP)

| Function | Região | Papel |
|----------|--------|-------|
| `gyAdminUpsertFeedPost` | us-central1 | Write Admin SDK feed/membros/chat/fornecedores Web |
| `gyPublicMemberSignup` | us-central1 | Cadastro membro público Web |
| `gyUploadFinanceComprovante` | us-central1 | Comprovante financeiro Web |
| `gyAdminDeleteFeedPosts` | us-central1 | Delete lote avisos/eventos |

### 9.2 Chat

| Function | Papel |
|----------|-------|
| `onChurchChatMessageCreated` | Push notificação |
| `onIgrejaMembroWriteChatPeerProfile` | Sync perfil peer |
| `pruneExpiredChurchChatMessages` | Retenção |
| `purgeChurchChatMessagesAdmin` | Purge ADM |

### 9.3 Site público / performance

| Function | Papel |
|----------|-------|
| `generatePublicFeedCache` | `_performance_cache/public_feed` |
| `generateBirthdayCache` | Aniversariantes cache |
| `backfillPublicChurchSlugIndex` | Índice `public_church_slugs` |
| `warmChurchTenantCaches` | Warmup painel |
| `scheduledRefreshPanelCaches` | Cache dashboard |

### 9.4 Auth / igreja

| Function | Papel |
|----------|-------|
| `repairMyChurchBinding` | Fix permission-denied pós-login |
| `setMemberApproved` | Aprovar membro público |
| `provisionChurchTenantCallable` | Provision tenant |

**Deploy functions:** incluído em `.\scripts\deploy_completo.ps1` ou `-ForceFunctions`.

---

## 10. Superfícies — checklist baseline 2034

| Superfície | Ficheiro principal | Status baseline |
|------------|-------------------|-----------------|
| **Painel igreja** | `igreja_clean_shell.dart`, `igreja_dashboard_moderno.dart` | Cache-first, links públicos card, watchSafe 12s |
| **Painel Master** | `admin_panel_page.dart`, `admin_divulgacao_media_page.dart` | Gate divulgação, `runWithWebRecovery` writes |
| **Site divulgação** | `site_public_page.dart` | `app_public/*`, `ensureReadyForPublicMedia` |
| **Site igreja público** | `church_public_page.dart` | `PublicChurchSlugResolver`, `_performance_cache` |
| **Cadastro membro** | `public_member_signup_page.dart` | Web → `gyPublicMemberSignup`; sem `alias`/`tenantId` no doc |

---

## 11. Limites de mídia por módulo (não alterar sem decisão explícita)

| Módulo | Fotos | Vídeo | Áudio | PDF |
|--------|-------|-------|-------|-----|
| Membros | 1 (1024+thumb 200) | ❌ | ❌ | ❌ |
| Avisos | 5 | ❌ | ❌ | ❌ |
| Eventos | 5 | 1 × 90s 720p | ❌ | ❌ |
| Patrimônio | 5 | ❌ | ❌ | ❌ |
| Chat | ✅ | ✅ | ✅ | ✅ |
| Financeiro | comprovante | ❌ | ❌ | ✅ |

**Compressão:** imagens ~150–300 KB feed; perfil 1024 @ 80%; Web = `WebImageCompressService` (Dart puro).

---

## 12. Serviços — mapa rápido (não duplicar)

| Papel | Ficheiro |
|-------|----------|
| Tenant Firestore | `ChurchRepository` |
| Init Firebase upload | `EcoFireDirectFirebase` (`lib/core/ecofire/ecofire_direct_firebase.dart`) |
| Gate UI mídia | `YahwehModuleMediaGate` |
| Upload bytes | `YahwehMediaUploadPipeline`, `EcoFireMediaUpload`, `UnifiedUploadService` |
| Publicação mural | `PublicationEngine`, `AvisoPublishService`, `EventoPublishService` |
| Chat | `ChurchChatService`, `ChatStrictPublishService` |
| Biometria | `BiometricService` (`biometric_disabled_by_user`) |
| Auth | `AuthService`, `PersistentAuthSessionService` |
| Web guard | `FirestoreWebGuard`, `FirestoreStreamUtils` |
| Imagens UI | `SafeNetworkImage`, `UnavailableMediaWidget` |
| Performance web | `YahwehDataEngineFetcher`, `ChurchPanelReadTimeouts` (poll 12s) |
| Sync offline | `SyncEngine`, `TenantOfflineWrite` |

---

## 13. UI — painel dashboard (links públicos)

**Ficheiro:** `lib/ui/pages/igreja_dashboard_moderno.dart`  
**Widget:** `_LinksPublicosStrip` → `_LinksPublicosPremiumCard`  
**Posição:** após atalhos (Ano todo / Galeria / Organograma), **antes** de Aniversariantes  
**Slug:** recebe `churchSlug` do pai (`_churchSlug`) — não esconder card quando cadastro concluído  
**URLs:**
- Site: `{publicWebBaseUrl}/igreja/{slug}`
- Cadastro: `AppConstants.publicChurchMemberSignupUrl(slug)`

---

## 14. Scripts operacionais

```powershell
cd C:\gestao_yahweh_premium_final
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1

# Auditoria legado (obrigatória antes de encerrar tarefa)
.\scripts\auditoria_acessos_firestore_storage.ps1

# Preflight código
.\scripts\preflight_deploy_compile.ps1

# Bump build (+N apenas)
.\scripts\bump_build.ps1

# Deploy completo (só se usuário pedir)
.\scripts\deploy_completo.ps1 -CopyTo "D:\Temporarios" -ForceFunctions -ContinueOnRulesFailure

# Artefactos deploy (AAB/ZIP/log) → D:\Temporarios
# Memória deste projeto → BKP_MEMORIA_PONTO_PARTIDA_YAHWEH.md (raiz repo, sem cópia)
```

---

## 15. Proibições absolutas (causam regressão)

1. `FirebaseFirestore.instance` / `.collection('tenants')` no painel igreja UI  
2. Segundo `Firebase.initializeApp` (`core/no-app`)  
3. `terminate()` Firestore em publish/upload  
4. `StreamBuilder` + `snapshots()` em listas longas na Web  
5. Upload Storage **depois** de doc Firestore completo (strict modules)  
6. `Image.network` para Storage URLs na Web  
7. Criar `*ServiceV2`, `*RepositoryNew`, novos resolvers tenant  
8. Hardcode `igreja_o_brasil_para_cristo_jardim_goiano` em código novo  
9. Gravar `alias`, `tenantId`, `church_aliases` em docs de módulo  
10. Deploy/build sem pedido explícito do usuário  

---

## 16. Testes mínimos antes de release (não pular)

1. Publicar aviso 1 foto (Web) — sem travar 78%  
2. Publicar evento 1 foto + 1 vídeo curto  
3. Chat: texto + imagem + áudio  
4. Membro: trocar foto  
5. Financeiro: anexar comprovante  
6. Patrimônio: 1 foto  
7. Cadastro membro público Web (visitante)  
8. Site público por slug  
9. Links públicos no dashboard (abrir + copiar)  
10. Offline → online (lista preservada)  

**Prova formal:** Configurações → DEBUG CHURCH → Publicar prova (Web/Android/iOS).

---

## 17. Igreja piloto / aceite

- **churchId canónico teste:** `igreja_o_brasil_para_cristo_jardim_goiano`  
- **Slug público BPC:** `o-brasil-cristo-jardim-goiano`  
- Paths aceite: **somente** `igrejas/{churchId}/...`

---

## 18. Histórico deste baseline (git)

- **Build actual memória:** **2034** — EcoFire upload, biometria opt-out, auditoria Storage, deploy completo 30/06/2026  
- Commit deploy 2034: `0a2a2f1` — `chore: deploy producao 11.2.305+2034`  
- AAB: `GestaoYahweh_11.2.305_build2034_play.aab` · iOS ZIP: `GestaoYahweh_ios_sources_11.2.305_build2034.zip`  
- Commit referência deploy 2016: `6a197b3` — cache WISDOMAPP, CF bridge, gyPublicMemberSignup  
- Build 2017 — paridade mídia, índices, links dashboard, cadastro CF Web  

---

*Este ficheiro é a **memória de ponto de partida**. Atualizar o número de build e a secção 18 após cada release significativa. Fica **só na raiz** do repo (`C:\gestao_yahweh_premium_final\`). Não apagar secções 2 e 15 — são o antídoto contra regressões de mídia, chat e tenant.*
