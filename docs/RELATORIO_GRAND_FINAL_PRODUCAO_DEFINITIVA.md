# GRAND FINAL — Gestão YAHWEH Produção Definitiva

**Data:** 2026-06-02  
**Missão:** Plataforma premium, estável, rápida, offline-first, pronta para produção real.  
**Restrição respeitada:** sem alteração de layout, design, cores, navegação ou funcionalidades visíveis — apenas corrigir, otimizar, simplificar e blindar.

---

## Resumo executivo

| Estado | Descrição |
|--------|-----------|
| **Arquitetura** | Fechada — evoluir serviços existentes (proibido V2 duplicado) |
| **Código** | Bootstrap único, offline Hive, SyncEngine, Publication Engine, resiliência, saúde ADM |
| **Gate deploy** | `scripts/verify_production_checklist.ps1` integrado ao deploy completo |
| **Bloqueador P0** | Deploy `firestore.rules` em produção — API Google **503** (intermitente) |
| **Próximo passo** | Validar checklist manual nos 3 ambientes → deploy real |

---

## Mapa das 22 fases

| Fase | Tema | Estado | Referência canónica |
|------|------|--------|---------------------|
| **0** | Bloqueadores no-app + permission-denied | **Código OK / deploy regras pendente** | `firebase_bootstrap.dart`, `firestore.rules` |
| **1** | Filosofia Controle Total | **Implementado** | `publication_engine.dart`, `TenantOfflineWrite` |
| **2** | Offline First (todos módulos) | **Parcial → incremental** | `lib/core/offline/*`, `offline_bootstrap.dart` |
| **3** | Sessão permanente | **Implementado** | `persistent_auth_session_service.dart`, `main.dart` |
| **4** | Retornar onde parou | **Parcial** | `app_resume_state_service.dart`, `igreja_clean_shell.dart` |
| **5** | Chat WhatsApp | **Implementado** | `church_chat_instant_send_service.dart`, outbox mídia |
| **6** | Avisos | **Implementado** | `publication_engine.dart`, `instagram_mural.dart` |
| **7** | Eventos | **Implementado** | `publication_engine.dart`, `events_manager_page.dart` |
| **8** | Membros | **Parcial** | `member_profile_photo_update_service.dart`, fila Hive |
| **9** | Patrimônio | **Parcial** | `patrimonio_publish_service.dart`, gravações directas restantes |
| **10** | Financeiro | **Parcial** | `finance_smart_batch_service.dart`, comprovante background |
| **11** | Dashboard agregado | **Implementado** | `church_tenant_dashboard_doc_service.dart` |
| **12** | Painel Master | **Implementado** | paginação + limites V4 |
| **13** | Cache stale-while-revalidate | **Parcial** | cache-first dashboard, warmup tenant |
| **14** | SyncEngine | **Implementado** | `sync_engine.dart`, `sync_priority.dart` |
| **15** | Modo degradação | **Implementado** | `service_degradation_registry.dart` |
| **16** | Auditoria | **Implementado** | `tenant_audit_service.dart` |
| **17** | Lixeira 30 dias | **Implementado** | `smart_trash_service.dart` |
| **18** | Monitoramento | **Implementado** | Crashlytics/Analytics/Performance + traces |
| **19** | Backup diário | **Backend OK** | CF `backupDailyToGcs`, `backupDailyToDrive` |
| **20** | Performance | **Parcial** | `yahweh_performance_v4.dart`, `.limit(20/30/50)` |
| **21** | Imagens/vídeos | **Implementado** | WebP 80%, 1200px, `video_compress` |
| **22** | Regra mestra | **Implementado** | `.cursor/rules/regra-mestra-projeto.mdc` |

---

## 1. Arquivos alterados (consolidado)

### Core Firebase / bootstrap
- `flutter_app/lib/main.dart`
- `flutter_app/lib/core/firebase/firebase_bootstrap.dart`
- `flutter_app/lib/core/firebase_bootstrap.dart`
- `flutter_app/lib/core/firebase_bootstrap_service.dart`
- `flutter_app/lib/core/firebase_publish_guard.dart`
- `flutter_app/lib/core/app_finalize_bootstrap.dart`

