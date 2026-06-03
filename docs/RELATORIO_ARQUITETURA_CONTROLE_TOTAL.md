# Relatório — Arquitetura Controle Total (Gestão YAHWEH Premium)

**Data:** 2026-06-02  
**Missão:** Estabilidade, velocidade e simplicidade (offline-first) **sem** alterar layout, design, cores, navegação ou funcionalidades visíveis.

---

## 1. Arquivos alterados (sessão atual + base já no repositório)

| Área | Arquivos principais |
|------|---------------------|
| Firebase bootstrap | `lib/core/firebase/firebase_bootstrap.dart`, `lib/core/firebase_bootstrap.dart`, `lib/core/firebase_bootstrap_service.dart`, `lib/main.dart` |
| Regras chat | `firestore.rules` (paths `chats`) |
| Chat performance | `lib/ui/pages/church_chat_thread_page.dart`, `lib/ui/pages/church_chat_hub_page.dart` |
| Chat envio | `lib/services/church_chat_instant_send_service.dart`, `lib/services/church_chat_service.dart` |
| Publicação CT | `lib/services/feed_publish_preflight.dart`, `mural_fast_publish_service.dart`, `patrimonio_publish_service.dart`, `finance_comprovante_publish_service.dart`, `member_profile_photo_update_service.dart` |
| Offline / resume | `lib/services/app_resume_state_service.dart`, `lib/ui/igreja_clean_shell.dart`, `lib/services/app_connectivity_service.dart` |
| Dashboard agregado | `lib/services/church_tenant_dashboard_doc_service.dart` |
| Performance limits | `lib/core/yahweh_performance_v4.dart`, `members_page.dart`, `patrimonio_page.dart`, `admin_panel_page.dart` |
| Logs | `lib/core/yahweh_flow_log.dart`, `lib/core/yahweh_catch_log.dart` |
| Migração coleções | `lib/services/church_firestore_collection_migration_service.dart` |
| Cursor / docs | `.cursor/rules/filosofia-controle-total.mdc`, `docs/RELATORIO_ERRO_FIREBASE_CHAT.md`, `docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md` |

---

## 2. Problemas encontrados

### Bloqueadores

1. **`core/no-app`** — Múltiplos caminhos tocavam Firestore/Auth sem garantir `[DEFAULT]`; health check e uploads em race após resume.
2. **`permission-denied` (chat)** — Funções em `firestore.rules` liam `chat_threads/{id}` enquanto o app usa `chats/{id}` → `exists()` falso → negação em mensagens/typing.
3. **Dados legados** — Threads ainda em `chat_threads` sem migração → lista vazia ou leitura negada após correção das regras.

### Performance / UX

4. Streams de chat recriados no `build` → re-subscribe e jank ao teclado.
5. `setState` / `ListenableBuilder` a cada tecla na pesquisa (hub, thread).
6. Warmup pesado no arranque (`ChurchTenantOfflineWarmupService` com muitas coleções).
7. «Retornar onde parou» incompleto (chaves de evento/aviso sem API; chat/membro pouco ligados ao shell).

### Arquitetura

8. Pilha longa: sessão → cache → warmup → fila → publish guard → Firestore (Controle Total usa 3 camadas).

---

## 3. Problemas corrigidos

| # | Correção |
|---|----------|
| 1 | **Um** `Firebase.initializeApp` em `FirebaseBootstrap.ensureInitialized()`; `ensureFirebaseCore()` para publish/chat/panel. |
| 2 | Regras: `canReadChatThreadDoc`, `chatSenderMayPostToThread`, etc. apontam para `igrejas/{tenantId}/chats/{threadId}`. |
| 3 | Migração CF `migrateTenantFirestoreCollections` no warmup + ao abrir hub do chat. |
| 4 | `_messagesStream` / `_threadStream` estáveis em `initState`; debounce 500 ms em pesquisas; `RepaintBoundary` no composer/lista. |
| 5 | Hub: `ValueNotifier` + debounce nas listas de conversas e grupos. |
| 6 | Publicação texto chat: Firestore direto (`writeTextMessageFirestoreOnce`); patrimônio/financeiro/mural: Firestore → UI → Storage background. |
| 7 | `AppResumeStateService`: shell, rota, chat, membro, patrimônio, evento, aviso; shell restaura aba + membro; hub reabre última conversa. |
| 8 | Dashboard: leitura `dashboard_stats/summary` e `church_dashboard_stats/summary` cache-first. |
| 9 | Limites V4: mensagens 30, threads 50/30, membros 20, patrimônio 20, master igrejas 25. |

