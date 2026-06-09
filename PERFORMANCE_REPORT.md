# AUDITORIA DE PERFORMANCE DEFINITIVA — Gestão YAHWEH

**Data:** 2026-06-08  
**Escopo:** Firestore, Storage, Auth, Functions, Indexes, Cache, Streams, Consultas  
**Objetivo:** Web tão rápido quanto Android — **sem alterar layout de telas**

---

## 1. Diagnóstico executivo

| Sintoma relatado | Causa raiz identificada | Severidade |
|------------------|-------------------------|------------|
| Web lento vs Android/iOS | Múltiplos `snapshots()` + `StreamBuilder` no painel (IndexedStack) + scans sem limite em telas legadas | **Crítica** |
| `INTERNAL ASSERTION FAILED` (Firestore 11.x Web) | Listeners duplicados / paralelismo de `.get()` no bootstrap | **Crítica** |
| Dashboard pesado | Abertura consultava snapshot + KPIs + feeds em paralelo; alguns cards compartilhavam falha | **Alta** |
| Chat lento | Mensagens com limite 80; Web com `snapshots()` nativo | **Média** |
| Eventos/avisos inconsistentes | Índices compostos OK; patch CF parcial vs recompute completo | **Média** |
| `firestore.indexes.json` inválido | ~300 entradas malformadas em `fieldOverrides` (impediam deploy limpo) | **Alta** |

**Conclusão:** A lentidão Web **não é Flutter UI** — é infraestrutura: índices, consultas sem limite, dashboard sem cache agregado único, listeners duplicados e persistência Web desligada.

---

## 2. Firestore — padrões encontrados

### 2.1 Inventário (código `flutter_app/lib`)

| Padrão | Ocorrências aprox. | Risco |
|--------|-------------------|-------|
| `.snapshots()` | ~15 arquivos core + dashboard | Alto na Web |
| `StreamBuilder` | ~55 arquivos | Alto se no `build()` |
| `.listen()` / `StreamSubscription` | ~40 arquivos | Médio sem `dispose` |
| `.get()` **sem** `.limit()` | `departments_page`, `finance_page`, `frota`, admin | **Collection scan** |
| `Future.wait` paralelo (painel) | 3 → corrigido para cargas independentes | Médio |

### 2.2 Scans proibidos (exemplos reais)

```
departments_page.dart   → _membersCol.get()          (sem limite)
finance_page.dart       → col.get() / orderBy sem limit
frota/abastecimento     → veiculos().get() inteiro
members_page.dart       → 1× collection.get() legado
```

**Regra implementada:** `ChurchFirestoreAccess.listOnce` agora aplica `FirebasePerformanceLimits.capListLimit()` — teto por subcoleção.

### 2.3 Limites canónicos (paginação)

| Módulo | Limite 1ª página | Arquivo fonte |
|--------|------------------|---------------|
| Membros | 50 | `firebase_performance_limits.dart` |
| Eventos | 32 | idem |
| Avisos | 32 | idem |
| Chat threads | 40 | idem |
| Chat mensagens | **30** | idem + `church_chat_repository.dart` |
| Patrimônio | 40 | idem |
| Financeiro | 80 | idem |
| Fornecedores | 40 | idem |
| Dashboard direto | **máx. 32** | idem — preferir cache |

Lista completa: `flutter_app/lib/core/performance/firebase_performance_limits.dart`

### 2.4 Relatório runtime (consultas)

Implementado: `FirebaseQueryAudit` — registra módulo, path, ms, docs, limite.

```dart
import 'package:gestao_yahweh/core/performance/firebase_query_audit.dart';
debugPrint(FirebaseQueryAudit.toReportTable());
```

Integrado em `ChurchFirestoreAccess.listOnce` (camada de dados unificada).

---

## 3. Índices Firestore

### 3.1 Correção crítica

O arquivo `firestore.indexes.json` continha **entradas inválidas** dentro de `fieldOverrides` (formato de composite index, não field override). Isso impedia deploy consistente e podia mascarar índices faltantes.

**Ação:** arquivo saneado + novos índices de performance adicionados.

### 3.2 Índices exigidos (status)

