# Gestão YAHWEH — Arquitetura definitiva de performance (Android + iOS + Web)

Objetivo: **rápido nas três plataformas ao mesmo tempo**, sem otimizar só uma e prejudicar outra.

Política central no código: `flutter_app/lib/core/yahweh_performance_v4.dart`  
Camada de dados: `flutter_app/lib/data/yahweh_data_repository.dart`  
Observabilidade: `flutter_app/lib/services/yahweh_observability.dart`

---

## Mapa das 15 camadas

| # | Camada | Estado | Implementação principal |
|---|--------|--------|-------------------------|
| 1 | Repository (UI → Repo → Cache → Firestore) | **Parcial** | `YahwehPublicFeedRepository`, `YahwehPanelRepository`; migração gradual das telas |
| 2 | Cache local | **Ativo** | `YahwehLocalSnapshotStore` (SharedPreferences) + Firestore offline |
| 2b | Isar/Hive | **Roadmap** | Só se snapshots + offline não bastarem |
| 3 | Imagens WebP q70 + variantes | **Ativo** | `MediaImageVariantsService`, CF `optimizeImage` |
| 4 | Vídeo H264/AAC 720p + thumb | **Ativo** | Cliente Android; iOS envia bruto leve → CF `compressVideo` |
| 5 | Storage `tenants/…` | **Ativo** | `ChurchStorageLayout` |
| 6 | Upload background | **Ativo** | `FeedMediaPublishService`, `MuralFastPublishService`, filas Storage |
| 7 | Cloud Functions | **Ativo** | `functions/src/churchPerformancePack.ts` |
| 8 | Chat 30 msgs + `startAfter` | **Ativo** | `church_chat_service.dart` |
| 9 | Site público lazy + 20 itens | **Ativo** | `SliverList` + limite V4; cache instantâneo no mural |
| 10 | Firestore persistence | **Ativo** | `firestore_app_config.dart` + `main.dart` |
| 11 | Menos streams duplicados | **Roadmap** | Shell lazy; consolidar painel num notifier |
| 12 | Pré-carregamento ao entrar | **Ativo** | `ChurchTenantDashboardWarmupService` |
| 13 | Retry + fila local | **Ativo** | `StorageUploadQueueService`, `StorageUploadPersistenceService` |
| 14 | iOS blindado | **Ativo** | `ios_publish_image_pipeline.dart`, upload serial, memória |
| 15 | Monitoramento | **Ativo** | Crashlytics + Analytics + `firebase_performance` |

---

## 1) Camada de dados (Repository)

```
UI (Widget)
    ↓
Provider / estado local (futuro: Riverpod onde fizer sentido)
    ↓
YahwehPublicFeedRepository / YahwehPanelRepository
    ↓
YahwehLocalSnapshotStore  →  ChurchPerformanceCacheService  →  Firestore
```

**Regra:** telas novas e refactors usam repositório; não abrir `FirebaseFirestore.instance` direto no `build()`.

---

## 2) Cache local

| Dado | Bucket snapshot | Cache servidor |
|------|-----------------|----------------|
| Feed público | `public_feed` | `_performance_cache/public_feed` |
| Aniversariantes | `birthdays` | `_performance_cache/birthdays` |
| Dashboard KPIs | — | `_performance_cache/dashboard_current` |
| Perfil sessão | — | `FirestoreDocumentMemoryCache` |

Warmup grava snapshots: `ChurchTenantDashboardWarmupService`.

---

## 3) Imagens

| Variante | Tamanho | Uso |
|----------|---------|-----|
| `thumb_200` | 200px | Chat, listas |
| `medium_800` | 800px | Feed, site |
| `full_1920` | 1920px | Tela cheia |

Qualidade WebP padrão: **70** (`YahwehPerformanceV4.webpQuality`).  
iOS na publicação: pipeline leve **60 / 1080** antes do upload (`IosPublishImagePipeline`).

---

## 4) Vídeos

