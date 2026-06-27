# Backup de referência — WISDOMAPP (Cursos, Vídeos, Dicas, Financeiro)

**Origem:** `C:\WISDOMAPP`  
**Projeto Firebase origem:** `wisdomapp-b9e98`  
**Destino de implementação:** `C:\gestao_yahweh_premium_final` (GESTAOYAHWEH / `gestaoyahweh-21e23`)  
**Doc principal:** [`../IMPLEMENTACAO_ANEXOS_AVISOS_EVENTOS_PATRIMONIO_FINANCEIRO.md`](../IMPLEMENTACAO_ANEXOS_AVISOS_EVENTOS_PATRIMONIO_FINANCEIRO.md)

Este manifesto lista **todos os arquivos estáveis** do WISDOMAPP que servem de backup lógico para padronizar anexos no Gestão YAHWEH. Não é cópia binária — é inventário para portar padrões.

---

## A. Módulo Cursos / Vídeos / Dicas

### A.1 Firestore

| Coleção / Doc | Campos principais |
|---------------|-------------------|
| `course_videos/{docId}` | `title`, `description`, `bodyText`, `type` (`curso`\|`dica`), `source`, `published`, `validityMode`, `expiresAt`, `youtubeVideoId`, `mp4Url`, `mp4Urls[]`, `imageUrl`, `imageUrls[]`, `linkUrl`, `thumbnailUrl`, `authorUid`, `createdAt`, `updatedAt` |
| `app_config/wisdom_courses_module` | `heroTitle`, `heroMessage`, `sectionTitle`, `emptyMessage`, `showTipsSection` |

### A.2 Storage

```
wisdomapp/course_videos/{docId}/video_{index}_{timestamp}.{mp4|webm|mov}
wisdomapp/course_videos/{docId}/photo_{index}_{timestamp}.{jpg|png|webp}
```

Limites: vídeo 250 MB; imagem 12 MB (otimizada para ~1920px JPEG q88).

### A.3 Cloud Functions

| Função | Ficheiro | Papel |
|--------|----------|-------|
| `ctAdminUpsertCourseVideo` | `functions/index.js` ~L1699 | Grava `course_videos` via Admin SDK (Web estável) |
| `ctAdminDeleteCourseVideos` | `functions/index.js` ~L1732 | Batch delete até 40 docs |
| `ctAdminSaveWisdomCoursesModuleConfig` | `functions/index.js` ~L1756 | Config módulo |
| `courseVideosExpiryCleanupScheduled` | `functions/courseVideosExpiryCleanup.js` | Purga expirados 04:00 Brasília |

Helpers CF: `decodeAdminFirestoreValue`, `requireCourseContentEditor`.

### A.4 Flutter — Admin (publicar)

| Ficheiro | Papel |
|----------|-------|
| `lib/screens/admin_cursos_tab.dart` | UI admin completa |
| `lib/utils/admin_course_firestore_bridge.dart` | Serializa FieldValue → CF |
| `lib/services/functions_service.dart` | `adminUpsertCourseVideo`, `adminDeleteCourseVideos` |
| `lib/services/course_video_file_service.dart` | Upload MP4 |
| `lib/services/course_video_image_service.dart` | Upload capa/fotos + otimização |
| `lib/utils/course_media_url_resolver.dart` | Monta campos Firestore pós-upload |
| `lib/utils/course_video_validity.dart` | Validade permanente/prazo |
| `lib/services/course_media_storage_cleanup.dart` | Delete Storage na exclusão |
| `lib/services/course_videos_expiry_cleanup_service.dart` | Purga cliente |
| `lib/utils/firestore_retry.dart` | Retry + terminated |
| `lib/utils/firestore_web_guard.dart` | Recovery Web |

### A.5 Flutter — App (visualizar)