### Offline + sync (Fase 2 / 14)
- `flutter_app/lib/core/offline/offline_bootstrap.dart`
- `flutter_app/lib/core/offline/sync_engine.dart`
- `flutter_app/lib/core/offline/sync_priority.dart`
- `flutter_app/lib/core/offline/hive_local_store.dart`
- `flutter_app/lib/core/offline/tenant_offline_write.dart`
- `flutter_app/lib/core/offline/offline_firestore_executor.dart`
- `flutter_app/lib/core/offline/offline_modules.dart`

### Resiliência + produção (Fases 15–19)
- `flutter_app/lib/core/resilience/service_degradation_registry.dart`
- `flutter_app/lib/core/resilience/emergency_mode_service.dart`
- `flutter_app/lib/services/system_health_service.dart`
- `flutter_app/lib/services/admin_diagnostic_service.dart`
- `flutter_app/lib/services/tenant_audit_service.dart`
- `flutter_app/lib/services/smart_trash_service.dart`
- `flutter_app/lib/services/internal_notification_inbox_service.dart`
- `flutter_app/lib/ui/pages/system_firebase_health_page.dart`

### Publicação Controle Total (Fases 6–10)
- `flutter_app/lib/services/publication_engine.dart`
- `flutter_app/lib/services/feed_media_publish_service.dart`
- `flutter_app/lib/services/mural_fast_publish_service.dart`
- `flutter_app/lib/services/patrimonio_publish_service.dart`
- `flutter_app/lib/services/finance_comprovante_publish_service.dart`

### Chat (Fase 5)
- `flutter_app/lib/ui/pages/church_chat_hub_page.dart`
- `flutter_app/lib/ui/pages/church_chat_thread_page.dart`
- `flutter_app/lib/services/church_chat_instant_send_service.dart`
- `flutter_app/lib/services/church_chat_service.dart`

### Sessão + resume (Fases 3–4)
- `flutter_app/lib/services/persistent_auth_session_service.dart`
- `flutter_app/lib/services/app_resume_state_service.dart`
- `flutter_app/lib/ui/igreja_clean_shell.dart`

### Regras + deploy
- `firestore.rules` (paths `chats`, helpers `canReadChatThreadDoc`)
- `firestore.indexes.json`
- `scripts/verify_production_checklist.ps1`
- `scripts/deploy_completo.ps1` (gate produção)

### Documentação
- `docs/CHECKLIST_PRODUCAO.md`
- `docs/ARQUITETURA_RESILIENCIA.md`
- `docs/RELATORIO_ARQUITETURA_CONTROLE_TOTAL.md`
- `.cursor/rules/checklist-producao.mdc`
- `.cursor/rules/arquitetura-resiliencia-producao.mdc`
- `.cursor/rules/regra-mestra-projeto.mdc`

**Total aproximado na branch:** ~56 ficheiros tocados, +1700 / −800 linhas (sem contar docs novos).

---

## 2. Problemas encontrados

### P0 — Bloqueadores

| # | Problema | Impacto |
|---|----------|---------|
| 1 | **`core/no-app`** — race entre resume, uploads e segundo touch em Firestore | Publicação/chat falha intermitente |
| 2 | **`permission-denied` chat** — regras liam `chat_threads` em vez de `chats` | Mensagens/typing negados |
| 3 | **Deploy regras Firestore** — API `firebaserules.googleapis.com` **HTTP 503** | Correção no repo **não** reflete em produção até deploy |
| 4 | **Dados legados** — threads ainda em `chat_threads` | Lista vazia após correção de regras |

### P1 — Estabilidade / UX

| # | Problema |
|---|----------|
| 5 | Gravações directas em `patrimonio_page.dart`, `members_page.dart` (fora de `TenantOfflineWrite`) |
| 6 | Resume incompleto: `saveOpenEvent` / `saveOpenAviso` / `saveOpenPatrimonio` nem sempre ligados |
| 7 | Warmup tenant pesado no 1.º frame |
| 8 | Listeners duplicados em algumas páginas legacy |
| 9 | `catch (e) {}` silenciosos espalhados (módulos antigos) |

