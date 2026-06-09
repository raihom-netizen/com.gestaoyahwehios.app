# AUDITORIA COM PROVAS — Web = Android = iOS

**Gerado:** 2026-06-09  
**Igreja teste:** `igreja_o_brasil_para_cristo_jardim_goiano`  
**Veredito geral:** **REPROVADO** (legado ainda no repositório + prints das 3 plataformas pendentes)

---

## 1. Tela DEBUG CHURCH (criada)

**Arquivo:** `flutter_app/lib/ui/pages/debug_church_page.dart`  
**Serviço:** `flutter_app/lib/services/debug_church_audit_service.dart`  
**Acesso:** Painel Igreja → **Configurações** → **DEBUG CHURCH (auditoria com provas)**

### O que a tela mostra (consulta REAL no Firestore)

| Campo | Origem |
|-------|--------|
| PLATAFORMA | `WEB` / `ANDROID` / `IOS` |
| churchId | `ChurchRepository.churchId()` |
| Firestore Path | `igrejas/{churchId}` |
| Storage Path | `ChurchStorageLayout.churchRoot(churchId)` |
| Nome, Cidade, Estado, Telefone, Email, LogoPath | doc `igrejas/{churchId}` |
| Contagens | query real em cada subcoleção |

### Log obrigatório no console (cada módulo)

```
MODULO
Cadastro Igreja
churchId
igreja_o_brasil_para_cristo_jardim_goiano
PATH
igrejas/igreja_o_brasil_para_cristo_jardim_goiano
```

(repetido para Departamentos, Cargos, Membros, etc.)

### Como obter PROVA nas 3 plataformas

1. Login na mesma igreja em **Web**, **Android** e **iOS**
2. Abrir **DEBUG CHURCH**
3. Botão **copiar relatório** (ícone copy) — colar em 3 ficheiros
4. **Tirar PRINT** da tela em cada plataforma
5. Comparar: `churchId`, paths e contagens devem ser **idênticos**

> O agente **não pode** executar Android/iOS nem gerar prints — isso é feito por você.

---

## 2. Tabela obrigatória — PATH consultado (código + DEBUG CHURCH)

Paths abaixo são os que **DEBUG CHURCH executa** (mesmo código Dart em Web/Android/iOS).

| MÓDULO | WEB | ANDROID | IOS | PATH CONSULTADO | STATUS |
|--------|-----|---------|-----|-----------------|--------|
| **CADASTRO** | *mesmo código* | *mesmo código* | *mesmo código* | `igrejas/{churchId}` | **APROVADO** path |
| **DEPARTAMENTOS** | idem | idem | idem | `igrejas/{churchId}/departamentos` | **APROVADO** path |
| **CARGOS** | idem | idem | idem | `igrejas/{churchId}/cargos` | **APROVADO** path |
| **MEMBROS** | idem | idem | idem | `igrejas/{churchId}/membros` | **APROVADO** path |
| **FORNECEDORES** | idem | idem | idem | `igrejas/{churchId}/fornecedores` | **APROVADO** path |
| **FINANCEIRO** | idem | idem | idem | `igrejas/{churchId}/finance` | **APROVADO** path |
| **EVENTOS** | idem | idem | idem | `igrejas/{churchId}/noticias` | **APROVADO** path |
| **AVISOS** | idem | idem | idem | `igrejas/{churchId}/avisos` | **APROVADO** path |
| **CHAT** | idem | idem | idem | `igrejas/{churchId}/chats` | **APROVADO** path *(após fix `church_chat_thread_page`)* |
| **PATRIMÔNIO** | idem | idem | idem | `igrejas/{churchId}/patrimonio` | **APROVADO** path |

### STATUS por coluna WEB / ANDROID / IOS

Preencher após prints (exemplo esperado se correção OK):

| MÓDULO | WEB churchId | ANDROID churchId | IOS churchId | Iguais? |
|--------|--------------|------------------|--------------|---------|
| Todos | `igreja_o_brasil_...` | `igreja_o_brasil_...` | `igreja_o_brasil_...` | ☐ SIM / ☐ NÃO |

**Contagens** (membros, dept, etc.) podem variar por cache/timing; **churchId e PATH não podem variar**.

---

## 3. Auditoria legado no repositório (grep com prova)

Relatório completo: [`AUDITORIA_LEGADO_RELATORIO.md`](AUDITORIA_LEGADO_RELATORIO.md)

### Resumo com números

