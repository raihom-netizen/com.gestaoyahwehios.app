# Roadmap Fases Críticas — Gestão YAHWEH

**Estimativa:** 80–90% pronto. Gargalo = padronizar `igrejas/{churchId}` e eliminar resolvers legados.

---

## 🔴 Fase 1 — WEB = ANDROID = IOS

| Item | Status | Notas |
|------|--------|-------|
| `ChurchContextService` sem alias/tenant | ✅ | `users/{uid}` → valida `igrejas/{id}` |
| `ChurchOperationalPaths.resolveCached` | ✅ | Só `ChurchRepository.churchId()` |
| `ChurchPublishContext` (gravações) | ✅ **novo** | Membros, Avisos, Eventos, Chat, Patrimônio |
| Cadastro Igreja timeout 10s | ✅ **novo** | Erro + retry, sem spinner infinito |
| Departamentos | ✅ | `ChurchRepository` + timeout Web |
| Cargos | ✅ **novo** | Sem `resolveCached` async |
| Membros leitura cluster | ✅ **novo** | Só um `churchId` |
| Financeiro paths | ✅ **novo** | `ChurchRepository.churchId` |
| Fornecedores | ✅ | Migrado sessão anterior |
| Legado `TenantResolver` no painel | ⚠️ | Resta em ~70 ficheiros (ADM, site público, warmup) |

**Sintomas Web a validar após deploy:**
- Cadastro Igreja carrega em ≤10s ou mostra erro
- Financeiro usa mesmo `churchId` do header
- Cargos = mesmo path que Android

---

## 🔴 Fase 2 — Cadastro + Departamentos + Cargos + Membros

| Módulo | Status | Bloqueio restante |
|--------|--------|-------------------|
| Cadastro Igreja | 🟡 | Testar Web com `igreja_o_brasil_para_cristo_jardim_goiano` |
| Departamentos | ✅ | — |
| Cargos | 🟡 | Merge multi-tenant removido; validar lista membros/cargo |
| Membros edição | 🟡 | `MembroStrictUpdateService` agora usa `ChurchPublishContext` |
| Membros exclusão | 🟡 | Mesmo fix; confirmar Storage cleanup |

---

## 🔴 Fase 3 — Avisos + Eventos + Chat

| Módulo | Status | Meta |
|--------|--------|------|
| Avisos publish | 🟡 | `ensureDraft` + pipeline; verificar foto pós-`success` |
| Eventos publish | 🟡 | `ChurchPublishContext` + verificação Storage |
| Chat mídia | 🟡 | `ChatPublishVerificationService` unificado |
| Tipos chat | ⚠️ | Validar manualmente: texto, foto, PDF, Word, Excel, vídeo, áudio |

**Regra:** `publishState = success` só após Firestore + Storage confirmados.

---

## 🟡 Fase 4 — Carteirinhas + Certificados + Site Público

| Item | Status |
|------|--------|
| `cardVersion` / `pdfVersion` | 🟡 Serviço criado; integrar em `member_card_page` |
| Logo via `logoPath` | ✅ `ChurchStorageService.logoDisplayUrl` |
| Site público `igrejas/{id}` | ⚠️ Ainda usa resolvers em `church_public_page` |

---

## 🟡 Fase 5 — Financeiro + Patrimônio + Fornecedores

| Item | Status |
|------|--------|
| `saldoAtual` pré-calculado | ✅ CF + `_dashboard_cache` |
| Financeiro parcial Web | 🟡 Testar após Fase 1 |
| Patrimônio / Fornecedores | 🟡 Paths unificados; testar |

---

## 🟢 Fase 6 — FCM + MP + Relatórios + Backup

| Item | Status |
|------|--------|
| `_dashboard_cache` | ✅ |
| Diagnóstico ADM | ✅ FCM, Functions, MP, tempo médio |
| `cleanupOrphanFiles` CF | ✅ (deploy pendente) |
| Compressão 1920/JPEG80 | 🟡 Parcial em `MediaImageVariantsService` |
| Push Android/iOS/Web | ⚠️ Teste manual |

---

## Ordem de teste recomendada (igreja teste)

`churchId`: `igreja_o_brasil_para_cristo_jardim_goiano`

1. Web login → header mostra mesmo ID que Android
2. Cadastro Igreja → carrega ou erro 10s
3. Departamentos + Cargos → listas
4. Membro → editar nome → recarregar → confirmar
5. Membro → excluir → doc sumiu
6. Aviso com foto → publicar → foto visível
7. Evento com vídeo → publicar → vídeo visível
8. Chat → enviar foto → confirma enviado

---

## Deploy quando autorizado

```bash
firebase deploy --only functions:scheduledCleanupOrphanFiles
firebase deploy --only firestore:indexes
# Web/Android/iOS via script completo do projeto
```