| Consulta | Status |
|----------|--------|
| eventos + `startAt` / `data` | ✅ |
| avisos + `createdAt` | ✅ |
| chats + `lastMessageAt` | ✅ |
| membros + `NOME_COMPLETO` / `nome` | ✅ |
| membros + `DEPARTAMENTOS` (array) | ✅ |
| membros + `departamentoId` + nome | ✅ **novo** |
| membros + `cargoId` + nome | ✅ **novo** |
| finance + `data` + `tipo`/`type` | ✅ |
| patrimonio + `categoria` + `status` | ✅ |
| escalas + `date` | ✅ |
| agenda + `startTime` + `data` | ✅ **novo** |
| messages + `createdAt` DESC | ✅ fieldOverride |

**Deploy:** `firebase deploy --only firestore:indexes`

---

## 4. Regras Firestore

Arquivo: `firestore.rules` (completo, ~1840 linhas — pronto para deploy)

### Adição desta auditoria

```javascript
match /_dashboard_cache/{docId} {
  allow read: if isMaster() || canAccessTenant(id) || memberLinkedToTenant(id);
  allow write: if false;  // só Cloud Functions
}
```

Caches de leitura rápida (escrita só Admin SDK):

- `igrejas/{id}/_panel_cache/*` — já existia
- `igrejas/{id}/_dashboard_cache/main` — **regra adicionada**
- `igrejas/{id}/dashboard/home` — contadores leves

**Deploy:** `firebase deploy --only firestore:rules`

---

## 5. Cloud Functions (agregação — sem scan no cliente)

Fonte: `functions/src/index.ts` → compilado em `functions/lib/index.js`  
Entrada deploy: `functions/index.js` (wrapper)

### Funções de cache do painel (já em produção)

| Função / Trigger | Escreve em | Propósito |
|------------------|------------|-----------|
| `recomputePanelDashboardSummary` | `_panel_cache/dashboard_summary` | Snapshot painel |
| `writeDashboardCacheMain` | `_dashboard_cache/main` | **1 leitura na abertura** |
| `writePanelStatisticsCache` | `_panel_cache/statistics_summary` | KPIs / totais |
| `panelFinanceSummary` (CF) | `_panel_cache/finance_summary` | Gráfico financeiro |
| `membersDirectoryCache` | `_panel_cache/members_directory` | Lista membros instantânea |
| `onChurchMembroWritePanelDashboard` | trigger | Totais membros |
| `onChurchAvisoWritePanelDashboard` | patch rápido | Totais avisos |
| `onChurchNoticiaWritePanelDashboard` | patch rápido | Totais eventos |
| `scheduledRefreshPanelCaches` | cron | Refresh agendado |
| `churchPerformancePack` | Storage WebP | Compressão imagens |

**Build + deploy functions:**

```bash
cd functions && npm run build
firebase deploy --only functions
```

---

## 6. Cache offline

| Plataforma | Antes | Depois |
|------------|-------|--------|
| Android/iOS | `persistenceEnabled: true` | Mantido |
| Web | `persistenceEnabled: false` (40MB) | **`true` + 80MB cache** + long-polling |

Arquivo: `flutter_app/lib/core/firestore_app_config.dart`

Fallback automático se IndexedDB falhar (Hive + long-polling).

Complemento: `HiveLocalStore` para fila de sync silenciosa.

---

## 7. Storage — compressão e limites de mídia

| Módulo | Limite | Qualidade WebP |
|--------|--------|----------------|
| Eventos | 5 fotos, 1 vídeo 90s | 75–78% (`churchPerformancePack` CF: 70–80) |
| Avisos | 5 fotos | 78% |
| Patrimônio | 5 fotos/item | pipeline existente |
| Chat | 30 msgs/página | thumbs via CF |

Arquivos: `media_upload_limits.dart`, `evento_aviso_media_policy.dart`, `functions/src/churchPerformancePack.ts`

---

## 8. Streams — regras e guard

### Regra: 1 listener por tela

Implementado: `StreamListenerRegistry` — bloqueia listener duplicado por chave.

```dart
StreamListenerRegistry.register(
  key: 'dashboard_finance_$churchId',
  subscription: sub,
);
// dispose:
await StreamListenerRegistry.cancel(key);
```

### Web — chat