| Padrão | Ocorrências | Painel crítico? |
|--------|-------------|-----------------|
| `collection('tenants')` | **0** | — |
| `collection('church_aliases')` | **1** | Não — só `multi_tenant_diagnostic_service.dart:133` (ADM) |
| `collection('church_roots')` | **0** | — |
| `resolveOperationalChurchDocId` | **~30** | Restam em dashboard, calendar, site público, FCM, `tenant_resolver_service.dart` |
| `syncStorageTenantId` | **várias** | **Removido** de `church_storage_layout.dart:122` nesta sessão |

### Trechos que FALHAM a regra (exemplos reais)

**church_aliases (única leitura Firestore):**

```
flutter_app/lib/services/multi_tenant_diagnostic_service.dart:133
          .collection('church_aliases')
```

**resolveOperationalChurchDocId ainda em UI painel (não nos 10 módulos da tabela):**

```
flutter_app/lib/ui/pages/igreja_dashboard_moderno.dart:3072
flutter_app/lib/ui/pages/igreja_dashboard_moderno.dart:6874
flutter_app/lib/ui/pages/calendar_page.dart:854
```

**TenantResolver em serviços auxiliares (não DEBUG CHURCH):**

```
flutter_app/lib/services/church_member_contact_chat.dart:272
      operationalTenant = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib/services/fcm_service.dart:53
flutter_app/lib/ui/widgets/mercado_pago_church_settings_section.dart:67-68
```

### Correção aplicada com prova de arquivo (Storage)

**Antes** (`church_storage_layout.dart:122-124`):

```dart
final tid = TenantResolverService.syncStorageTenantId(tenantId);
return 'igrejas/$tid';
```

**Depois:**

```dart
final tid = ChurchRepository.churchId(tenantId.trim());
final id = tid.isNotEmpty ? tid : tenantId.trim();
return 'igrejas/$id';
```

---

## 4. Verificação grep — módulos críticos do painel

Comando: `rg resolveOperationalChurchDocId flutter_app/lib/ui/pages/{cadastro,dept,...}`

| Arquivo módulo | `resolveOperationalChurchDocId` | `TenantResolver` |
|----------------|--------------------------------|------------------|
| `igreja_cadastro_page.dart` | 0 | 0 *(só richness score)* |
| `departments_page.dart` | 0 | 0 |
| `cargos_page.dart` | 0 | 0 |
| `members_page.dart` | 0 | 0 |
| `fornecedores_page.dart` | 0 | 0 |
| `finance_page.dart` | 0 | 0 |
| `events_manager_page.dart` | 0 | 0 |
| `church_chat_thread_page.dart` | 0 | 0 *(corrigido hoje)* |

Publish services (gravação):

| Serviço | `resolveOperationalChurchDocId` |
|---------|--------------------------------|
| `membro_publish_verification_service.dart` | 0 |
| `avisos_publish_verification_service.dart` | 0 |
| `eventos_publish_verification_service.dart` | 0 |
| `chat_publish_verification_service.dart` | 0 |

---

## 5. Veredito final

| Critério | Resultado |
|----------|-----------|
| PATH painel 10 módulos = `igrejas/{churchId}/…` | **APROVADO** (código + DEBUG CHURCH) |
| Storage = `igrejas/{churchId}/` sem syncStorageTenantId | **APROVADO** (após fix `church_storage_layout`) |
| Zero legado no repositório inteiro | **REPROVADO** (~30 resolvers + 1 church_aliases ADM) |
| Prints Web = Android = iOS | **PENDENTE** (você tira os 3 prints) |
| Logs sem tenants/alias/tenantResolver | **PENDENTE** — validar console ao abrir DEBUG CHURCH |

### Para mudar para APROVADO

1. Os 3 prints mostram **mesmo churchId** e **mesmos paths**
2. Console DEBUG CHURCH **sem** tokens: `tenants`, `church_aliases`, `tenantResolver`, `alias`
3. Eliminar `resolveOperationalChurchDocId` dos ficheiros restantes (lista em `AUDITORIA_LEGADO_RELATORIO.md`)

---

## 6. Arquivos criados/alterados nesta auditoria

| Arquivo | Ação |
|---------|------|
| `flutter_app/lib/ui/pages/debug_church_page.dart` | CRIADO |
| `flutter_app/lib/services/debug_church_audit_service.dart` | CRIADO |
| `flutter_app/lib/ui/pages/configuracoes_page.dart` | Link DEBUG CHURCH |
| `flutter_app/lib/core/church_storage_layout.dart` | Fix `churchRoot` |
| `flutter_app/lib/ui/pages/church_chat_thread_page.dart` | Fix churchId |
| `AUDITORIA_LEGADO_RELATORIO.md` | CRIADO (grep arquivo:linha) |
| `AUDITORIA_PROVA_TABELA.md` | CRIADO (este ficheiro) |