- Android: transcode 720p no aparelho quando necessário.
- iOS: evita transcode/thumb local; CF processa após Storage.
- Player: `SafeNetworkImage` / `ChurchMediaDisplay` (nunca `Image.network` direto em URLs Storage na web).

---

## 5–7) Storage, upload background, Cloud Functions

Fluxo publicação:

1. Utilizador toca **Publicar**
2. Stub Firestore (`publishState: uploading`)
3. UI fecha
4. `StorageUploadQueueService` / outbox envia ficheiros
5. CF `optimizeImage` / `compressVideo` atualiza variantes e cache

Deploy functions: ver `docs/ARCHITECTURE_PERFORMANCE_V4.md`.

---

## 8) Chat estilo WhatsApp

- `limit(30)` na thread ativa
- `startAfterDocument` ao carregar histórico
- Upload de mídia com fila e estados `sending` / `uploading` / `sent`

---

## 9) Site público

- Mural: `SliverList` lazy (equivalente a `ListView.builder` em slivers)
- **20** publicações por stream (`YahwehPerformanceV4.publicFeedPageSize`)
- Abertura: skeleton a partir de `YahwehPublicFeedRepository.readInstantFeed`

---

## 10) Firestore offline

`configureFirestoreForOfflineAndSpeed()` em `main.dart` após Firebase init.  
Web: `synchronizeTabs` quando suportado pelo SDK.

---

## 11–12) Streams e pré-carregamento

Hoje: warmup paralelo no shell (`ChurchTenantDashboardWarmupService`).  
Meta: um stream agregado por módulo + `ChangeNotifier` no painel (roadmap).

---

## 13) Retry automático

`StorageUploadQueueService` + persistência `pendingUploads` + outbox mural.  
Até **3** tentativas por upload crítico (`MediaUploadService`).

---

## 14) iOS blindado

- Comprimir **antes** de qualquer `readAsBytes` da original
- Máx. **5** fotos / **1** vídeo por post
- Upload **serial** no iOS
- `if (mounted) setState`
- `imageCache.clear()` após lote pesado

---

## 15) Monitoramento

| Ferramenta | Uso |
|------------|-----|
| **Crashlytics** | Crashes e erros de upload (`main.dart`, `YahwehTelemetry`) |
| **Analytics** | Site público + `panel_screen_view` via `YahwehObservability` |
| **Performance Monitoring** | Traces HTTP e operações (`YahwehObservability.traceAsync`) |
| **YahwehPerformanceMonitor** | Debug + amostra Firestore `performanceLogs` (>800 ms) |

---

## Resultados estimados (com rede normal)

| Métrica | Antes | Depois (meta) |
|---------|-------|----------------|
| Abertura app | 4–10 s | 1–2 s (cache + warmup) |
| Upload foto (percebido) | 3–8 s | 0,5–1 s (stub + background) |
| Upload vídeo | 15–40 s | 2–5 s (iOS leve + CF) |
| Chat | lento | paginação 30 + thumb |
| Site | pesado | skeleton instantâneo + 20 itens |

---

## Compatibilidade multiplataforma

| Otimização | Web | Android | iOS |
|------------|-----|---------|-----|
| WebP variantes | ✓ | ✓ | ✓ (publicação leve) |
| Upload paralelo | 3–4 | 3–4 | **1** |
| CF pós-upload | ✓ | ✓ | ✓ |
| Firestore offline | limitado | ✓ | ✓ |
| Performance SDK | — | ✓ | ✓ |

---

## Próximos passos (opcional)

1. Migrar mais ecrãs para `Yahweh*Repository`
2. Paginação cursor no mural público (`fetchAvisosPage` + «carregar mais»)
3. Isar só se listas offline > 500 docs por igreja
4. `flutterfire configure` após adicionar `firebase_performance` (build iOS/Android)

Ver também: [ARCHITECTURE_INSTANT_UX.md](./ARCHITECTURE_INSTANT_UX.md), `.cursor/rules/yahweh-performance-v4.mdc`, `imagens-rede-firebase.mdc`.