| Ficheiro | Papel |
|----------|-------|
| `lib/screens/cursos_videos_screen.dart` | Módulo Cursos no app |
| `lib/widgets/course_media_preview.dart` | Galeria/thumbnails |
| `lib/widgets/course_video/course_module_media_panel.dart` | Painel inline |
| `lib/widgets/course_video/course_video_watch_screen.dart` | Player estilo YouTube |
| `lib/widgets/course_video/course_video_embed_web.dart` | Embed Web (nodownload) |
| `lib/widgets/course_video/course_protected_image.dart` | Imagem protegida |
| `lib/widgets/course_video/course_protected_image_web.dart` | Web: bloqueia save/right-click |
| `lib/models/wisdom_courses_module_config.dart` | Config textos hero |

### A.6 Regras

| Ficheiro | Resumo |
|----------|--------|
| `firestore.rules` | `course_videos`: read signedIn; write `canEditPublicContent()` |
| `storage.rules` | `wisdomapp/course_videos/**`: read signedIn; write admin + ≤250 MB |

### A.7 Padrão crítico Web (copiar para YAHWEH)

1. **Upload Storage no cliente** (admin autenticado)
2. **Gravação Firestore via Cloud Function** (Admin SDK) — não `docRef.set()` directo na Web admin
3. **Listagem admin:** `Future.get(Source.server)` + `_reloadCourseVideos()` — **sem** `snapshots()` durante write
4. **App consumidor:** `snapshots()` OK (só leitura)

---

## B. Módulo Financeiro (comprovantes)

### B.1 Firestore

| Coleção / Doc | Campos principais |
|---------------|-------------------|
| `users/{uid}/transactions/{txId}` | `type`, `amount`, `category`, `description`, `status`, `date`, `effectiveDate`, `financeAccountId`, `hasReceipt`, `receipt`, `createdAt`, `updatedAt` |
| `users/{uid}/finance_accounts/{id}` | `presetId`, `productType`, `nickname`, `sortOrder` |
| `finance_month_buckets/{yyyy-MM}` | `netPaid`, `updatedAt` |
| `finance_account_month_buckets/{yyyy-MM}` | `netByAccount`, `updatedAt` |

**Objeto `receipt` (nested):**

```json
{
  "storagePath": "users/{uid}/receipts/{txId}/{ts}_{nome}",
  "downloadUrl": "https://firebasestorage.googleapis.com/...",
  "name": "comprovante.pdf",
  "originalName": "comprovante.pdf",
  "mimeType": "application/pdf",
  "size": 123456,
  "createdAt": "<Timestamp>"
}
```

### B.2 Storage

```
users/{uid}/receipts/{txId}/{timestamp}_{nomeSanitizado}.{pdf|png|jpg}
users/{uid}/reports/finance/{filename}   # PDFs gerados servidor
```

Limite: **5 MB** (`ReceiptAttachmentUtils.maxBytes`).

### B.3 Cloud Functions

| Função | Ficheiro | Papel |
|--------|----------|-------|
| `ctUploadReceiptToStorage` | `functions/index.js` ~L2226 | base64 → Storage → merge `receipt` no doc |
| `financeMonthBucketsOnTransactionWrite` | `functions/financeMonthBuckets.js` | Trigger agregados |
| `ctFinancePeriodTotals` | `functions/index.js` | Totais período |
| `ctGenerateFinancePdfServer` | `functions/index.js` | PDF extrato servidor |

### B.4 Flutter — Upload + Save

| Ficheiro | Papel |
|----------|-------|
| `lib/utils/receipt_attachment_utils.dart` | Pick, validação PDF/PNG/JPG ≤5 MB |
| `lib/utils/receipt_file_reader.dart` | Leitura bytes multi-plataforma |
| `lib/services/transaction_save_service.dart` | Salva tx + await upload Web |
| `lib/services/functions_service.dart` | `uploadReceiptToStorage()` |
| `lib/screens/novo_lancamento_page.dart` | UI novo lançamento |
| `lib/screens/finance_screen.dart` | Tela financeiro |
| `lib/utils/finance_transactions_hub.dart` | Notifier pós-mutação |

### B.5 Flutter — Visualização

