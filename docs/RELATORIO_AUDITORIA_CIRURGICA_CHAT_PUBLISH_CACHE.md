# Auditoria cirúrgica — Chat, Publicação, Upload, Cache, Dashboard

**Data:** 2026-06-01 · **Build:** `11.2.295+1728`  
**Pedido:** descomplicar e estabilizar — **sem** alterar design, telas ou funcionalidades.  
**Entrega:** relatório **antes** de refactors massivos (avaliação do utilizador confirmada).

---

## 1. Diagnóstico em uma frase

O projeto **não falta código** — há **camadas redundantes** (outbox local + `chat_uploads` + warmups paralelos + caches sobrepostos) que competem pelo mesmo trabalho. Os sintomas (mensagem presa, aviso que não publica, lentidão) encaixam em **estado duplicado** e **retentativas em cascata**, não em ausência de Storage/Firestore.

---

## 2. Mapa «fonte de verdade» (o que deve mandar)

### Chat

| Papel | Serviço | O que grava / controla |
|-------|---------|-------------------------|
| **Firestore mensagens** | `church_chat_service.dart` | `igrejas/{t}/chats/{thread}/messages/{id}` — texto, mídia, `status` / `deliveryStatus` |
| **Entrada UI texto** | `church_chat_instant_send_service.dart` | Delega 100% a `beginTextMessage` + `finalizeTextMessage` |
| **Entrada UI mídia** | `optimistic_chat_media_upload.dart` | Stub → Storage → `completeMediaUploadMessage` |
| **Paralelismo** | `church_chat_media_upload_coordinator.dart` | Máx. 3 uploads simultâneos (não é fila de negócio) |
| **Espelho progresso** | `church_chat_uploads_service.dart` | `igrejas/{t}/chat_uploads/{id}` — metadados de retoma |
| **Retoma pós-app morto** | `church_chat_media_outbox_service.dart` | JSON em `SharedPreferences` + `_resumeAll` ao voltar online |
| **Bolha local** | `church_chat_outbound_pending.dart` | Modelo em memória (UI), aponta para `firestoreMessageId` |
| **Bytes em disco** | `church_chat_pending_media_cache.dart` | Cache de ficheiro para reenvio |
| **Lista conversas local** | `church_chat_local_conversations.dart` | Índice/cache de previews (não substitui Firestore) |
| **Limpeza** | `church_chat_stuck_cleanup_service.dart` | Apaga stubs `sending`/`uploading` antigos + filas |

**Texto na thread (`church_chat_thread_page.dart`):** usa `ChurchChatInstantSendService.enqueueText` — **correto** (Firestore directo, sem CF).

**Mídia na thread:** usa `OptimisticChatMediaUpload.flush` — **correto** (stub antes do upload).

**Duplicado legado:** `ChurchChatService.sendTextMessage` ainda existe e é usado em `church_chat_church_features.dart` (funções da igreja), não no composer principal.

---

### Avisos / Eventos

| Papel | Serviço |
|-------|---------|
| **Firestore primeiro** | `feed_media_publish_fast.dart` |
| **API UI** | `feed_media_publish_service.dart` → `publish()` / `publishNow()` |
| **Upload background** | `mural_fast_publish_service.dart` |
| **Retoma interrompida** | `mural_publish_outbox_service.dart` (SharedPreferences) |
| **Legado (não usar)** | `feed_media_publish_strict.dart` — só delega ao fast |
| **Warm** | `fast_media_publish_bootstrap.dart` + `immediate_media_warm.dart` |

**Push / feed:** Cloud Function (`pushNovoConteudo`) **depois** de `publishState: published` — não bloqueia o botão Publicar no cliente.

`church_media_publish_policy.dart` — **documentação** + exports (não é fila).

`church_public_feed_service.dart` — leitura site público com **paginação 20** — OK.

---

### Dashboard / cache

