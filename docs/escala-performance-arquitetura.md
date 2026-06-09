# Escala e performance — Gestão YAHWEH (centenas/milhares de igrejas)

**Data:** 2026-06-08  
**Alvo:** Web = Android = iOS, `igrejas/{churchId}` único, carregamento rápido.

---

## Estrutura definitiva

```
Firestore: igrejas/{churchId}
  ├─ membros
  ├─ departamentos
  ├─ cargos
  ├─ eventos
  ├─ avisos
  ├─ chats
  ├─ patrimonio
  ├─ finance
  ├─ escalas
  ├─ certificados
  ├─ carteirinhas
  ├─ agenda
  ├─ configuracoes
  ├─ notificacoes
  └─ _panel_cache/          ← pré-processado (CF)
       ├─ dashboard_summary  (canónico)
       ├─ dashboard          (alias)
       ├─ members_directory
       └─ finance_summary

Storage: igrejas/{churchId}/
  ├─ configuracoes/   (logo_igreja.png)
  ├─ membros/
  ├─ eventos/
  ├─ avisos/
  ├─ chat/
  ├─ patrimonio/
  ├─ certificados/
  ├─ carteirinhas/
  └─ site_publico/
```

---

## 12 pilares de escala

| # | Pilar | Status no projeto |
|---|-------|-------------------|
| 1 | Dashboard pré-processado `_panel_cache` | ✅ CF `panelDashboardCache.ts` + leitura 1 doc |
| 2 | Contadores agregados | ✅ `ChurchAggregatedCountersService` + campos em `igrejas/{id}` |
| 3 | Lazy loading | ✅ Shell `_pageCache` + `TenantIntelligentPreload` por módulo |
| 4 | Paginação `limit(20)` | ✅ `YahwehPerformanceV4.defaultPageSize` |
| 5 | Imagens comprimidas | ✅ 1920/80%, perfil 512, logo 1024 (`church_image_profiles.dart`) |
| 6 | Cache logo em memória | ✅ `ChurchBrandService.preloadForSession` |
| 7 | Chat `limit(50)` | ✅ `chatMessagesPageSize = 50` |
| 8 | Índices Firestore | ✅ `firestore.indexes.json` expandido |
| 9 | PDF/Certificado no backend | 🟡 Parcial — validação CF; geração ainda no app |
| 10 | Web App Shell | ✅ Menu/layout imediato; dados depois |
| 11 | Diagnóstico permanente | ✅ Configurações → `ChurchPanelDiagnosticPage` |
| 12 | Fonte única `igrejas/{id}` | ✅ Flutter 0× `collection('tenants')` |

---

## Dashboard — 1 leitura

```
Login → Dashboard
         ↓
  readOnce: igrejas/{churchId}/_panel_cache/dashboard_summary
         (fallback: dashboard, dashboard_stats/summary)
         ↓
  Pinta: membros, aniversários, avisos, eventos, líderes
```

Cloud Function atualiza o cache quando membros/eventos/avisos mudam.

---

## Lazy loading

```
Login → resolve churchId (1×)
     → Dashboard (panel_cache)
     → Membros SÓ ao abrir Membros
     → Chat SÓ ao abrir Chat
```

`TenantIntelligentPreload.scheduleModuleForShellIndex` aquece Hive/cache do módulo.

---

## Paginação obrigatória

| Módulo | Limite inicial |
|--------|----------------|
| Membros, avisos, eventos UI | 20 |
| Chat mensagens | 50 |
| Financeiro lista | 250 + páginas 100 |
| Admin export | 500 (lote único) |

Proibido `limit(10000)` em listas UI.

---

## Próximos passos (CF / backend)

1. Espelhar contadores no doc raiz `igrejas/{id}` quando CF atualizar `_panel_cache`
2. Escrever alias `_panel_cache/dashboard` além de `dashboard_summary`
3. Cloud Function para gerar PDF certificado/carteirinha (não no dispositivo)
4. Deploy índices — pedido explícito do usuário

---

## Diagnóstico

**Configurações → Diagnóstico permanente** — churchId, paths, tempos, contadores, traces.

`SystemDiagnosticService.probe()` para automação/ADM.