### P2 — Performance

| # | Problema |
|---|----------|
| 10 | Algumas queries ainda sem `.limit()` ou paginação |
| 11 | Eventos: carregar só mês visível — parcial |

---

## 3. Problemas corrigidos

| # | Correção |
|---|----------|
| 1 | **Um** `Firebase.initializeApp` — `FirebaseBootstrap.ensureInitialized()` + `ensureFirebaseCore()` |
| 2 | Guards: `ensureFirebaseReadyForPublishUpload`, `ForChatSend`, `ForPanelRead` |
| 3 | `FirebaseBootstrapService.runGuarded` — reconnect automático em no-app |
| 4 | Regras: `canReadChatThreadDoc`, `match /chats/{threadId}` (path correcto) |
| 5 | Migração CF + warmup: `chat_threads` → `chats` |
| 6 | Chat: envio texto instantâneo; mídia optimistic + outbox |
| 7 | Publication Engine: Firestore → UI → distribuição background |
| 8 | SyncEngine + Hive + prioridade (Login→Chat→…→Vídeos) |
| 9 | Degradação: Storage/Push/Site público falham sem derrubar app |
| 10 | Auditoria + lixeira 30d nos módulos críticos |
| 11 | Central Saúde ADM + gate `verify_production_checklist.ps1` |
| 12 | Dashboard: `dashboard_stats` / agregados (sem contagens live) |
| 13 | Limites V4: chat 30 msg, threads 50, membros/património 20 |
| 14 | Resume: shell, chat, membro; hub reabre última conversa |
| 15 | Grupos chat: sync timeout + permissões `chatHubSeesAllDepartmentGroups` |

---

## 4. Índices Firestore (`firestore.indexes.json`)

Principais (já definidos; deploy via `deploy_firebase_rules.ps1`):

| Coleção / grupo | Campos | Uso |
|-----------------|--------|-----|
| `chats` | `participantUids` + `lastMessageAt` DESC | Lista conversas |
| `messages` (group) | `createdAt` DESC | Histórico chat |
| `avisos` | `publishState` + `createdAt`; `publicSite` + `createdAt` | Mural / site |
| `eventos` | `type` + `startAt` / `createdAt` | Agenda / mural |
| `membros` | `STATUS`+`FUNCAO`, departamentos, aniversário | Lista membros |
| `chat_uploads` | `ownerUid` + `status` | Uploads chat |

**Estado deploy índices:** tentativa em 2026-06-02 — **503** na API de rules (mesmo script re-tenta).

---

## 5. Regras ajustadas

### Firestore (`firestore.rules`)
- Path canónico: `igrejas/{tenantId}/chats/{threadId}`
- Funções: `canReadChatThreadDoc`, `canReadChatThreadData`, `chatSenderMayPostToThread`
- Subcoleções: `messages`, `typing`, `chat_presence`
- Fallback gestor por e-mail (`sameChurch`) — evita permission-denied em presença/eventos

### Storage (`storage.rules`)
- Sem alteração estrutural nesta missão
- Deploy Storage: **OK** (2026-06-02)

### Publicação em produção (obrigatório P0)

```powershell
.\scripts\deploy_firebase_rules.ps1
```