| Papel | Serviço | Documento / coleção |
|-------|---------|---------------------|
| **Contadores topo (pedido)** | `church_tenant_dashboard_doc_service.dart` | `igrejas/{t}/dashboard/home` |
| **Resumo rico painel** | `panel_dashboard_snapshot_service.dart` | `igrejas/{t}/_panel_cache/dashboard_summary` |
| **Cache CF site/aniversários** | `church_performance_cache_service.dart` | `igrejas/{t}/_performance_cache/*` |
| **Warmup agregador** | `church_tenant_dashboard_warmup_service.dart` | Dispara **vários** warmups ao abrir shell |
| **Offline prefetch** | `church_tenant_offline_warmup_service.dart` | Pré-leituras Firestore |
| **Leituras resilientes** | `church_tenant_resilient_reads.dart` | Wrapper cache+retry |

**Problema:** o pedido «só `church_tenant_dashboard_doc_service`» **não está cumprido na UI** — `igreja_dashboard_moderno.dart` ainda combina `_panel_cache`, streams de membros e múltiplos `.snapshots()`.

---

## 3. Filas e duplicações (onde trava)

### Chat — **4 camadas** para o mesmo upload

```
UI OptimisticChatMediaUpload.flush
  → ChurchChatService (mensagem Firestore)
  → Storage (UnifiedUploadService / MediaUploadService)
  → ChurchChatUploadsService (doc chat_uploads)
  → ChurchChatMediaOutboxService (prefs local + resume on connectivity)
  → (opcional) PendingUploadsFirestoreService — DESLIGADO por política
```

| Fila | Activa? | Risco |
|------|---------|-------|
| `chat_uploads` Firestore | Sim | Doc órfão se `markDone` falhar |
| `church_chat_media_outbox` prefs | Sim | Jobs «fantasma» se bytes/path perdidos → banner «N pendentes» |
| `pending_uploads` Firestore | **Não** (`firestorePendingQueueEnabled = false`) | Código ainda referenciado em cleanup/stuck |
| `StorageUploadQueueService` | Memória | Limpo no «Limpar chat» |

**Retentativas:** `optimistic_chat_media_upload` — timeout 8–18 min + `_deferForRetry` + outbox `_resumeAll` ao reconectar → **não é infinito**, mas pode **repetir** o mesmo job se prefs e `chat_uploads` divergirem.

**Mensagens presas:** `deliveryStatus` em `sending` / `uploading` sem `completeMediaUploadMessage` — causas típicas: rede após Storage OK; `update` Firestore falhou; app morto antes do merge. **Correcção operacional:** `ChurchChatStuckCleanupService` / botão Limpar no hub.

**Cloud Function para aparecer mensagem:** **não** — texto e stub são `set`/`update` directos. CF só notifica push.

---

### Avisos/Eventos — **3 camadas** de retoma

```
FeedMediaPublishFast (Firestore stub)
  → MuralFastPublishService (upload)
  → MuralPublishOutboxService (prefs se interrompido)
  → AppFinalizeBootstrap resume on start/resume
```

Publicação **normal** já não bloqueia no upload (build 1726+). Posts com `publishState: processing` eterno = background/outbox não concluiu.

---

### Warmups excessivos (mesmo problema, outro módulo)

`FastMediaPublishBootstrap.warmForChatSend()` = `warmForFeedPublish()` = mesmo trabalho.

Chamado de:

- `optimistic_chat_media_upload` (cada mídia),
- `immediate_media_warm` (mural/património),
- `church_tenant_dashboard_warmup_service` (shell aberto — **pacote paralelo**),
- publicar aviso/evento.

`ChurchTenantDashboardWarmupService.scheduleAfterShellOpen` dispara em paralelo: panel snapshot, members directory, performance cache, offline warmup, gallery, media prefetch — **duplica** leituras que a Home já faria.

---

## 4. Verificação dos requisitos do prompt

### Chat

| Requisito | Estado |
|-----------|--------|
| Texto → Firestore imediato | **OK** (`InstantSend` → `begin`+`finalize`) |
| Imagem: stub `sending` → upload → `fileUrl` → `sent` | **OK** (`beginMediaUploadMessage` + `completeMediaUploadMessage`) |
| Sem fila infinita | **OK** com timeouts; risco = **jobs prefs irrecuperáveis** |
| Sem CF para aparecer | **OK** |

