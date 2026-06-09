# Produção Estável — Gestão YAHWEH

**Data:** 2026-06-08  
**Escopo:** Melhorias pós-unificação `igrejas/{churchId}`

---

## 1. Gravações órfãs — `cleanupOrphanFiles`

**Novo:** `functions/src/cleanupOrphanFiles.ts`  
**Export:** `scheduledCleanupOrphanFiles` (diário, `southamerica-east1`)

| Ação | Detalhe |
|------|---------|
| Firestore → Storage | Remove `storagePath` quando ficheiro não existe (avisos, eventos, chat) |
| Storage → Firestore | Apaga ficheiros em `avisos/` e `eventos/` sem doc (>7 dias) |
| Estados | `draft`, `uploading`, `failed`, `verifying` |

Complementa: `storageCleanupOnFirestoreDelete.ts`, `purgeStalePendingUploads.ts`

---

## 2. Índices Firestore (`firestore.indexes.json`)

Adicionados:

| Coleção | Campos |
|---------|--------|
| `finance` | `tipo` + `data` |
| `membros` | `status` + `nome` |
| `avisos` | `publicado` + `createdAt` |
| `eventos` / `noticias` | `dataEvento` + `active` |
| `patrimonio` | `categoria` + `status` |
| `messages` | `threadId` + `createdAt` |

**Deploy índices:** `firebase deploy --only firestore:indexes` (quando autorizado)

---

## 3. Dashboard instantâneo — `_dashboard_cache`

**CF:** `panelDashboardCache.ts` grava `igrejas/{churchId}/_dashboard_cache/main`:

```json
{
  "totalMembros": 120,
  "ativos": 100,
  "visitantes": 15,
  "saldo": 15000,
  "saldoAtual": 15000,
  "updatedAt": "..."
}
```

`saldo` vem de `_panel_cache/finance_summary` (já existente).

**Flutter:**
- `church_dashboard_cache_service.dart` — leitura 1 doc
- `church_dashboard_current_service.dart` — prioriza `_dashboard_cache` antes de `_performance_cache`
- Mantém `_panel_cache/dashboard_summary` (rico, aniversariantes, avisos recentes)

---

## 4. Chat estilo WhatsApp

- `YahwehPerformanceV4.chatMessagesPageSize` = **30** (era 50)
- `ChurchChatService.recentMessagesQuery` + `loadOlderMessagesPage` — paginação já existente

---

## 5. Financeiro rápido

**Já existia:** `_panel_cache/finance_summary` com `saldoAtual` (CF `panelFinanceSummary.ts`)  
**Novo:** espelho em `_dashboard_cache/main.saldo` para abertura do painel

**Flutter:** `church_finance_aggregates_service.dart` lê `saldoAtual` — sem somar lançamentos no cliente

---

## 6. Publicação rascunho → upload → verificação → publicar

**Novo:** `church_publish_state.dart` — estados `draft`, `uploading`, `verifying`, `success`, `failed`

**Atualizado:**
- `publish_verification_base.dart` — `runPublishPipeline()` + `ChurchRepository.churchId`
- `avisos_publish_verification_service.dart` — `ensureDraft()` + sem tenant resolver

Falha mantém documento em `draft`/`failed` — conteúdo não se perde.

---

## 7. Carteirinhas — `cardVersion`

**Novo:** `church_document_version_service.dart`

Campos: `cardVersion`, `cardPdfPath`, `contentFingerprint`  
Só regenera quando fingerprint muda (integrar em `member_card_page` na próxima passagem).

---

## 8. Certificados — `pdfVersion` / `pdfPath`

**Atualizado:** `certificate_emitido_service.dart` grava `pdfVersion`, `pdfPath`, `contentFingerprint` na emissão.

---

## 9. Fotos de perfil — miniaturas

**Atualizado:** `media_image_variants_service.dart`

| Tier | Tamanho | Uso |
|------|---------|-----|
| `thumb_100` | 100px | Listas densas |
| `thumb_300` | 300px | Cards / listas |
| `full_1920` | 1920px | Detalhe / carteirinha |

`encodeProfileWebpTiers()` — novo helper para upload membro.

---

## 10. Modo offline

**Já configurado:** `firestore_app_config.dart`

| Plataforma | Persistência |
|------------|--------------|
| Android / iOS | `persistenceEnabled: true`, cache ilimitado |
| Web | IndexedDB desativado (evita `INTERNAL ASSERTION` Firestore JS); fallback long-polling + Hive |

Ativar persistence na Web exige validação em staging — risco conhecido documentado no código.

---

## 11. Loading infinito (regra 10s)

**Já existente + reforço:**
- `ChurchRepository.panelQueryTimeout` = 10s
- `ChurchPanelTimedFutureBuilder` — erro + «Tentar novamente»
- `ChurchPanelErrorBody` — padrão nos módulos

---

## 12. Diagnóstico do Sistema (ADM)

**Menu:** «Diagnóstico do Sistema» (antes «Saúde do Sistema»)  
**Página:** `system_firebase_health_page.dart`

**Novos checks em `system_health_service.dart`:**
- Firestore OK
- Storage OK
- FCM OK
- Cloud Functions OK
- Mercado Pago OK (`config/mercado_pago`)
- Tempo médio consultas (`SessionPerformanceMetrics.averageLastMs`)

---

## 13. Estrutura final adotada

### Firestore `igrejas/{churchId}/`

| Subcoleção | Status |
|------------|--------|
| membros, visitantes, departamentos, cargos | ✅ |
| avisos, eventos/noticias, chats | ✅ |
| finance (financeiro), fornecedores, patrimonio | ✅ |
| certificados_emitidos, escalas, notificacoes | ✅ |
| `_dashboard_cache`, `_panel_cache` | ✅ cache servidor |

### Storage `igrejas/{churchId}/`

configuracoes, membros, eventos, avisos, chat_media, patrimonio, certificados, cartao_membro, financeiro — via `ChurchStorageService`

---

## Arquivos alterados nesta sessão

### Cloud Functions
- `functions/src/cleanupOrphanFiles.ts` *(novo)*
- `functions/src/churchRootCountersMirror.ts`
- `functions/src/panelDashboardCache.ts`
- `functions/src/index.ts`

### Flutter
- `church_dashboard_cache_service.dart` *(novo)*
- `church_publish_state.dart` *(novo)*
- `church_document_version_service.dart` *(novo)*
- `church_repository.dart`, `church_dashboard_current_service.dart`
- `publish_verification_base.dart`, `avisos_publish_verification_service.dart`
- `certificate_emitido_service.dart`
- `media_image_variants_service.dart`, `yahweh_performance_v4.dart`
- `system_health_service.dart`, `session_performance_metrics.dart`
- `system_firebase_health_page.dart`, `admin_menu_lateral.dart`

### Infra
- `firestore.indexes.json`

---

## Próximos passos (deploy)

1. `firebase deploy --only functions:scheduledCleanupOrphanFiles` (+ triggers existentes se necessário)
2. `firebase deploy --only firestore:indexes`
3. Testar painel Web: dashboard abre com `_dashboard_cache` em <1s
4. Integrar `cardVersion` no fluxo PDF de `member_card_page.dart`
5. Aplicar `encodeProfileWebpTiers` em `member_profile_photo_update_service.dart`
