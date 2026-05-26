# Gestão YAHWEH — UX instantânea (percepção + escala)

Velocidade deixa de ser só técnica: **arquitetura + UX + escalabilidade**.

## 1. Modo instantâneo (offline-first leve)

| Camada | Implementação |
|--------|----------------|
| Local | `YahwehLocalSnapshotStore` (SharedPreferences) + Firestore offline |
| API | `YahwehOfflineInstant` — gravar local → UI → sync background |
| Chat | `ChurchChatInstantSendService` — stub `sending` antes da rede |
| Avisos/eventos | `FeedMediaPublishService` + `MuralFastPublishService` — stub `uploading` |
| Perfil | variantes + cache RAM (`MemberProfilePhotoBytesCache`) |
| Membros | `MembersDirectorySnapshotService` + snapshot `membros_search` |

**Roadmap:** Isar/Hive quando listas > 500 docs/igreja e outbox complexo.

## 2. Sincronização inteligente

`YahwehIncrementalSync` — `lastSyncDate` por `tenantId` + bucket:

- `fetchDelta()` — query `updatedAt > lastSync` (menos tráfego que full reload)
- `markSyncedNow()` após pull bem-sucedido

Buckets sugeridos: `avisos`, `eventos`, `membros`, `chat_threads`, `public_feed`.

## 3. Web — bundle inicial

| Script | Renderer |
|--------|----------|
| `scripts/deploy_web_hosting.ps1` | CanvasKit (mídia HD, padrão atual) |
| `scripts/deploy_web_hosting_html_dom.ps1` | HTML/DOM (menor bundle) |
| `scripts/deploy_web_hosting_skwasm.ps1` | **Skwasm** (experimental — browsers modernos) |

Módulos lazy: `church_shell_lazy_module_policy.dart` (mobile só Dashboard montado).

## 4. Menos reconstruções

- Preferir `ValueListenableBuilder` + `GlobalUploadProgress` (já no upload strip)
- `ListenableBuilder` no painel (aniversariantes)
- **Roadmap:** Riverpod/Selector em ecrãs com 10+ `StreamBuilder`

## 5. Componentes reutilizáveis (`lib/ui/widgets/app_design/`)

| Widget | Uso |
|--------|-----|
| `AppAvatar` | Fotos circulares |
| `AppCachedImage` | URLs Storage → `SafeNetworkImage` |
| `AppCard` | Cartões do painel |
| `AppButton` | Botão primário |
| `AppSkeleton` | Shimmer de carregamento |

## 6. Upload com indicador real

`GlobalUploadProgress` — ex.: **Imagem 2/5 — 72%**

- `startBatch(itemLabel:, totalItems:)`
- `updateBatch(currentItem:, totalItems:, slotProgress01:)`
- UI: `AsyncUploadProgressStrip` (`displayLabel`)

## 7. Busca local primeiro

`YahwehLocalSearchService`:

- `searchMembersLocal()` — diretório + snapshot `membros_search`
- `searchFeedLocal()` — snapshots `public_feed` / avisos

Membros: lista já filtra `_directoryCache` quando disponível.

## 8. Push silencioso → cache

`YahwehPushCacheRefresh` — ligado em `FcmService` / `onMessage`:

- Data `cacheRefresh` / `silent` / tipo `chat`
- Aquece `members_directory`, `public_feed` em disco

Payload FCM exemplo (data-only):

```json
{
  "silent": "true",
  "tenantId": "…",
  "cacheRefresh": "chat"
}
```

## Já existente (não duplicar)

- Skeleton: `YahwehSkeletonLoading`, `ChurchPanelLoadingBody`
- Observabilidade: `AnalyticsService`, `PerformanceService`, `CrashlyticsService`
- Repository: `YahwehPublicFeedRepository`, `YahwehPanelRepository`

Ver também: [ARCHITECTURE_PERFORMANCE_MULTI_PLATFORM.md](./ARCHITECTURE_PERFORMANCE_MULTI_PLATFORM.md)