### Avisos / Eventos

| Requisito | Estado |
|-----------|--------|
| Firestore → UI → upload → push/feed | **OK** no caminho canónico |
| Nunca upload → Firestore no publish | **OK** (retry eventos corrigido) |

### Dashboard

| Requisito | Estado |
|-----------|--------|
| Fonte principal `church_tenant_dashboard_doc_service` | **Parcial** — existe; UI ainda usa `_panel_cache` + streams |
| Eliminar múltiplas contagens RT | **Não** — `igreja_dashboard_moderno.dart` |

### Consultas `.limit(20)`

| Área | Estado |
|------|--------|
| Feed público / `ChurchDataQuery` | OK |
| Membros lista cache | OK com `_panel_cache/members_directory` |
| Admin/PDF/alguns ecrãs | **Violam** (relatório anterior) |

### Logs pedidos (CHAT/AVISO/EVENTO/UPLOAD START/OK/ERROR)

| Estado |
|--------|
| **Parcial** — `YahwehFlowLog` / `ChurchPublishFlowLog` em publicação e chat; **não** uniforme em todos os serviços listados |

---

## 5. Serviços duplicados (resumo)

| Trabalho | Quem faz (redundante) | Manter como SOT |
|----------|----------------------|-----------------|
| Enviar texto chat | `InstantSend` vs `sendTextMessage` direto | **InstantSend** na thread; features igreja podem manter `sendTextMessage` |
| Progresso upload chat | `chat_uploads` + outbox prefs + bolha `OutboundPending` | Firestore mensagem + **opcional** só `chat_uploads` OU só outbox (não ambos obrigatórios) |
| Retoma upload | `ChurchChatMediaOutboxService` + `AppFinalizeBootstrap` + `StorageUploadPersistence` | Unificar política num único «resume» |
| Warm Storage | `FastMediaPublishBootstrap` × N chamadas + `ImmediateMediaWarm` | 1 warm por sessão/publicação |
| Cache painel | `dashboard/home` + `_panel_cache` + `_performance_cache` + streams membros | **`dashboard/home`** topo; `_panel_cache` detalhe; **sem** count RT |
| Publicação mural retoma | `MuralPublishOutbox` + `pending_uploads` (off) | Só outbox + fast publish |
| Feed site | `ChurchPublicFeedService` vs streams mural | Paginação CF/cache vs stream limitado |

**Não é duplicação (útil):**

- `ChurchChatMediaUploadCoordinator` — semáforo de rede
- `church_chat_local_conversations` — UX lista rápida
- `church_tenant_resilient_reads` — resiliência, não segunda gravação

---

## 6. Arquivos problemáticos (prioridade cirúrgica)

| Prioridade | Ficheiro | Problema |
|------------|----------|----------|
| P0 | `optimistic_chat_media_upload.dart` | Orquestra 5+ subsistemas; timeouts/retries complexos |
| P0 | `church_chat_media_outbox_service.dart` | Prefs + resume; fantasma «pendentes» |
| P0 | `igreja_dashboard_moderno.dart` | Streams RT + cache — ignora SOT dashboard doc |
| P1 | `church_tenant_dashboard_warmup_service.dart` | Warmup em massa ao abrir shell |
| P1 | `app_finalize_bootstrap.dart` | Resume **todas** as filas no resume (chat+mural+storage) |
| P1 | `church_chat_stuck_cleanup_service.dart` | Necessário mas sintoma de filas duplicadas |
| P2 | `church_chat_uploads_service.dart` | Docs órfãos se fluxo aborta |
| P2 | `mural_publish_outbox_service.dart` | Duplica retoma já feita por `MuralFastPublishService` |
| P2 | `pending_uploads_firestore_service.dart` | Código morto com política off — confunde auditoria |
| P2 | `church_chat_service.dart` | 25× `catch (_)` — falhas de envio invisíveis |

---

## 7. Gargalos eliminados (já no código — sessões anteriores)

