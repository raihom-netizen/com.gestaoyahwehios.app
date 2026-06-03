# Refactor produção — Gestão YAHWEH = padrão Controle Total

## Objetivo

Menos serviços, filas, coordenadores e cache complexo.  
Mais: **Firestore directo**, **Storage directo**, **UI simples**, **logs START / SUCCESS / ERROR**.

## Regra principal

Nenhum módulo crítico depende de `queue`, `pending`, `outbox`, `sync coordinator`, `publish coordinator`, `publish guard` ou **warmup obrigatório** para funcionar.

Exceção aceite: fila **disco** mobile (retry offline de ficheiros), como no CT — sem espelho Firestore `pending_uploads`.

## Padrão único (5 passos)

1. Firestore salva (stub ou dados finais)
2. Tela recebe sucesso
3. Storage envia ficheiro(s) em background
4. `update` com URL(s)
5. Fim

## Firebase (uma inicialização)

- `main.dart` → `FirebaseBootstrap.ensureInitialized()` = único `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
- Publicar → `ensureFirebaseCore(requireAuth: true)` (init + JWT, sem reconnect)
- Regras chat: paths em `igrejas/{id}/chats/{threadId}` (não `chat_threads`)

## Módulos

| Módulo | Firestore | Storage | Serviço canónico |
|--------|-----------|---------|------------------|
| Membros | `igrejas/{id}/membros/{memberId}` | `…/membros/{id}/profile*.webp` | `MemberProfilePhotoUpdateService` |
| Avisos | `…/avisos/{id}` | `…/avisos/{id}/…` | `FeedMediaPublishFast` + `MuralFastPublishService` |
| Eventos | `…/noticias/{id}` | `…/eventos/{id}/…` | idem |
| Patrimônio | `…/patrimonio/{id}` | slots por item | `PatrimonioPublishService` |
| Financeiro | `…/financeiro/…` | `…/comprovantes/{id}.jpg` | `FinanceComprovantePublishService` |
| Chat texto | `…/chats/{t}/messages/{m}` | — | `writeTextMessageFirestoreOnce` |
| Chat mídia | stub `sending` | `chat_media/…` | `optimistic_chat_media_upload` |
| Cartão / Cartas | metadados Firestore | PDF local | fluxos existentes |
| Agenda | `…/agenda/…` | anexos se houver | páginas + `YahwehFlowLog.agenda*` |
| Relatórios | leitura agregada | — | `dashboard_stats` |

## Chat

**Texto:** uma gravação, `status: sent`, sem fila, sem CF.

```json
{ "text", "senderUid", "senderName", "createdAt", "deliveryStatus": "sent" }
```

**Foto / vídeo / PDF:** criar mensagem `sending` → upload → `fileUrl` → `sent`.

## Consultas

- Proibido `collection.get()` sem `.limit()` em listas.
- Padrão: `.limit(20)` + paginação (`YahwehPerformanceV4.defaultPageSize`).

## Dashboard

- Usar `dashboard_stats` (documento agregado).
- Proibido contagens em tempo real sobre coleções grandes.

## Logs

`YahwehFlowLog` / `YahwehCatchLog`:

- `MODULO START`
- `MODULO SUCCESS` ou fases `FIRESTORE OK` / `UPLOAD OK`
- `MODULO ERROR` + stack

## Tratamento de erro

Proibido `catch (e) {}`.  
Obrigatório: `catch (e, st) { log; rethrow; }` ou log + estado `error` no documento.

## Prioridade de estabilização

1. `core/no-app` — bootstrap único
2. `permission-denied` — regras `chats` + deploy
3. Simplificar fluxos (este documento)
4. Consultas + dashboard
5. Uploads / mídia finos

## Deploy

```powershell
.\scripts\deploy_firebase_rules.ps1
.\scripts\deploy_web_hosting.ps1
```

Web: https://gestaoyahweh-21e23.web.app (Ctrl+F5).
