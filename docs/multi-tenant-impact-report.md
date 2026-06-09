# Relatório de impacto — refatoração multi-tenant

**Data:** 2026-06-08  
**Política:** coleções auxiliares **não foram apagadas** — apenas deixam de ser fonte operacional.

## Fonte da verdade (alvo)

| Camada | Caminho |
|--------|---------|
| Firestore | `igrejas/{churchId}` + subcoleções |
| Storage | `igrejas/{churchId}/…` |

## Coleções auxiliares — status

### `church_aliases`

| Aspecto | Detalhe |
|---------|---------|
| **Uso atual** | `TenantResolverService.resolveChurchAlias` — mapa alias → `canonicalId` |
| **Onde** | Resolução inicial de login / slug legado |
| **Risco se apagar** | Links públicos com slug antigo (`o-brasil-cristo-jardim-goiano`, `batista-renovada`, etc.) deixam de resolver |
| **Ação** | Manter coleção; resolver **uma vez** em `ChurchContextService.resolveAndBind`; módulos não consultam de novo |
| **Apagar?** | **Não** até migrar todos os slugs/links para `igrejas/{churchId}` |

### `tenants`

| Aspecto | Detalhe |
|---------|---------|
| **Uso no Flutter** | **0** ocorrências de `collection('tenants')` — ver `docs/tenants-collection-audit-report.md` |
| **Uso em Cloud Functions** | 39× em `functions/src/index.ts` — login fallback, onboarding, cobrança, backup |
| **Risco se apagar** | Alto para onboarding/cobrança legado; dados duplicados (ex. Batista Renovada) |
| **Apagar?** | **Não** — somente compatibilidade; operacional = `igrejas/{churchId}` |

### `church_roots`

| Aspecto | Detalhe |
|---------|---------|
| **Uso no Flutter** | Nenhuma |
| **Apagar?** | Auditar backend |

### `users.igrejaId` / `users.tenantId`

| Aspecto | Detalhe |
|---------|---------|
| **Uso** | Vínculo usuário → igreja na resolução inicial |
| **Ação** | `syncUserToCanonicalChurchId` alinha ao doc canónico |
| **Apagar campo?** | **Não** — necessário para login |

## Caminhos legados no código (antes da refatoração)

| Legado | Arquivos | Impacto |
|--------|----------|---------|
| `resolveModuleReadTenantId` (cluster redirect) | `igreja_clean_shell.dart`, leituras resilientes | Podia redirecionar leitura para doc “mais rico” do cluster |
| `richestChurchProfileForCadastro` | `church_repository.dart` | Mesclava perfil de irmãos — risco de dados cruzados + lentidão |
| `brasilparacristo_sistema` | `tenant_resolver_service.dart` | Redireciona para BPC canónico |
| Slug como fonte primária | site público, cadastro membro | Slug continua válido na URL; resolve para `churchId` uma vez |

## Módulos — matriz de conformidade

| Módulo | Firestore alvo | Status pós-refatoração |
|--------|----------------|------------------------|
| Cadastro Igreja | `igrejas/{id}` | Bootstrap paralelo + timeout 15s |
| Membros | `igrejas/{id}/membros` | Via `ChurchOperationalPaths` |
| Departamentos / Cargos | subcoleções | Via `ChurchTenantResilientReads` |
| Avisos / Eventos | subcoleções | Pipeline linear strict |
| Chat | `igrejas/{id}/chats` | Strict publish |
| Logo | `logoPath` + Storage | `ChurchBrandService` |
| Site público | `igrejas/{id}` + slug resolve | Alias só na entrada |

## Sintoma: loading infinito no Cadastro (Web)

**Causas identificadas:**

1. `_bootstrapCadastro` sem timeout global
2. `_applyChurchDataResult` retornava sem marcar `_cadastroBootstrapDone` se `data.isEmpty`
3. `ChurchRepository.loadChurchData` aguardava cluster scan (`richestChurchProfileForCadastro`) e verificação de logo no Storage

**Correções aplicadas:**

- `ChurchBootstrapService.loadCadastroPanel` — `Future.wait` + 15s
- `ChurchRepository.loadChurchData(directDocOnly: true)` — só `igrejas/{churchId}`
- Logo verify não bloqueante
- Erro visível + botão “Tentar novamente”

## Validação recomendada (Fase 12)

Login Web / Android / iOS com usuário BPC Jardim Goiano:

- `churchId` esperado: `igreja_o_brasil_para_cristo_jardim_goiano`
- Cadastro carrega em &lt; 15s ou mostra erro
- Membros, logo, mural usam o mesmo `churchId`

## Próximos passos (sem apagar dados)

1. ~~Migrar shell e auth gate para `ChurchContextService` exclusivo~~ **Feito** (2026-06-08)
2. ~~`ChurchOperationalPaths.resolveModuleReadTenantId` retorna `currentChurchId` quando bound~~ **Feito**
3. `ChurchStorageService` — wrapper padronizado para uploads (paths only)
4. Remover chamadas diretas a `TenantResolverService.resolveModuleReadTenantId` em dashboard/departments (já herdam contexto via cache)
5. Script de limpeza **opcional** de campos legados (`logo_url`, etc.) — não coleções
6. Auditar Cloud Functions para `tenants` / `church_aliases`

## Serviços criados nesta sessão

| Serviço | Função |
|---------|--------|
| `ChurchContextService` | Resolve uma vez após login; expõe `currentChurchId` |
| `ChurchBootstrapService` | Cadastro: `Future.wait` paralelo + timeout 15s |
| `ChurchStorageService` | Upload padronizado — só `storagePath` |
| `SystemDiagnosticService` | Diagnóstico churchId/paths/tempos/erros |

## Integração de contexto

| Ponto | Comportamento |
|-------|---------------|
| `auth_gate.dart` | `ChurchContextService.resolveAndBind` após resolver igrejaId |
| `igreja_clean_shell.dart` | `_resolveOperationalTenant` usa `resolveAndBind` |
| `church_sign_out_navigation.dart` | `ChurchContextService.clear()` no logout |
| `church_operational_paths.dart` | `resolveCached` / `resolveModuleReadTenantId` preferem contexto bound |
