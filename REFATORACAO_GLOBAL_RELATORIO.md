# REFATORAÇÃO DEFINITIVA GLOBAL — Gestão YAHWEH

**Data:** 2026-06-08  
**Objetivo:** Uma única fonte de verdade `igrejas/{churchId}` (Firestore) e `igrejas/{churchId}/` (Storage), sem tenants/aliases no painel.

---

## 1. Mudança estrutural principal (impacto em todos os módulos)

O problema de skeleton infinito na Web vinha do **resolver legado** (`TenantResolverService`, `church_aliases`, `syncStorageTenantId`) sendo chamado em cadeia por `ChurchOperationalPaths.resolveCached()`.

### Corrigido na camada central (propaga para ~50 módulos sem editar cada tela)

| Arquivo | O que mudou |
|---------|-------------|
| `church_operational_paths.dart` | `_resolveOperational()` e `resolveModuleReadTenantId()` passam a usar **só** `ChurchRepository.churchId()` — **sem** `resolveOperationalChurchDocId`, **sem** `syncStorageTenantId` |
| `church_context_service.dart` | `resolveAndBind()` lê `users/{uid}` → valida `igrejas/{churchId}` → bind. **Removidos** alias, tenant, slug e `TenantResolverService` |
| `church_repository.dart` | `loadChurchDataInner()` só leitura directa `igrejas/{churchId}`; API completa de módulos; timeout Web 10s |

**Efeito:** Qualquer tela que ainda chama `ChurchOperationalPaths.resolveCached()` (Financeiro, Certificados, Eventos, Chat, Cargos, etc.) deixa de travar na Web à espera do resolver legado.

---

## 2. API única — classes oficiais

### ChurchContextService
- `currentChurchId` — contexto da sessão
- `resolveAndBind()` — `users/{uid}` + validação `igrejas/{churchId}`
- **Proibido no painel:** alias, tenant, slug

### ChurchRepository (`igrejas/{churchId}/…`)
Métodos disponíveis:

| Método público | Subcoleção Firestore real |
|----------------|---------------------------|
| `church()` | doc raiz |
| `departamentos()` | `departamentos` |
| `cargos()` | `cargos` |
| `membros()` | `membros` |
| `visitantes()` | `visitantes` |
| `financeiro()` | `finance` |
| `fornecedores()` | `fornecedores` |
| `patrimonio()` | `patrimonio` |
| `eventos()` | `noticias` |
| `avisos()` | `avisos` |
| `chat()` / `chats()` | `chats` |
| `configuracoes()` | `config` |
| `certificados()` | `certificados_emitidos` |
| `carteirinhas()` | `membros` (+ Storage `cartao_membro/`) |
| `escalas()` | `escalas` |
| `notificacoes()` | `notificacoes` |

### ChurchStorageService
- Raiz: `igrejas/{churchId}/`
- Subpastas: `configuracoes/`, `membros/`, `avisos/`, `eventos/`, `chat/`, `patrimonio/`, `certificados/`, `cartao_membro/`, `financeiro/`
- `displayUrl()` / `logoDisplayUrl()` — URL **só na exibição**, nunca no upload
- Upload: grava `storagePath`, confirma existência, **sem** `getDownloadURL` no fluxo de gravação

### Web — anti skeleton infinito
- `ChurchRepository.panelQueryTimeout` = 10s
- Novo widget: `ChurchPanelTimedFutureBuilder` em `church_panel_ui_helpers.dart`
- Padrão existente: `ChurchPanelErrorBody` + botão "Tentar novamente"

---

## 3. Arquivos alterados nesta sessão

### Serviços (camada oficial)
- `flutter_app/lib/services/church_context_service.dart` — reescrito
- `flutter_app/lib/services/church_operational_paths.dart` — resolver painel sem legado
- `flutter_app/lib/services/church_repository.dart` — API completa + load directo
- `flutter_app/lib/services/church_storage_service.dart` — display URL + financeiro
- `flutter_app/lib/services/church_bootstrap_service.dart`
- `flutter_app/lib/services/church_tenant_resilient_reads.dart`
- `flutter_app/lib/services/church_module_firestore_audit.dart` *(novo)*
- `flutter_app/lib/services/church_module_path_audit_service.dart` *(novo)*

### UI / painel
- `flutter_app/lib/ui/auth_gate.dart`
- `flutter_app/lib/ui/igreja_clean_shell.dart`
- `flutter_app/lib/ui/pages/departments_page.dart` — referência migrada
- `flutter_app/lib/ui/pages/igreja_cadastro_page.dart`
- `flutter_app/lib/ui/pages/cargos_page.dart` — removido merge multi-tenant
- `flutter_app/lib/ui/pages/visitors_page.dart` — removido `resolveOperationalChurchDocId`
- `flutter_app/lib/ui/pages/finance_page.dart`
- `flutter_app/lib/ui/pages/fornecedores_page.dart`
- `flutter_app/lib/ui/pages/configuracoes_page.dart`
- `flutter_app/lib/ui/pages/members_page.dart`
- `flutter_app/lib/ui/pages/patrimonio_page.dart`
- `flutter_app/lib/ui/pages/church_chat_hub_page.dart`
- `flutter_app/lib/ui/pages/church_panel_diagnostic_page.dart`
- `flutter_app/lib/ui/widgets/church_panel_ui_helpers.dart` — `ChurchPanelTimedFutureBuilder`

