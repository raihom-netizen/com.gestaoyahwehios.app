# Padronização de performance — Gestão YAHWEH = Controle Total

## Pré-requisitos (bloqueantes)

Antes de medir velocidade, garantir:

1. **`core/no-app`** — um único `Firebase.initializeApp` + `ensureFirebaseCore()`
2. **`permission-denied`** — regras chat em `igrejas/{id}/chats/...` (deploy `firestore.rules`)

## Metas de tempo (alvo)

| Área | Meta |
|------|------|
| Home / Painel Master | < 1 s |
| Membros / Eventos / Avisos | < 1 s |
| Chat (texto) | instantâneo |
| Patrimônio / Financeiro | < 2 s |
| Relatórios | < 3 s |

## Dashboard agregado

| Documento | Caminho |
|-----------|---------|
| Igreja | `igrejas/{id}/dashboard_stats/summary` |
| Alias CT | `igrejas/{id}/church_dashboard_stats/summary` |
| Master | `config/master_dashboard_summary` |

**Proibido:** `count()` / `.get()` sem limite em coleções grandes para KPIs.

Serviço: `ChurchTenantDashboardDocService` (cache → servidor).

## Limites canónicos (`YahwehPerformanceV4`)

| Constante | Valor |
|-----------|-------|
| `defaultPageSize` | 20 |
| `chatMessagesPageSize` | 30 |
| `chatThreadsListLimit` | 50 |
| `masterChurchesPageSize` | 25 |
| `patrimonioListPageSize` | 20 |
| `webpQuality` | 80 |
| `uploadMaxEdgePx` | 1200 |

## Módulos

- **Membros:** `_membersLoadLimit = 20`, paginação infinita
- **Avisos:** feed 20 + `FeedMediaPublishFast`
- **Eventos:** mês visível (não histórico completo na abertura)
- **Chat:** 30 mensagens + histórico sob demanda
- **Patrimônio:** lista `orderBy('nome').limit(20)`
- **Painel Master:** resumo `MasterDashboardCacheService` + igrejas `limit(25)`
- **Financeiro:** resumo primeiro (`FinanceComprovantePublishService`)

## Publicação (5 passos)

Firestore → sucesso UI → Storage → URL → fim.

Sem fila Firestore `pending_uploads` (`firestorePendingQueueEnabled = false`).

## Cache

Cache local / Firestore cache primeiro, servidor depois (`dashboard_stats`, `master_dashboard_summary`).

## Logs

`YahwehFlowLog`: `MODULO START` | `SUCCESS` | `ERROR`.

## Índices

Ver `firestore.indexes.json` — `avisos`, `eventos`, `messages`, `chats` com `createdAt` / `participantUids`.

## Deploy

```powershell
.\scripts\deploy_firebase_rules.ps1
.\scripts\deploy_web_hosting.ps1
```
