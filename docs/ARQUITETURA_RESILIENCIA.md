# Arquitetura de Resiliencia — Gestao YAHWEH

Infraestrutura de producao (sem novos modulos de negocio).

## 1. Modo degradacao automatica

`ServiceDegradationRegistry` — `lib/core/resilience/service_degradation_registry.dart`

Storage, Push, Site publico, Functions podem falhar **sem derrubar** Firestore/Chat/Avisos.

## 2. Fila inteligente de sync

`SyncPriority` — `lib/core/offline/sync_priority.dart`

Ordem: Login → Chat → Avisos → Eventos → Financeiro → Patrimonio → Fotos → Videos.

Aplicada em `HiveLocalStore.listTasks` e ordem dos flushers em `SyncEngine`.

## 3. Auditoria completa

`TenantAuditService` — `igrejas/{tenant}/auditoria_tenant`

Modulos: financeiro, patrimonio, membros, escalas. Campos: acao, uid, email, dispositivo, criadoEm.

Integrado em `TenantOfflineWrite` e `logFinanceiroAuditoria`.

## 4. Lixeira inteligente

`SmartTrashService` — move para `igrejas/{tenant}/lixeira`, retencao 30 dias.

Modulos auditados usam soft delete via `TenantOfflineWrite.deleteDocument`.

## 5. Modo emergencia

`EmergencyModeService` — offline ou Firestore indisponivel; trabalho local + sync depois.

## 6. Centro de notificacoes

`InternalNotificationInboxService` — `usuarios/{uid}/caixa_entrada`

Merge na pagina `NotificationsPage` (tenant + caixa pessoal).

## 7. Painel diagnostico ADM

Menu Master → Saude do Sistema → abas **Central** e **Diagnostico**

`AdminDiagnosticService`: sync/upload pendentes, presenca chat, backup, ultimo erro, degradacao.

## Prioridade final (nao negociavel)

1. core/no-app
2. permission-denied
3. Chat / Avisos / Eventos
4. Offline First + Sync
5. Monitoramento + Backup
6. Producao real

Sem novos modulos ate estabilizar Android, iOS e Web.

## 8. Zero carregamento + Hive local

| Componente | Ficheiro |
|------------|----------|
| Banco Hive por modulo | `lib/core/cache/tenant_module_hive_cache.dart` |
| Stale-while-revalidate | `lib/core/cache/tenant_stale_while_revalidate.dart` |
| Preload pos-dashboard | `lib/services/tenant_intelligent_preload.dart` |
| Upload resumivel (video) | `lib/services/resumable_upload_service.dart` |

Fluxo: **Abre tela → Hive instantaneo → rede em background**.

Integrado em `ChurchTenantResilientReads` (membros, avisos, eventos, patrimonio, financeiro, agenda).

## 9. Diagnóstico encerrado — 3 pilares finais

### 9.1 Modo «Nunca Perder Dados»

| Peça | Ficheiro |
|------|----------|
| Módulos protegidos | `lib/core/offline/never_lose_data_policy.dart` |
| Write-ahead antes do Firebase | `TenantOfflineWrite._persistBeforeRemote` |
| Fila + push | `SyncEngine` / `sync_repository.dart` |

Módulos: membros, eventos, avisos, patrimônio, financeiro, chat, mural.

### 9.2 Anti-travamento global

| Peça | Ficheiro |
|------|----------|
| Wrapper `compute()` | `lib/core/yahweh_heavy_work.dart` |
| Compressão fora da UI | `lib/services/image_helper.dart` |

Regra: uploads, compressão, PDF e relatórios pesados **não** bloqueiam a thread principal.

### 9.3 Recuperação automática

`AppFinalizeBootstrap.runAutomaticRecovery()` — arranque e resume:

1. Chat (auto-recovery + media outbox)
2. Mural publish outbox
3. Storage pending uploads
4. `SyncEngine.flushAll` se online

### O que NÃO fazer a seguir

- Novos serviços, filas ou caches paralelos
- ChatV2 / RepositoryV2 / DashboardV2

### Ciclo de produção

**CORRIGIR → TESTAR** em **Android + iOS + Web** até checklist passar.

Ver `docs/PADRONIZACAO_MULTIPLATAFORMA.md` — release bloqueada se falhar numa plataforma.
