# Relatório — Erros `core/no-app` e `permission-denied` (Chat / Avisos)

Data: 2026-06-01  
Prioridade: bloqueio de produção (não é performance).

---

## ERRO 2 — Chat `permission-denied`

### 1. Caminho acessado pelo app

| Operação | Caminho Firestore |
|----------|-------------------|
| Lista de conversas | `igrejas/{churchId}/chats` — query `where participantUids arrayContains {uid}` + `orderBy lastMessageAt` |
| Thread | `igrejas/{churchId}/chats/{threadId}` |
| Mensagens | `igrejas/{churchId}/chats/{threadId}/messages/{messageId}` |
| Typing | `igrejas/{churchId}/chats/{threadId}/typing/{uid}` |
| Prefs | `igrejas/{churchId}/chat_member_prefs/{uid}` |

Código: `church_chat_service.dart` → `threadRef`, `chatThreadsQueryForUser`, `messagesCol`.

### 2. Regra que bloqueava

As funções auxiliares em `firestore.rules` apontavam para a coleção **legada**:

```
igrejas/{tenantId}/chat_threads/{threadId}
```

O app migrou para **`chats`** (`ChurchChatFirestoreMap.conversationsCollection`).

Funções afetadas:

- `canReadChatThreadDoc` — usada em **read** de `messages` e `typing`
- `chatSenderMayPostToThread` — usada em **create** de mensagens
- `chatMessageDeleteForEveryoneAllowed`
- `chatThreadDeleteAllowed`

Com o thread em `chats/{id}`, `exists(path)` em `chat_threads/{id}` era **sempre falso** → `permission-denied` em mensagens/envio, mesmo com lista de threads às vezes legível via `match /chats/{threadId}` direto.

### 3. UID logado

Deve aparecer no debug console após a correção de logs:

```
CHAT PATH=igrejas/{churchId}/chats?...
UID={firebaseAuth.uid}
```

Sem login: regras falham em `request.auth == null`.

### 4. Church ID

`tenantId` / `churchId` do painel — resolver via `TenantResolverService` / sessão da igreja (não confundir com slug do subdomínio).

### 5. Solução exata

**Alterar** os quatro `let path` de `chat_threads` para `chats` nas funções acima (feito neste commit).

**Publicar regras:**

```powershell
.\scripts\deploy_firebase_rules.ps1
```

**Validar:** abrir chat → lista carrega → abrir DM → mensagens aparecem → enviar texto.

---

## ERRO 1 — Avisos `Firebase não inicializou (core/no-app)`

### Causa provável

1. Acesso a `firebaseDefaultFirestore` / `auth` / `storage` quando `Firebase.apps` está vazio (reconexão, `restart()`, race após `Firebase.app().delete()`).
2. `healthCheck` chamava `FirebaseFirestore.instance.enableNetwork()` no singleton global em vez de `instanceFor(app: defaultApp)` — corrigido.
3. `main.dart` chama `FirebaseBootstrap.ensureInitialized()` e depois `FirebaseBootstrapService.initialize()` (dupla init é tratada com `duplicate-app`, mas logs ajudam a auditar).

### Correções aplicadas

- Logs: `FIREBASE INIT START` / `FIREBASE INIT OK` / `FIREBASE APPS=N` em `firebase_bootstrap.dart` e `firebase_bootstrap_service.dart`.
- Guard `_assertFirebaseAppAvailable()` nos getters `defaultApp`, `firestore`, `auth`, `storage` — mensagem clara em vez de crash opaco `core/no-app`.
- Preflight avisos: log `FIREBASE APPS` + `ERROR` em falha de `ensureFirebaseReadyForPublishUpload`.

### Se persistir após deploy

1. Ver no console se `FIREBASE APPS=0` no momento do erro.
2. Toque em «Reconectar» (`FirebaseBootstrapRecoveryPage`) ou reinicie o app.
3. Confirmar que não há código novo a usar `FirebaseFirestore.instance` antes do `main` (grep no projeto).

---

## Ordem de deploy recomendada

1. `.\scripts\deploy_firebase_rules.ps1` — **obrigatório** para o chat.
2. `.\scripts\deploy_web_hosting.ps1` — guards + logs no cliente web.
3. Nova build mobile quando for publicar na loja.

---

## O que NÃO foi alterado (pedido do utilizador)

- Cache, design, otimizações de performance, fluxos de negócio do chat além dos logs de diagnóstico.
