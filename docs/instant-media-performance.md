# Mídia instantânea — Gestão YAHWEH

Arquitetura para Chat, Patrimônio, Financeiro, Eventos e Avisos com percepção de velocidade em Web, Android e iOS.

## Prioridade máxima (3 ganhos ~80%)

1. **Upload paralelo** — `FeedPostMediaUpload.uploadParallel` + `Future.wait` em patrimônio/chat.
2. **Thumbnails automáticas** — `thumb_300` / `medium_800` / `full_1920` (WebP) via `ChurchInstantUploadPipeline` e `MediaImageVariantsService`.
3. **Dashboard + Financeiro** — `_panel_cache/dashboard_summary` e `finance_summary` com campos agregados (`saldoAtual`, `receitasMes`, …).

## Fluxo de upload (regra de ouro)

```
Seleciona mídia → Upload Storage imediatamente → storagePath → Firestore
```

O Firestore **nunca** guarda bytes. URLs são resolvidas na hora (`getDownloadURL` / resolver dinâmico).

## Storage

```
igrejas/{churchId}/
  avisos/imagens/
  eventos/imagens/ + eventos/videos/
  chat_media/
  patrimonio/imagens/ + patrimonio/thumbs/
  membros/
  configuracoes/
```

`cacheControl: public, max-age=31536000` em todos os uploads (`media_upload_service.dart`).

## Compressão automática

| Tipo   | Limite   | Ação                          |
|--------|----------|-------------------------------|
| Imagem | > 3 MB   | Comprimir antes do upload     |
| Vídeo  | > 50 MB  | Recomprimir (eventos/chat)    |
| Evento | 90 s max | 720p H.264 ~2 Mbps AAC        |

## Módulos

| Módulo      | Lista carrega        | Detalhe carrega   |
|-------------|----------------------|-------------------|
| Avisos      | `thumbStoragePath`   | `imageStoragePath`|
| Eventos     | thumb + galeria lazy | full / vídeo      |
| Patrimônio  | `fotoPrincipalThumbPath` | `fotoPrincipalPath` + `gallery` |
| Chat        | `limit(50)` + paginação | anexo full     |
| Financeiro  | `_panel_cache`       | lançamentos paginados |

## Cloud Functions

- `panelFinanceSummary` — agregados mensais + espelho em `igrejas/{id}.financeAggregates`
- `panelDashboardCache` — `dashboard_summary`
- `optimizeImage` — variantes no mobile (1 upload → CF gera thumbs)

## Cache local agressivo

`ChurchPanelLocalCache` + `ChurchBootstrapService`: cadastro, logo, departamentos, cargos, configurações.

## Arquivos-chave (Flutter)

- `church_instant_upload_pipeline.dart`
- `church_feed_media_storage_fields.dart`
- `church_feed_linear_publish_service.dart`
- `media_image_variants_service.dart`
- `church_finance_aggregates_service.dart`
- `entity_image_fields.dart` (`FeedImageFields`, `PatrimonioImageFields`)