1. Publicar aviso/evento: Firestore-first (`FeedMediaPublishFast`).
2. `drainInFlight` 40s → 2s no publish.
3. Retry eventos upload→set removido.
4. Patrimônio fotos: `PatrimonioPublishService` background.
5. `FirebaseUploadPolicy.firestorePendingQueueEnabled = false` — sem fila Firestore global activa.

**Nenhuma alteração de código nesta entrega** — só documentação.

---

## 8. Correções recomendadas (próxima onda — cirúrgicas)

### Chat (sem mudar UI)

1. **Uma fila de retoma:** manter `ChurchChatMediaOutboxService` **ou** `chat_uploads`, documentar o outro como espelho opcional.
2. `pruneUnrecoverableJobs` no arranque — já em `AppFinalizeBootstrap`; garantir que banner só conta jobs com bytes/path (`recoverablePendingJobCount` — já existe).
3. Logs únicos: `CHAT START` / `CHAT OK` / `CHAT ERROR` só em `ChurchChatService` + `OptimisticChatMediaUpload` (remover prints dispersos).
4. `warmForChatSend` — não chamar em **cada** mídia se `ImmediateMediaWarm`/`AppFinalizeBootstrap` já aqueceu na sessão.

### Dashboard (sem mudar layout)

1. Topo do painel: **só** `ChurchTenantDashboardDocService.readOnce` para números.
2. `_panel_cache`: avisos/eventos/aniversariantes — **sem** novo `snapshots()` de `membros` para contagem.
3. `ChurchTenantDashboardWarmupService`: reduzir lista paralela (não repetir o que `PanelDashboardSnapshotService.readOnce` já faz).

### Publicação

1. Manter SOT; `MuralPublishOutbox` só para recovery real (app killed).
2. Não reactivar `pending_uploads` Firestore sem migração.

---

## 9. Testes executados

| Teste | Resultado |
|-------|-----------|
| Leitura estática / grep dependências | **Sim** (esta auditoria) |
| `dart analyze` módulos publish 1728 | Sem errors (sessão anterior) |
| Teste manual chat/mural | **Não** nesta entrega |
| Stress 50k mensagens | **Não** |

---

## 10. Itens ainda pendentes

- Unificar filas de retoma chat (prefs vs `chat_uploads`).
- Dashboard: uma fonte de contagem + remover streams RT redundantes.
- Warmup: deduplicar chamadas `FastMediaPublishBootstrap`.
- Logs uniformes CHAT/AVISO/EVENTO/UPLOAD em todos os SOT.
- Remover ou isolar código `pending_uploads` quando política off.
- `catch (_)` nos SOT de envio/publicação (fase incremental).
- Teste E2E: enviar texto, imagem, publicar aviso 3 fotos, cold start resume.

---

## 11. Diagrama simplificado (alvo)

```
CHAT TEXTO:
  Thread UI → InstantSend → ChurchChatService → Firestore ✓

CHAT MÍDIA:
  Thread UI → OptimisticFlush → ChurchChatService (stub)
            → Storage
            → ChurchChatService (complete)
            → [opcional] chat_uploads done
            → [se app morreu] outbox prefs resume

AVISO/EVENTO:
  Editor → FeedMediaPublishFast → Firestore stub → fecha UI
         → MuralFastPublish → URLs → published → CF push

DASHBOARD (alvo):
  Home → ChurchTenantDashboardDocService (1 doc)
       → _panel_cache (detalhe, sem recount RT)
```

---

## 12. Conclusão

A avaliação do utilizador está **correcta**: o maior risco é **excesso de serviços** a resolver o mesmo problema. As funcionalidades existem; a estabilização passa por **escolher uma fonte de verdade por fluxo**, **uma fila de retoma**, e **menos warmups** — não por acrescentar mais uma camada.

**Próximo passo sugerido:** aprovar **onda Chat P0** (outbox + logs + warm dedupe) **ou** **onda Dashboard P0** (streams) — um módulo por PR.

---

*Relatório cirúrgico — sem alterações de código nesta entrega.*
