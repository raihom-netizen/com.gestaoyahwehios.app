# Upload e mídia — padrão Controle Total (definitivo)

**Data:** 2026-07-12  
**Projeto:** `C:\gestao_yahweh_premium_final`  
**Firebase:** `gestaoyahweh-21e23`

---

## Regra única (Web = Android = iOS)

1. Picker → **bytes** (`Uint8List`) — **nunca** `putFile` na Web.
2. Comprimir no app (JPEG/WebP, limites em `media_upload_limits.dart`).
3. Upload Storage path canónico: `igrejas/{churchId}/{modulo}/…`
4. `getDownloadURL` → gravar Firestore **só** URL + `storagePath` + metadados.
5. Offline (mobile): fila **só em disco** — `StorageUploadPersistenceService` + `BackgroundUploadWorker.drainAll`.
6. **Proibido:** fila `igrejas/{tenant}/pending_uploads` no Firestore (`firestorePendingQueueEnabled = false`).

---

## Ponto único de upload (painel igreja)

| Camada | Arquivo |
|--------|---------|
| Facade | `lib/services/church_media_upload_facade.dart` |
| Core | `lib/core/church_central_storage_upload.dart` |
| putData | `lib/core/ecofire/direct_storage_url_publish.dart` |
| Paths | `lib/core/church_storage_layout.dart` |
| Fila disco | `lib/services/storage_upload_persistence_service.dart` |
| Drain | `lib/services/background_upload_worker.dart` |

**Todas as telas** (Avisos, Eventos, Membros, Patrimônio, Financeiro, Chat, Master) devem delegar à **facade** — não criar uploads soltos.

---

## Correções 2026-07-12

### Financeiro
- Removido fallback Web via Cloud Function `gyUploadFinanceComprovante` no catch.
- **Web e mobile** usam `_uploadComprovanteStorageCore` → `putData` directo (padrão CT).

### `ChurchDataService.uploadFile`
- Deixou de usar `putFile` cru.
- Lê bytes do `File` e chama `uploadBytes` (`putData`).

### Chat
- Erro retryável (timeout/rede) enfileira em `EcoFireResilientPublish.queueChatMedia` mesmo quando não está 100% offline — evita bolha sumir na Web.

### Migração total upload (2026-07-12 — sessão 2)

- **`upload_bytes_core`:** `uploadStoragePutFileWithRetry` → lê bytes → só `putData`.
- **`EcoFireEventVideoUpload`:** vídeos de evento via `putData` (sem `putFile`).
- **`MediaUploadService.uploadFileWithRetry`:** sempre bytes → `uploadBytesWithRetry`.
- **`UnifiedUploadService`:** removido atalho `putFile` por path local; vídeo/ficheiro via bytes.
- **Chat:** `church_chat_media_send_service` + `church_chat_service` → `putBytesFast`.
- **Eventos galeria:** `ChurchMediaUploadFacade` + `EcoFireEventVideoUpload`.
- **`PendingUploadsFirestoreService`:** writes/streams no-op quando `firestorePendingQueueEnabled = false`.
- **`ChurchMediaUploadFacade.uploadFromPipeline`:** delega a `YahwehMediaUploadPipeline` (sem `UnifiedUploadService` paralelo).

---- Módulo **100% local** — sem Firebase Storage.
- Pasta saída: `Utilitarios_GestaoYahweh` em documentos do app.
- Menu: índice **24** — `ChurchShellIndices.utilitarios`.
- Arquivos em `lib/ui/pages/utilitarios_*.dart` + `lib/services/utilitarios_*.dart`.

---

## Módulos com imagem — cobertura confirmada (2026-07-12)

| Módulo | Serviço / pipeline | Path Storage | Web + mobile |
|--------|-------------------|--------------|--------------|
| **Patrimônio** (até 5 fotos/slot) | `PatrimonioMediaUpload` → `ChurchCentralStorageUpload` | `igrejas/{id}/patrimonio/{itemId}/foto_N.jpg` | ✅ bytes → putData |
| **Yahweh Chat** (imagem/vídeo/áudio/doc) | `ChurchChatMediaSendService` + `ChurchChatMediaStorage.putBytesFast` | `igrejas/{id}/chat_media/…` | ✅ bytes → putData |
| **Chat** foto de perfil | `MemberProfilePhotoUpdateService` / sheet `church_chat_profile_photo_sheet` | `membros/{id}/foto_perfil.jpg` | ✅ |
| **Membros** — foto perfil | `MemberProfilePhotoSaveService` → `DirectStorageUrlPublish.uploadBytes` | path fixo `foto_perfil.jpg` | ✅ |
| **Cadastro público** membro | `MemberProfilePhotoSaveService.uploadStorageOnlyControleTotal` + `ChurchCanonicalMediaPublish.memberProfileFields` | idem membros | ✅ visitante anónimo OK |
| **Cadastro igreja** — foto gestor | `MemberProfilePhotoUpdateService.scheduleBackgroundPhotoUpload` (mesmo pipeline membros) | idem membros | ✅ |
| **Fornecedores** — comprovante compromisso | `FornecedorCompromissoComprovanteService` → `ChurchCentralStorageUpload.uploadFornecedorCompromissoComprovante` → `DirectStorageUrlPublish.uploadBytes` | `igrejas/{id}/fornecedores/{fornecedorId}/compromissos/{compId}_comprovante.{ext}` | ✅ |
| **Fornecedores** — lançamentos financeiros | `FinanceComprovanteAttachFlow.attachToLancamento` (mesmo pipeline módulo Financeiro) | `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext` | ✅ |

Nenhum destes módulos usa `ref.putFile` — picker entrega `Uint8List`, compressão no app, upload `putData`, Firestore só com URL + `storagePath`. **Sem** Cloud Function `gyUploadFinanceComprovante` no fluxo activo (legado só em `church_functions_service.dart`).

---

```
igrejas/{churchId}/avisos/imagens/…
igrejas/{churchId}/eventos/imagens|videos|thumbs/…
igrejas/{churchId}/membros/fotos/…
igrejas/{churchId}/patrimonio/{itemId}/…
igrejas/{churchId}/financeiro/YYYY_MM/{lancamentoId}.ext
igrejas/{churchId}/chat_media/{images|videos|audio|documents}/…
igrejas/{churchId}/configuracoes/…
```

Paths legados (`tenants/`, `members/`, raiz `noticias/`) — **write bloqueado** em `storage.rules`.

---

## Legado a não usar (remover chamadas novas)

- `MediaUploadService.putFile` directo (delegar facade)
- `UnifiedUploadService` paralelo
- `PendingUploadsFirestoreService.enqueue` com write Firestore
- `ChurchDataService.uploadFile` com `putFile` (corrigido)
- Financeiro Web só via CF (removido)

---

## Deploy

```powershell
cd C:\gestao_yahweh_premium_final
.\DEPLOY_WINDOWS.bat
# ou firebase deploy via script do projeto após build web
```

Regras: `firestore.rules`, `storage.rules`, `firestore.indexes.json` na raiz — comparar antes de regredir.

---

## Checklist pós-alteração

- [x] Código: zero `ref.putFile` em pipelines de upload (só bytes → putData)
- [ ] Aviso: foto publica e aparece no mural (web + mobile)
- [ ] Evento: galeria upload múltiplo
- [ ] Membro: foto perfil
- [ ] Financeiro: comprovante **na Web** sem CF
- [ ] Chat: imagem não some após timeout
- [ ] Patrimônio / Master divulgação: upload OK
- [ ] Utilitários: compactar PDF local sem rede