Repetir até sucesso (script: 10–15 tentativas, backoff 8s→180s).  
Se 503 persistir: [Google Cloud Status](https://status.cloud.google.com/) ou Console Firebase → Firestore → Rules (upload manual).

---

## 6. Serviços simplificados (sem duplicar)

| Antes (espalhado) | Agora (canónico) |
|-------------------|------------------|
| Vários publish paths mural/eventos | **`PublicationEngine`** |
| Filas ad hoc offline | **`TenantOfflineWrite`** + **`SyncEngine`** |
| Health espalhado | **`SystemHealthService`** + **`AdminDiagnosticService`** |
| Audit só financeiro | **`TenantAuditService`** (+ `finance_logs` legado) |
| Delete hard | **`SmartTrashService`** (módulos auditados) |
| Erros só print | **`YahwehCatchLog`** → Crashlytics + **`SystemLastErrorRegistry`** |

**Proibido por regra mestra:** RepositoryV2, SyncV2, ChatV2, novos serviços paralelos.

---

## 7. Testes executados

| Teste | Resultado |
|-------|-----------|
| `.\scripts\verify_production_checklist.ps1` | **OK** (gate estático + dart analyze produção) |
| `dart analyze` — bootstrap, sync, publication, health | **0 errors** |
| `dart analyze` — chat hub/thread | **0 errors** (warnings herdados) |
| Deploy Storage rules | **OK** |
| Deploy Firestore rules + índices | **FALHA 503** (API Google indisponível) |
| Testes manuais dispositivo (checklist 18 itens) | **Pendente operador** |

### Checklist obrigatório manual (antes de produção real)

```
✓ Login          → testar arranque com sessão salva
✓ Biometria      → local_auth + preferências
✓ Offline        → modo avião + gravar aviso/membro
✓ Sync           → voltar online → fila Hive esvazia
✓ Chat           → texto + foto + vídeo + PDF
✓ Avisos         → publicar com mídia
✓ Eventos        → idem
✓ Membros        → cadastro + foto
✓ Patrimônio     → item + foto
✓ Financeiro     → lançamento + comprovante
✓ Cartões/Cartas → abrir sem erro
✓ Site Público   → feed público
✓ Dashboard      → stats agregados (não live count)
✓ Painel Master  → Saúde → Central = LIBERADO
✓ Uploads        → filas < 15 jobs
```

Painel: **Menu Master → Saúde do Sistema → Central / Diagnóstico**

---

## 8. Pendências restantes (prioridade)

### P0 — Antes de qualquer feature

1. **Deploy `firestore.rules`** quando API responder (`deploy_firebase_rules.ps1`)
2. **Validar migração** `chat_threads` → `chats` na igreja piloto
3. **Checklist manual** 18 itens Android + iOS + Web

### P1 — Estabilização incremental (sem layout novo)

4. Migrar gravações directas restantes para `TenantOfflineWrite` (património, membros, departamentos)
5. Ligar `AppResumeStateService.saveOpenEvent/Aviso/Patrimonio` nas telas de detalhe
6. Alimentar `InternalNotificationInboxService.deliver()` nos publishes (avisos/eventos/chat)
7. Purga lixeira expirada — CF scheduled (opcional; cliente já tem `purgeExpired`)

### P2 — Performance / polish

8. Warmup tenant «light» no 1.º frame
9. Varredura `catch {}` → `YahwehCatchLog` por módulo
10. Eventos: query só mês visível; financeiro: resumo antes de lista completa

### P3 — Operação

11. Confirmar bucket GCS backup (`gcs.backup_bucket`) no Firebase Console
12. Após checklist OK: `.\scripts\deploy_completo.ps1` (gate automático)

---

## Comandos úteis

```powershell
# P0 — regras + índices
.\scripts\deploy_firebase_rules.ps1

# Gate produção (local)
.\scripts\verify_production_checklist.ps1

# Deploy completo (após P0 + checklist manual)
.\scripts\deploy_completo.ps1

# Análise
cd flutter_app; dart analyze --no-fatal-warnings
```

**Web após deploy:** https://gestaoyahweh-21e23.web.app (Ctrl+F5)

---

## Conclusão

O **pacote de arquitetura e estabilidade está definido e implementado no código**. O Gestão YAHWEH possui:

- Offline-first com fila Hive e SyncEngine prioritário  
- Publicação estilo Controle Total (Firestore → UI → background)  
- Sessão permanente + resume parcial  
- Chat WhatsApp (texto instantâneo + mídia optimistic)  
- Degradação, auditoria, lixeira, monitoramento, backup CF  
- Gate de produção e painel diagnóstico ADM  

**O único bloqueador externo confirmado hoje é o deploy das regras Firestore (503 Google).**  
Depois de P0 + validação manual, o foco deve ser **confiabilidade em produção real**, não novas camadas de complexidade.

---

*Documento gerado como fecho da missão GRAND FINAL — Gestão YAHWEH Produção Definitiva.*
