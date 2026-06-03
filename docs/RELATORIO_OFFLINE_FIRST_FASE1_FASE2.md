# Relatório — Offline-First (migração gradual) — Gestão YAHWEH Premium

**Data:** 2026-06-02  
**Política:** Corrigir bloqueadores **antes** de offline completo. **Sem** alterar layout, design, telas, navegação ou funcionalidades visíveis.

---

## Plano de fases

| Fase | Escopo | Estado |
|------|--------|--------|
| **0 — Bloqueadores** | `core/no-app`, `permission-denied`, deploy `firestore.rules` | Código OK; deploy regras pode depender da API Google (503) |
| **1 — Fundação** | Hive + `LocalRepository` + `RemoteRepository` + `SyncRepository` + `SyncEngine` | **Implementado** |
| **2 — Módulos** | Membros, eventos, avisos, patrimônio, financeiro, escalas → fila Hive por entidade | **Implementado** (`TenantOfflineWrite` + fachadas por módulo) |
| **3 — UI cache-first** | Todas as listas: cache → servidor | Parcial (`FirestoreReadResilience`, `_panel_cache`, `dashboard_stats`) |

---

## 1. Arquivos alterados (esta entrega)

| Ficheiro | Alteração |
|----------|-----------|
| `pubspec.yaml` | `hive`, `hive_flutter` |
| `lib/core/offline/sync_task.dart` | Modelo da fila |
| `lib/core/offline/local_repository.dart` | Interface local |
| `lib/core/offline/remote_repository.dart` | Interface remota |
| `lib/core/offline/hive_local_store.dart` | Hive (mobile); memória na web |
| `lib/core/offline/firebase_remote_repository.dart` | Handlers remotos por módulo/operação |
| `lib/core/offline/sync_repository.dart` | Local → tentativa remota |
| `lib/core/offline/sync_engine.dart` | Fila + retry + `flushAll` |
| `lib/core/offline/offline_bootstrap.dart` | Init + flushers (chat, mural, storage, bootstrap) |
| `lib/main.dart` | `OfflineBootstrap.init()` após Firebase |
| `lib/services/app_connectivity_service.dart` | `SyncEngine.flushAll` ao voltar online |
| `lib/core/yahweh_flow_log.dart` | `RETRY` |
| `lib/core/app_finalize_bootstrap.dart` | `catch (e, st)` + log |
| `docs/RELATORIO_ARQUITETURA_CONTROLE_TOTAL.md` | Relatório anterior |
| `.cursor/rules/filosofia-controle-total.mdc` | Regra permanente |

---

## 2. Serviços criados

- **`HiveLocalStore`** — fila persistente (`yahweh_sync_queue_v1`)
- **`SyncEngine`** — orquestra flush ao ficar online
- **`SyncRepository`** — padrão enqueue + sync
- **`FirebaseRemoteRepository`** — registo de handlers Firestore/Storage
- **`OfflineBootstrap`** — arranque e ligação às filas existentes

## 3. Serviços removidos

Nenhum. Migração **aditiva** — filas antigas (`ChurchChatMediaOutboxService`, `MuralPublishOutboxService`, `StorageUploadPersistenceService`, Firestore persistence) **mantidas**.

---

## 4. Índices Firestore

Já definidos em `firestore.indexes.json` (ex.: `chats` + `participantUids` + `lastMessageAt`, `messages` + `createdAt`, `avisos`/`eventos` + `createdAt`). Deploy via `.\scripts\deploy_firebase_rules.ps1`.

---

## 5. Regras ajustadas

- Paths canónicos do chat: **`igrejas/{tenantId}/chats/{threadId}`** (não `chat_threads` nas funções auxiliares).
- **Publicar em produção:** `.\scripts\deploy_firebase_rules.ps1` até `firestore:rules` OK.

---

## 6. Problemas corrigidos

| Problema | Solução |
|----------|---------|
| `core/no-app` | Um `Firebase.initializeApp`; `ensureFirebaseCore` |
| `permission-denied` chat | Regras `chats` + migração CF no hub |
| Sem motor de sync unificado | `SyncEngine` + rede → `flushAll` |
| `catch (e)` sem stack no bootstrap | `catch (e, st)` + `YahwehFlowLog.error` |

---

## 7. O que já funcionava offline (antes desta fase)

- **Mobile:** Firestore `persistenceEnabled: true` (cache ilimitado)
- **Chat texto:** `deliveryStatus: local` offline → Firestore sincroniza ao voltar rede
- **Chat mídia:** `ChurchChatOutboundPending` + outbox
- **Sessão:** `FirebaseAuth` + `Persistence.LOCAL` (web) + `PersistentAuthSessionService`
- **Retomar:** `AppResumeStateService` (shell, chat, membro, …)
- **Publicação:** patrimônio/mural/financeiro — Firestore primeiro, foto depois

---

## 8. Testes executados

| Teste | Resultado |
|-------|-----------|
| `flutter pub get` (hive) | OK |
| `dart analyze` — `lib/core/offline`, `main.dart`, `app_connectivity_service` | Sem `error` (executar após pull) |
| Deploy regras | Repetir até API 503 cessar |

**Testes manuais obrigatórios:**

1. Login → fechar app → reabrir **sem** login  
2. Modo avião → enviar mensagem chat → aparece → online → `sent`  
3. Publicar aviso com foto → lista atualiza antes do upload  
4. Chat após deploy regras → sem `permission-denied`

---

## 9. Pendências restantes

### P0
- Confirmar **deploy** `firestore.rules` em produção
- Validar migração `chat_threads` → `chats` na igreja de teste

### P1 (offline completo por módulo) — Fase 2 entregue
- `TenantOfflineWrite` — enfileira no Hive quando `!isOnline` (+ espelho Firestore cache no mobile)
- `OfflineFirestoreExecutor` — handlers `set` / `update` / `delete` / `batch_write` por módulo
- Fachadas: `MembrosOfflineSync`, `EventosOfflineSync`, `AvisosOfflineSync`, `PatrimonioOfflineSync`, `FinanceiroOfflineSync`, `EscalasOfflineSync`
- Integrado: `ChurchDataService`, `FinanceSmartBatchService`, `ImmediatePatrimonioPhotoAttach`
- Pendente incremental: gravações directas em `patrimonio_page.dart`, `members_page.dart`, `department_member_integration_service` (batches)

### P1 — feito nesta entrega (resume + performance)
- **Retomar onde parou:** eventos, avisos, patrimônio (`saveOpen*` + shell + `initialOpen*DocId`)
- **Warmup:** 1.º frame leve (24 membros / 20 avisos / 20 eventos); completo após 4 s
- **Chat mídia:** `runChatMediaUploadTask` em vez de `runFirebaseBackgroundTask` no caminho quente
- **Deploy regras:** repetir `.\scripts\deploy_firebase_rules.ps1` se API 503

### P2
- Web: IndexedDB opcional ou aceitar Firestore-only na web
- Substituir `catch (e) {}` global (incremental por pasta)
- Painel Master: só `master_dashboard_stats` no primeiro frame

---

## 10. Filosofia implementada

```
Ação do usuário
  → gravação local / Firestore cache (imediato)
  → sucesso na tela
  → SyncEngine / filas legadas (background)
  → confirmação servidor
```

**Comando deploy bloqueadores:**

```powershell
.\scripts\deploy_firebase_rules.ps1
.\scripts\deploy_web_hosting.ps1
```
