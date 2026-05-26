# Arquitetura de performance — Gestão YAHWEH V4

> **Multiplataforma (Android + iOS + Web):** ver [ARCHITECTURE_PERFORMANCE_MULTI_PLATFORM.md](./ARCHITECTURE_PERFORMANCE_MULTI_PLATFORM.md)

Objetivo: **não voltar a ficar lento** com muitos membros, mensagens, fotos, eventos e igrejas.

## Princípio: separar leitura de armazenamento pesado

| Camada | Responsabilidade |
|--------|------------------|
| **Firestore** | Metadados: título, datas, status, URLs, variantes (`imageVariants`, `photoThumb`) |
| **Storage** | Bytes: `.webp`, `.mp4`, `.aac` |
| **Cloud Functions** | Compressão, WebP, cache agregado, push |
| **Cache cliente** | Memória + disco (Firestore persistence, `flutter_cache_manager`, snapshots locais) |

**Nunca** gravar `base64` de fotos/vídeos em documentos Firestore (só previews locais / PDF legado).

## Coleções de cache (servidor)

Por igreja: `igrejas/{tenantId}/_performance_cache/`

| Documento | Atualização | Uso |
|-----------|-------------|-----|
| `public_feed` | CF `generatePublicFeedCache` (10 min) + após aviso/evento | Site público |
| `birthdays` | CF `generateBirthdayCache` (24 h) | Aniversariantes |
| `dashboard_summary` | CF `getChurchPanelSnapshot` / triggers membro | Painel ADM |

Cliente: `ChurchPerformanceCacheService`, `PanelDashboardSnapshotService`.

## Cliente Flutter (serviços globais)

| Serviço | Função |
|---------|--------|
| `FirestoreDocumentMemoryCache` | Evita `users/uid` repetido na mesma sessão |
| `UserSessionCacheService` | Perfil do utilizador logado |
| `StorageUploadQueueService` | Fila de uploads Storage (rede instável) |
| `MediaBatchUploadQueue` | Várias fotos em série (máx. 2 paralelas) |
| `ChurchTenantDashboardWarmupService` | Pré-carrega painel em paralelo ao entrar |
| `ChurchTenantOfflineWarmupService` | Aquece cache Firestore offline |
| `ProgressiveMediaResolver` | thumb → medium → full |
| `YahwehLocalSnapshotStore` | Snapshot JSON leve em disco (abre instantâneo) |
| `FirestoreWriteGuard` | Bloqueia base64 acidental em writes |

## Mídia: celular envia, servidor processa

1. Cliente: stub Firestore (`uploading`) + upload Storage (opcional WebP leve).
2. CF `optimizeImage`: variantes WebP + patch Firestore.
3. UI: `ProgressiveMediaResolver` mostra thumb primeiro.

## Chat estilo WhatsApp

- `limit(30)` + `startAfterDocument` — não carregar histórico inteiro.
- Um stream por thread; evitar dezenas de `StreamBuilder` na mesma tela.
- Estados: `sending` / `uploading` / `sent` (já no modelo).

## UI: lazy + progressivo

- Listas: `ListView.builder` / `GridView.builder`.
- Imagens: `SafeNetworkImage` + `memCacheWidth` + cache disco 30d/1000 objetos.

## Módulos lazy (shell)

- **Mobile:** só Dashboard montado; Chat/Eventos/Membros criados ao entrar no menu.
- **Desktop:** `IndexedStack` com cache por índice visitado.
- Ver `church_shell_lazy_module_policy.dart`.

## Dashboard pré-processado

- `igrejas/{tenant}/_performance_cache/dashboard_current` — KPIs (CF `panelDashboardCache`).
- Cliente: `ChurchDashboardCurrentService` + `PanelDashboardSnapshotService`.

## Rede adaptativa

- `NetworkMediaQualityPolicy` — Wi‑Fi 85% / 4G 70% / fraca 50% WebP; paralelismo de upload 3/2/1.

## Upload + background

- `StorageUploadQueueService` — retry em memória.
- `StorageUploadPersistenceService` — `pendingUploads` em disco (resume ao abrir app).
- `MuralPublishOutboxService` — posts interrompidos.

## Telemetria

- `YahwehTelemetry` + Crashlytics (upload, ecrãs).
- `YahwehPerformanceMonitor` — `performanceLogs` (amostra ecrãs > 800 ms).

## Chat presença (sem WebSocket extra)

- Firestore: `chat_presence`, `typing/{uid}` — tempo real nativo do SDK.

## CDN

- Firebase Storage já usa CDN global (GCS). CDN “própria” = Cloud CDN + bucket (custo extra).

## Roadmap (opcional)

- **Hive/Isar** para listas grandes offline — avaliar quando `_performance_cache` + Firestore offline não bastar.
- Consolidar estado do painel num único `ChangeNotifier` (menos streams duplicados).
- **Workmanager** para upload com app totalmente fechado (iOS restritivo).

## Deploy

```powershell
.\scripts\deploy_firebase_rules.ps1
cd functions && npm run build && firebase deploy --only functions:optimizeImage,functions:compressVideo,functions:generateBirthdayCache,functions:generatePublicFeedCache,functions:refreshPublicFeedCacheOnPost
```