| Ficheiro | Papel |
|----------|-------|
| `lib/utils/anexo_viewer_helper.dart` | Abre bottom sheet |
| `lib/screens/anexo_viewer_screen.dart` | PDF/imagem inline |
| `lib/screens/anexo_viewer_web.dart` | Web: URL directa (sem http.get CORS) |
| `lib/widgets/finance_transaction_list_tile.dart` | Botão «ver comprovante» |

### B.6 Regras

| Ficheiro | Resumo |
|----------|--------|
| `firestore.rules` | `users/{userId}/{**}`: owner ou admin |
| `storage.rules` | `users/{uid}/receipts/**`: write premium + ≤5 MB; CF usa Admin SDK |

### B.7 Padrão crítico Web (copiar para YAHWEH Financeiro)

1. **Comprovante via Cloud Function** (`base64` → servidor → Storage + Firestore merge)
2. **Web:** `await` upload antes de notificar UI/listeners
3. **Viewer Web:** embed URL Firebase directamente — **não** `http.get` (CORS)
4. **Campos flat no YAHWEH:** `comprovanteUrl` + `comprovanteStoragePath` (equivalente ao nested `receipt`)

---

## C. Script para copiar arquivos de referência (opcional)

Executar no PowerShell **a partir da raiz YAHWEH** para copiar snapshot de leitura:

```powershell
$src = "C:\WISDOMAPP"
$dst = "C:\gestao_yahweh_premium_final\docs\backup_wisdomapp\sources"

$files = @(
  "lib\utils\admin_course_firestore_bridge.dart",
  "lib\utils\receipt_attachment_utils.dart",
  "lib\screens\anexo_viewer_screen.dart",
  "lib\screens\anexo_viewer_web.dart",
  "lib\services\course_video_image_service.dart",
  "lib\services\course_video_file_service.dart",
  "lib\utils\course_media_url_resolver.dart",
  "lib\utils\firestore_web_guard.dart",
  "lib\utils\firestore_retry.dart",
  "functions\index.js"
)

New-Item -ItemType Directory -Force -Path $dst | Out-Null
foreach ($f in $files) {
  $from = Join-Path $src $f
  if (Test-Path $from) {
    $toDir = Join-Path $dst (Split-Path $f -Parent)
    New-Item -ItemType Directory -Force -Path $toDir | Out-Null
    Copy-Item $from (Join-Path $dst $f) -Force
    Write-Host "OK $f"
  } else {
    Write-Host "SKIP (nao existe) $f"
  }
}
```

> Os ficheiros copiados são **referência somente leitura** — adaptar paths `users/` → `igrejas/{churchId}/` antes de usar no YAHWEH.

---

## D. Equivalência directa para GESTAOYAHWEH

| WISDOMAPP | GESTAOYAHWEH |
|-----------|--------------|
| `course_videos/` | `igrejas/{id}/eventos/` + `avisos/` |
| `wisdomapp/course_videos/` | `igrejas/{id}/eventos/` + `avisos/imagens/` |
| `users/{uid}/transactions/` | `igrejas/{id}/finance/` |
| `users/{uid}/receipts/` | `igrejas/{id}/financeiro/YYYY_MM/` |
| `receipt.downloadUrl` | `comprovanteUrl` |
| `receipt.storagePath` | `comprovanteStoragePath` |
| `ctAdminUpsertCourseVideo` | `gyAdminUpsertFeedPost` (a implementar) |
| `ctUploadReceiptToStorage` | `gyUploadFinanceComprovante` (a implementar) |
| `AdminCourseFirestoreBridge` | `AdminFeedFirestoreBridge` (a implementar) |

---

## E. Export Firestore (backup dados produção YAHWEH)

Para backup da igreja teste antes de refatorar:

```powershell
# Requer firebase-tools + login
firebase firestore:export gs://gestaoyahweh-21e23.firebasestorage.app/backups/pre-refactor-$(Get-Date -Format yyyyMMdd) `
  --project gestaoyahweh-21e23
```

Ou export parcial via Console Firebase → Firestore → Import/Export, filtrando coleções:

- `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/avisos`
- `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/eventos`
- `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/patrimonio`
- `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/finance`

---

*Manifesto backup WISDOMAPP — 2026-06-26*