### Regra de projeto
- `.cursor/rules/church-repository-unico.mdc`

---

## 4. Caminhos legados removidos do fluxo do painel

| Legado | Status no painel igreja |
|--------|-------------------------|
| `TenantResolverService.resolveOperationalChurchDocId` | **Removido** de `resolveAndBind`, `_resolveOperational`, `visitors_page` |
| `TenantResolverService.syncStorageTenantId` | **Removido** de `resolveAndBind`, fallback do shell |
| `TenantResolverService.resolveModuleReadTenantId` | **Substituído** por `ChurchRepository.churchId` em `ChurchOperationalPaths` |
| `TenantResolverService.rememberModuleReadTenantId` | **Removido** de `_applyBind` e `rememberResolved` |
| `TenantResolverService.getAllTenantIdsWithSameSlugOrAlias` | **Removido** de `cargos_page` (merge membros) |
| `TenantResolverService.operationalChurchId` | **Removido** de `loadChurchDataInner` |
| `TenantResolverService.peekRegistrationContext` | **Removido** de `peekCached` |
| `collection('tenants')` | **Não usado** pelo app painel (só ADM/diagnóstico) |
| `collection('church_aliases')` | **Não usado** pelo app painel (só `multi_tenant_diagnostic_service`) |

---

## 5. Legado ainda isolado (fora do painel pós-login)

Mantido **apenas** para site público, ADM master, migração e cluster:

- `tenant_resolver_service.dart` — classe legada (não eliminar ainda; isolar)
- `church_operational_paths.dart` → `clusterDocIds()`, `resolveOperationalChurch()` — ADM/cluster
- `multi_tenant_diagnostic_service.dart` — auditoria ADM
- `church_public_page.dart`, `public_member_signup_page.dart` — slug público
- `billing_license_service.dart` — operações master
- Chamadas directas a `TenantResolverService` em ~90 arquivos (maioria agora **inofensiva** no painel porque `resolveCached` não resolve mais via alias)

---

## 6. Módulos — estado de migração

| Módulo | Estado |
|--------|--------|
| Cadastro Igreja | ✅ `loadByChurchId` directo |
| Departamentos | ✅ `ChurchRepository` + timeout Web |
| Membros | ✅ `panelChurchId` |
| Cargos | ✅ sem merge multi-tenant |
| Visitantes | ✅ sem resolver async |
| Financeiro | ⚠️ UI ainda chama `resolveCached` (agora síncrono/effectivo) |
| Fornecedores | ✅ parcial |
| Configurações | ✅ parcial |
| Patrimônio | ✅ parcial |
| Certificados | ⚠️ `resolveCached` (efectivo, migrar para `ChurchRepository`) |
| Carteirinhas | ⚠️ `member_card_page` — pendente migração directa |
| Avisos / Eventos | ⚠️ publish flows — pendente strict publish |
| Chat | ⚠️ `church_chat_service` — pendente strict publish |
| Web skeleton | ✅ timeout central; aplicar `ChurchPanelTimedFutureBuilder` em telas restantes |

---

## 7. Pendências (próxima fase)

1. Substituir chamadas directas `FirebaseFirestore.instance` nas pages por `ChurchRepository`
2. Aplicar `ChurchPanelTimedFutureBuilder` em Financeiro, Certificados, Eventos, Cargos (listas com Future preso)
3. Publish flows strict (avisos, eventos, chat, membros) conforme spec
4. Compressão mídia global (1920px, JPEG 80, H264 90s)
5. Cache Hive offline global
6. Remover `TenantResolverService` completamente após migração site público + ADM

---

## 8. Teste recomendado (igreja de teste)

`churchId`: `igreja_o_brasil_para_cristo_jardim_goiano`

1. Web: login → Departamentos, Cargos, Financeiro, Configurações — **máx. 10s** ou erro com retry
2. Android: mesmo `churchId` nos logs `MODULO/churchId/PATH`
3. Cadastro: logo grava `logoPath` em Firestore; URL só na exibição via `ChurchStorageService.logoDisplayUrl`

---

## 9. Resumo executivo

**Antes:** Web chamava resolver legado → Future presa → skeleton infinito.  
**Agora:** Painel resolve `churchId` uma vez (`users/{uid}` + `igrejas/{id}`) e todos os módulos leem o mesmo path que Android/iOS.

**WEB = ANDROID = IOS** no critério de `churchId` e Firestore path, via as mesmas classes `ChurchContextService`, `ChurchRepository`, `ChurchStorageService`.
