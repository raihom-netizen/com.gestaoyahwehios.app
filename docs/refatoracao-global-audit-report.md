# Refatoração Global Definitiva — Relatório de Auditoria

**Data:** 2026-06-08  
**Projeto:** Gestão YAHWEH (Flutter Web/Android/iOS + Cloud Functions)  
**Política:** Não apagar coleções legadas sem backup — parar uso operacional.

---

## FASE 1 — Resumo da auditoria

### Fonte única alvo

| Camada | Caminho oficial |
|--------|-----------------|
| Firestore | `igrejas/{churchId}` + subcoleções |
| Storage | `igrejas/{churchId}/…` |

### `collection('tenants')` / `collection("tenants")`

| Área | Ocorrências | Operacional? |
|------|-------------|--------------|
| **flutter_app/** | **0** | ✅ Nenhuma |
| **functions/src/index.ts** | 39 | ⚠️ Login fallback, onboarding, cobrança, backup |
| **functions/lib/** (compilado) | 39+ | Espelho TS |
| **functions/src/churchTenantProvisioning.ts** | 1 | Onboarding |
| **functions/src/churchCanonicalResolve.ts** | 1 | Resolução canónica |
| **functions/src/consolidateBpcCluster.ts** | 1 | Migração BPC |
| **Scripts** (seed, migrate, backfill) | 8+ | Migração apenas |

### `collection('church_aliases')`

| Área | Ocorrências | Operacional? |
|------|-------------|--------------|
| **flutter_app** | 1 (`multi_tenant_diagnostic_service.dart`) | 🔍 Só diagnóstico ADM |
| **tenant_resolver_service.dart** | `resolveChurchAlias` | ⚡ **Uma vez** no login/slug público |
| **scripts/** | migrate, seed | Migração |

### `collection('church_roots')`

| Área | Ocorrências Flutter | Operacional? |
|------|---------------------|--------------|
| **flutter_app** | **0** | ✅ |
| **scripts/migrate_church_roots_and_aliases.mjs** | 1 | Migração |

### `tenantRepository` / `tenantService` / `tenantProvider`

**0 ocorrências** em todo o projeto.

### Parâmetro `tenantId` (Flutter)

~**170 arquivos** — na maioria é o **nome do parâmetro** para `churchId` canónico passado pelo shell. Não implica leitura de `tenants/`.

### `canonicalId`

~**30 arquivos** — usado em resolução de alias, logs e Cloud Functions. Após bind: `ChurchContextService.currentChurchId`.

### `slug` / `alias`

- **Entrada pública:** URL do site → resolve para `igrejas/{churchId}` uma vez
- **Firestore:** campos `slug`/`alias` no doc `igrejas/{id}` (metadado, não fonte paralela)
- **Proibido pós-login:** re-resolver slug em módulos operacionais

### `users.igrejaId` / `users.tenantId`

Usado **apenas na resolução inicial** (auth gate). Sincronizado ao doc canónico via `syncUserToCanonicalChurchId`.

---

## FASE 2–3 — Serviços oficiais (implementados)

| Serviço | Arquivo | Responsabilidade |
|---------|---------|------------------|
| **ChurchContextService** | `church_context_service.dart` | `currentChurchId`, `currentChurchData`, bind pós-login |
| **ChurchRepository** | `church_repository.dart` | Única porta de leitura do perfil `igrejas/{id}` |
| **ChurchBootstrapService** | `church_bootstrap_service.dart` | `Future.wait` paralelo + timeout 15s |
| **ChurchBrandService** | `church_brand_service.dart` | Logo: `logoPath` + Storage |
| **StorageService** | `storage_service.dart` | Compressão + `uploadToChurchPath` |
| **ChurchStorageService** | `church_storage_service.dart` | Upload bytes → só `storagePath` |
| **ChurchPanelLocalCache** | `church_panel_local_cache.dart` | Hive (mobile) + SharedPreferences (Web) |
| **SystemDiagnosticService** | `system_diagnostic_service.dart` | churchId, paths, tempos, traces |
| **ChurchOperationalFirestoreTrace** | `church_operational_firestore_trace.dart` | Origem de cada consulta |

---

## FASE 4–5 — Estrutura Firestore / Storage

### Subcoleções oficiais `igrejas/{churchId}/`

`membros`, `departamentos`, `cargos`, `eventos`, `avisos`, `chat`/`chats`, `escalas`, `finance`/`financeiro`, `patrimonio`, `certificados`, `carteirinhas`, `agenda`, `notificacoes`, `configuracoes`, `users`, `event_templates`

### Storage oficial `igrejas/{churchId}/`

| Módulo | Path |
|--------|------|
| Logo | `configuracoes/logo_igreja.png` |
| Membro | `membros/{memberId}/perfil.jpg` |
| Eventos | `eventos/{eventId}/` (até 5 fotos + vídeo 90s) |
| Avisos | `avisos/{avisoId}/` (até 5 fotos) |
| Chat | `chat/{threadId}/` |
| Patrimônio | `patrimonio/` |
| Certificados | `certificados/` |
| Carteirinhas | `carteirinhas/` |
| Site público | `site_publico/` |

`FeedTenantStorageMap.usePhysicalTenantPaths = false` → novos uploads só em `igrejas/`.

---

## FASE 6–12 — Conformidade por módulo

| Módulo | Firestore | Storage fields | Status |
|--------|-----------|----------------|--------|
| Cadastro | `igrejas/{id}` | `logoPath` | ✅ Bootstrap + cache |
| Logo | `logoPath` | `configuracoes/logo_igreja.png` | ✅ ChurchBrandService |
| Membros | `igrejas/{id}/membros` | `fotoPath` (strict publish) | 🟡 URLs legadas em leitura |
| Eventos | subcoleção `eventos` | `storagePaths[]`, `videoPath` | ✅ Pipeline linear |
| Avisos | subcoleção `avisos` | `storagePaths[]` | ✅ Pipeline linear |
| Chat | subcoleção | `storagePath` (sem `mediaUrl` novo) | 🟡 Leitura legado `mediaUrl` |
| Carteirinhas | subcoleção | ChurchBrandService | 🟡 Auditar paths |
| Certificados | subcoleção | ChurchBrandService | 🟡 Auditar paths |
| Site público | `igrejas/{id}` | resolve slug 1× | ✅ |
| Dashboard | `operationalChurchId` | — | ✅ |
| Financeiro | `igrejas/{id}/finance` | comprovante paths | ✅ |

---

## FASE 13–15 — Performance Web

| Item | Status |
|------|--------|
| `ChurchBootstrapService` Future.wait | ✅ cadastro + logo + deps + cargos |
| Cache local Web | ✅ SharedPreferences (`ChurchPanelLocalCache`) |
| Cache local mobile | ✅ Hive (`TenantModuleHiveCache`) |
| Timeout 15s | ✅ Context, Bootstrap, Repository |
| Spinner infinito Cadastro | ✅ Corrigido (`_cadastroBootstrapDone` sempre setado) |

---

## FASE 16 — Firestore Indexes

Arquivo: `firestore.indexes.json` — **640+ linhas**, índices existentes + **19 novos** adicionados:

- `membros`: ativo+createdAt, ativo+updatedAt, memberId+ativo
- `departamentos`, `cargos`: ativo+createdAt/updatedAt
- `eventos`: dataEvento+ativo, tipo+createdAt
- `avisos`: ativo+createdAt/updatedAt, tipo+createdAt
- `finance`, `patrimonio`, `certificados`, `agenda`, `notificacoes`
- `igrejas`: churchId+createdAt

**Deploy índices:** somente com pedido explícito do usuário.

---

## FASE 17 — Diagnóstico

`SystemDiagnosticService.probe()` retorna:

- `churchId`, `seedId`, `firestorePath`, `storagePath`
- `loadDurationMs`, `firestoreReadMs`, `bootstrapMs`
- `readSource`, `lastError`, `tenantMismatch`
- `recentTraces[]` (origem, path, duração)
- `fromLocalCache`

---

## FASE 18 — WEB = ANDROID = IOS

| Verificação | Resultado |
|-------------|-----------|
| `collection('tenants')` no Flutter | **0** |
| Repositórios diferentes por plataforma | **Não encontrado** |
| `kIsWeb` com Firestore path alternativo | **Não encontrado** |
| Resolução de tenant | `ChurchContextService` unificado |

Diferenças `kIsWeb` existentes: compressão de arquivo, Hive desabilitado na Web (substituído por SharedPreferences), guard de snapshots Firestore JS.

---

## FASE 19 — Migração (sem apagar)

### Dados em coleções legadas

| Coleção | Conteúdo típico | Ação |
|---------|-----------------|------|
| `tenants/{id}` | alias, slug, cpf, email duplicados | Manter; espelhar writes de onboarding |
| `church_aliases/{slug}` | `canonicalId` | Manter; resolver 1× no login |
| `church_roots` | Raízes antigas | Auditar scripts |
| `igrejas/{id}` | **Fonte da verdade** | Destino final |

### Cloud Functions — prioridade de migração

1. Helper `readChurchDoc(id)` → `igrejas` primeiro, `tenants` só fallback
2. Onboarding: escrever `igrejas` + espelho opcional em `tenants`
3. `usersIndex`/`members` em `tenants/` → migrar para `igrejas/{id}/membros`

**Não apagar** sem backup (`GESTAO_YAHWEH_BKPS_DIARIOS` já existe nas CF).

---

## FASE 20 — Checklist de validação

| Teste | Web | Android | iOS |
|-------|-----|---------|-----|
| Login → churchId BPC | ☐ | ☐ | ☐ |
| Cadastro carrega ≤15s | ☐ | ☐ | ☐ |
| Logo via ChurchBrandService | ☐ | ☐ | ☐ |
| Membros lista | ☐ | ☐ | ☐ |
| Mural avisos/eventos | ☐ | ☐ | ☐ |
| Chat upload storagePath | ☐ | ☐ | ☐ |
| Site público slug | ☐ | — | — |
| Batista Renovada mesmo churchId | ☐ | ☐ | ☐ |

**churchId esperado BPC:** `igreja_o_brasil_para_cristo_jardim_goiano`  
**churchId esperado Batista:** `igreja_batista_renovada`

---

## Resultado atual vs objetivo

| Critério | Status |
|----------|--------|
| Flutter só usa `igrejas/{churchId}` | ✅ |
| `tenants/` fora do app operacional | ✅ |
| `church_aliases` só na resolução inicial | ✅ |
| ChurchContextService com dados + cache | ✅ |
| Bootstrap paralelo + cache Web | ✅ |
| Índices Firestore expandidos | ✅ |
| Cloud Functions migradas | ⏳ Pendente |
| Campos legados (`logo_url`, `mediaUrl`) removidos | 🟡 Em progresso |
| Deploy produção | ⏳ Aguardando pedido explícito |

---

## Documentos relacionados

- `docs/tenants-collection-audit-report.md`
- `docs/multi-tenant-impact-report.md`