`ChurchChatRepository`: Web usa **polling 6s + `.get()`** em vez de `snapshots()` contínuo.

### Dashboard

`igreja_dashboard_moderno.dart`: 14× `StreamBuilder` — **não alterados nesta auditoria** (escopo proibido). Mitigação: caches `_panel_cache` + cargas independentes no bootstrap.

---

## 9. Sync UI (Web)

| Texto proibido | Status |
|----------------|--------|
| Sincronizando… | ✅ removido (`ConnectivityOfflineStrip` vazio) |
| Enviando para nuvem | ✅ não encontrado |
| Atualizando / Baixando / Normalizando | ✅ só em fluxos pontuais (certificados PDF) |

Feedback: `✔ Atualizado agora` / `⚠ Sem conexão` (`sync_feedback_listener.dart`)

---

## 10. Metas de tempo (sessão)

Fonte: `SessionPerformanceMetrics` — alvos já definidos:

| Módulo | Meta |
|--------|------|
| Dashboard | ≤ 1000 ms |
| Chat | ≤ 1000 ms |
| Eventos / Avisos | ≤ 1000 ms |
| Financeiro / Patrimônio | ≤ 1500 ms |
| Membros (lista cache) | ≤ 1000 ms (via `_panel_cache/members_directory`) |
| Login | ≤ 3000 ms |

Medição: `YahwehPerformanceMonitor.markScreenReady('igreja_dashboard')` + Saúde do Sistema.

---

## 11. Checklist de aceite pós-deploy

```
[ ] firebase deploy --only firestore:indexes,firestore:rules
[ ] cd functions && npm run build && firebase deploy --only functions
[ ] Web: abrir painel — 1 leitura _dashboard_cache/main + statistics_summary
[ ] Web: Configurações → Saúde do Sistema — contagens > 0
[ ] Web: sem INTERNAL ASSERTION em 5 min de uso
[ ] Android/iOS: paridade de abertura (< 2s painel com cache)
[ ] Chat: máx. 30 mensagens na 1ª carga
[ ] FirebaseQueryAudit: zero unlimited_scans na camada ChurchFirestoreAccess
```

---

## 12. Artefatos entregues (prontos para deploy)

| Arquivo | Status |
|---------|--------|
| `firestore.rules` | ✅ Atualizado (`_dashboard_cache`) |
| `firestore.indexes.json` | ✅ Saneado + índices performance |
| `functions/index.js` | ✅ Criado (wrapper → `lib/index.js`) |
| `functions/src/index.ts` | ✅ Já exporta CF de cache/agregação |
| `PERFORMANCE_REPORT.md` | ✅ Este documento |

### Código de performance (sem alterar layout)

| Arquivo | Função |
|---------|--------|
| `lib/core/performance/firebase_performance_limits.dart` | Limites paginação |
| `lib/core/performance/firebase_query_audit.dart` | Relatório consultas |
| `lib/core/performance/stream_listener_registry.dart` | Anti-listener duplicado |
| `lib/core/data/church_firestore_access.dart` | Enforcement de limites |
| `lib/core/firestore_app_config.dart` | Persistence Web ON |

---

## 13. Redução esperada de leituras

| Cenário | Antes (estimado) | Depois |
|---------|------------------|--------|
| Abertura dashboard Web | 15–40 reads paralelos | **2–4 reads** (cache) |
| Lista membros (camada nova) | até 120 docs | **máx. 50** |
| Chat thread | 80 msgs | **30** |
| Auditoria módulos | amostra 20 | **count()** agregado |

---

## 14. Pendências (fora do escopo «sem telas»)

Migrar ~50 páginas que ainda usam `lib/services/church_repository.dart` legado com `.get()` sem limite — **próxima fase**, módulo a módulo, via `ChurchRepository` + `FirebasePerformanceLimits`.

**Prioridade de migração por impacto:**

1. `finance_page.dart` — scans finance sem limite  
2. `departments_page.dart` — `_membersCol.get()`  
3. `igreja_dashboard_moderno.dart` — reduzir StreamBuilders (requer refactor controller, não layout)  
4. `events_manager_page.dart` / `instagram_mural.dart` — feeds  

---

*Gestão YAHWEH — Auditoria Performance v1.0 — infraestrutura implementada, telas intactas.*