---

## 4. Índices Firestore (já em `firestore.indexes.json`)

| Uso | Índice |
|-----|--------|
| Chat lista | `chats`: `participantUids` (CONTAINS) + `lastMessageAt` DESC |
| Mensagens | `messages`: `createdAt` DESC (várias variantes collection group) |
| Avisos | `avisos`: `publishState` + `createdAt`; `publicSite` + `createdAt` |
| Eventos | `eventos`: `type` + `startAt` / `createdAt` |
| Membros | `membros`: `STATUS`+`FUNCAO`, `departamentosIds`, aniversário |
| Uploads chat | `chat_uploads`: `ownerUid` + `status` |

**Deploy índices:** incluído em `.\scripts\deploy_firebase_rules.ps1` (última execução: índices OK).

---

## 5. Regras ajustadas

- **Firestore:** `match /chats/{threadId}` + subcoleções `messages`, `typing`; funções auxiliares com path `chats` (não `chat_threads`).
- **Storage:** sem alteração estrutural nesta missão; uploads seguem paths `church_storage_layout`.

**Publicação em produção:** executar quando a API Google responder (503 transitório):

```powershell
.\scripts\deploy_firebase_rules.ps1
```

---

## 6. Testes realizados

| Teste | Resultado |
|-------|-----------|
| `dart analyze` — `church_chat_thread_page.dart` | Sem `error` |
| `dart analyze` — `church_chat_hub_page.dart`, `church_chat_notification_settings_page.dart` | Sem `error` |
| Compilação regras local (`firebase deploy` dry) | `firestore.rules` compila |
| Deploy Storage + índices | OK |
| Deploy `firestore:rules` upload | **Pendente** (HTTP 503 API `firebaserules.googleapis.com` — script re-tenta) |

**Testes manuais recomendados (dispositivo):**

1. Arranque com sessão salva → painel sem login repetido.  
2. Chat → DM → mensagens → enviar texto offline/online.  
3. Publicar aviso com foto → aparece na lista antes do upload terminar.  
4. Fechar app na conversa → reabrir → volta à conversa (hub).  
5. Fechar no detalhe de membro → reabrir → aba Membros + ficha (shell).

---

## 7. Pendências

| Prioridade | Item |
|------------|------|
| **P0** | Confirmar deploy **`firestore.rules`** em produção (503). |
| **P0** | Validar migração `chat_threads`→`chats` na igreja de teste (CF + console). |
| **P1** | Ligar `saveOpenEvent` / `saveOpenAviso` nas telas de edição (eventos/avisos). |
| **P1** | Ligar `saveOpenPatrimonio` ao abrir item. |
| **P2** | Reduzir warmup inicial (modo «light» por defeito no 1.º frame). |
| **P2** | Substituir `runFirebaseBackgroundTask` restante no chat mídia por `ensureFirebaseCore` + task direta. |
| **P2** | Varredura `catch (e) {}` vazios → `YahwehCatchLog` (milhares de ocorrências — fazer por módulo). |
| **P3** | Eventos: query só mês visível; financeiro: resumo antes de lançamentos. |
| **P3** | Índices adicionais se surgirem erros de query no console (`churchId`+`status`+`createdAt` em novas coleções). |

---

## 8. Padrão alvo (referência)

```
PASSO 1 — Firestore (ou stub local offline)
PASSO 2 — Sucesso na UI
PASSO 3 — Upload Storage (background)
PASSO 4 — merge URL / status
PASSO 5 — SYNC (rede)
```

**Princípio:** O utilizador não deve notar diferença entre online e offline; a sensação de velocidade vem de **gravação local imediata + sincronização automática**, não só de otimizar rede.

---

## 9. Comandos úteis

```powershell
# Regras + índices
.\scripts\deploy_firebase_rules.ps1

# Web
.\scripts\deploy_web_hosting.ps1

# Análise
cd flutter_app
dart analyze --no-fatal-warnings lib/core/firebase_bootstrap.dart lib/services/app_resume_state_service.dart
```

**Web:** https://gestaoyahweh-21e23.web.app (Ctrl+F5 após deploy)

**Console:** https://console.firebase.google.com/project/gestaoyahweh-21e23/overview
