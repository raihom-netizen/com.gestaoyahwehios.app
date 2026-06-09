# AUDITORIA CAMADA DE DADOS — Web = Android = iOS

**Gerado:** 2026-06-09  
**Igreja teste:** `igreja_o_brasil_para_cristo_jardim_goiano`  
**Veredito:** **REPROVADO** (unificação iniciada no Dashboard; acesso direto Firestore ainda em ~40 telas UI)

---

## Diagnóstico (causa das capturas)

O **app mobile** pintava o painel completo porque lia `_panel_cache/dashboard_summary` em **vários IDs do cluster** (slug/alias via `TenantResolverService`).

O **Web** com `ChurchContextService` já ligado a **um** `churchId` recebia cache “pobre” ou vazio — **sistema paralelo**, não widget quebrado.

---

## Correções aplicadas nesta sessão

| Arquivo | O que mudou |
|---------|-------------|
| `panel_dashboard_snapshot_service.dart` | `clusterDocIdsForPanel` → **só** `[ChurchRepository.churchId]` |
| `igreja_dashboard_moderno.dart` | Removido `TenantResolverService`; feeds via `ChurchRepository` |
| `church_tenant_resilient_reads.dart` | `loadTenantBundle`, `loadChurchAddressBundle`, `eventCategories` → `ChurchRepository` |
| `igreja_clean_shell.dart` | Chat presence → `ChurchRepository.churchId` |
| `igreja_painel_page.dart` | Resolve tenant → `ChurchRepository` |
| `.cursor/rules/camada-dados-unificada.mdc` | Regra permanente |
| `scripts/auditoria_camada_dados.ps1` | Grep obrigatório |

**Não existe** `WebMemberRepository` / `WebDashboardRepository` no repo (confirmado).

**API única existente:** `ChurchRepository`, `ChurchStorageService`, `ChurchContextService`, `ChurchTenantResilientReads` (usa `ChurchRepository.churchDoc`).

---

## FASE 1 — Grep legado (painel / serviços)

Executar: `.\scripts\auditoria_acessos_firestore_storage.ps1`  
Executar: `.\scripts\auditoria_camada_dados.ps1`

### TenantResolverService ainda em UI (22 arquivos)

Inclui: `calendar_page`, `igreja_cadastro_page`, `auth_gate`, `busca_global_widget`, `public_member_signup_page` (cadastro público — OK legado), etc.

**Dashboard (`igreja_dashboard_moderno.dart`):** **0** ocorrências após fix.

### FirebaseFirestore.instance em `ui/pages` (amostra crítica)

| Módulo | Direto Firestore? | Via ChurchRepository? |
|--------|-------------------|------------------------|
| Membros | **Não** | **Sim** |
| Dashboard moderno | **Não** | **Sim** (após fix) |
| Calendar | **Sim** (batch) | Parcial |
| Igreja cadastro | **Sim** | Parcial |
| Configurações | **Sim** | Parcial |

### Cluster slug/alias (proibido no painel)

| Arquivo | Linha | Trecho |
|---------|-------|--------|
| `member_profile_photo_update_service.dart` | 184, 352 | `getAllTenantIdsWithSameSlugOrAlias` |
| `carteirinha_staff_redirect.dart` | 50 | idem |

**Removido** de `panel_dashboard_snapshot_service` e `igreja_dashboard_moderno`.

---

## FASE 2 — Regra

Nenhuma tela do painel pós-login deve usar `FirebaseFirestore.instance` direto.

Delegar a `ChurchRepository.*` ou `ChurchTenantResilientReads.*`.

---

## FASE 3–10 — Pendente (próximos PRs)

1. Migrar `calendar_page`, `departments_page` (batch), `igreja_cadastro_page` writes → services
2. `FirestoreCacheService` TTL 5 min (Fase 8) — hoje: `_panel_cache`, Hive parcial
3. Chat streams nativos — `church_chat_thread_page` já usa Firestore streams; validar Web
4. Validação DEBUG CHURCH 3 plataformas — contagens Dashboard/Membros/Eventos

---

## Validação obrigatória (você)

1. Web + Android + iOS → **DEBUG CHURCH** → Publicar prova → Copiar relatório de aceite
2. Comparar: membros, dept, eventos, avisos, financeiro — **números iguais**
3. Dashboard Web deve mostrar: líderes, aniversariantes, eventos, avisos, gráficos (mesmo `_panel_cache` que o app)

---

## Comando para o Cursor (não “corrija telas”)

```
Prove unificação da camada de dados Web = Android = iOS.

1) Saída de .\scripts\auditoria_camada_dados.ps1 com arquivo:linha
2) Dashboard Web lê o mesmo churchId que Membros (ChurchRepository.churchId)
3) Zero TenantResolver no igreja_dashboard_moderno e panel_dashboard_snapshot_service
4) DEBUG CHURCH: contagens idênticas nas 3 plataformas

Veredito: APROVADO ou REPROVADO — não encerre sem prova.
```
