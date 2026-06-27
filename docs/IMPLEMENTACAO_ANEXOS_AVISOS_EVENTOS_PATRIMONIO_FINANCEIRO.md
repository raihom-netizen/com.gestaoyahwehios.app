# Implementação — Anexos padronizados (Avisos, Eventos, Patrimônio, Financeiro)

**Projeto destino:** GESTAOYAHWEH  
**ID Firebase:** `gestaoyahweh-21e23`  
**Número:** `157235497908`  
**Ambiente:** Produção  
**Hosting:** https://gestaoyahweh-21e23.web.app  
**Bucket Storage:** `gestaoyahweh-21e23.firebasestorage.app`  
**Igreja teste (Firestore):** `igrejas/igreja_o_brasil_para_cristo_jardim_goiano`

**Referência de origem (backup lógico):** WISDOMAPP (`C:\WISDOMAPP`) — módulos **Cursos/Vídeos/Dicas** e **Financeiro (comprovantes)** já estáveis na Web.

**Docs relacionados:**  
- [`FIREBASE_PADRAO_CONTROLE_TOTAL.md`](FIREBASE_PADRAO_CONTROLE_TOTAL.md)  
- [`MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`](MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md)  
- [`backup_wisdomapp/CURSOS_DICAS_FINANCEIRO_MANIFESTO_BKP.md`](backup_wisdomapp/CURSOS_DICAS_FINANCEIRO_MANIFESTO_BKP.md)

---

## 1. Objetivo

Padronizar **Eventos**, **Avisos**, **Patrimônio** e **Financeiro** no Gestão YAHWEH com o mesmo contrato que já funciona em:

| Referência YAHWEH (já OK) | Referência WISDOMAPP (backup) |
|---------------------------|-------------------------------|
| `MemberProfilePhotoSaveService` | `CourseVideoImageService` + upload Storage |
| `FinanceComprovantePublishService` | `ctUploadReceiptToStorage` + `ReceiptAttachmentUtils` |
| `ChurchChatMediaSendService` | `CourseVideoFileService` + player protegido |
| `ChurchFeedLinearPublishService` | `AdminCourseFirestoreBridge` + CF Admin SDK |

**Contrato único (Controle Total):**

```
Validar formulário
  → Bootstrap Firebase (auth + Storage)
  → Upload Storage (path canónico)
  → Verificar metadata Storage
  → Gravar Firestore UMA vez (com URL + storagePath)
  → Visualizar com SafeNetworkImage / viewer sheet (Web-safe)
```

**Proibido na Web durante gravação:** `snapshots()` concorrente na mesma coleção que está sendo escrita.

---

## 2. Diagnóstico — por que os módulos quebram hoje

| Módulo | Sintoma típico | Causa raiz |
|--------|----------------|------------|
| **Avisos / Eventos** | Publica mas não aparece; mídia quebrada; `permission-denied` Web | Legado `noticias/` + paths Storage antigos; monólitos (`events_manager_page.dart`, `instagram_mural.dart`); regras Firestore duplicadas em `eventos/` |
| **Patrimônio** | Fotos no Storage sem URL no Firestore | Publicação parcial; falta `repairFromStorage`; permissões mais restritas que mural |
| **Financeiro** | Comprovante some ou não abre na Web | Upload desacoplado do doc; CORS na visualização; naming `finance/` vs `financeiro/` |

---

## 3. Árvore canónica GESTAOYAHWEH (única verdade)

### 3.1 Firestore

```
igrejas/{churchId}/
├── avisos/{avisoId}           ← mural avisos
├── eventos/{eventoId}         ← mural eventos
├── patrimonio/{itemId}        ← bens + manutencoes/, transferencias/
├── finance/{lancamentoId}     ← lançamentos (UI: «financeiro»)
├── finance_logs/              ← auditoria append-only
├── contas/                    ← contas bancárias
├── categorias_receitas|despesas/
└── _dashboard_cache/          ← contadores (avisosCount, etc.)
```

### 3.2 Storage

```
igrejas/{churchId}/
├── avisos/imagens/{postId}_{slot}.webp
├── eventos/imagens|videos|thumbs/{eventoId}_{slot}.webp
├── patrimonio/imagens|thumbs/{itemId}_foto0N.webp
└── financeiro/YYYY_MM/{lancamentoId}.{jpg|png|pdf}
```

**Legado (só leitura — NÃO gravar novos):**

- Firestore: `noticias/`, `mural_avisos/`, `events/`
- Storage raiz: `noticias/{tenantId}/`, `patrimonio/{tenantId}/`, `comprovantes/` (paralelo)

---

## 4. Schema Firestore padronizado (campos de anexo)

Todos os módulos com mídia devem gravar **os mesmos conceitos** (nomes adaptados por módulo):

### 4.1 Aviso (`igrejas/{id}/avisos/{avisoId}`)

| Campo | Tipo | Obrigatório | Uso |
|-------|------|-------------|-----|
| `titulo`, `texto` | string | sim | Conteúdo |
| `imagemUrl` | string | não | 1ª imagem (HTTPS) |
| `imagemStoragePath` | string | não | Path interno |
| `imagensUrls` | string[] | não | Galeria (até 10) |
| `imagensStoragePaths` | string[] | não | Paths galeria |
| `thumbnailUrl` | string | não | Miniatura lista |
| `mediaUploadState` | string | sim | `published` \| `uploading` \| `failed` |
| `published` | bool | sim | Visível no mural |
| `authorUid`, `authorEmail` | string | sim | Auditoria |
| `createdAt`, `updatedAt` | Timestamp | sim | Ordenação |

### 4.2 Evento (`igrejas/{id}/eventos/{eventoId}`)

| Campo | Tipo | Obrigatório | Uso |
|-------|------|-------------|-----|
| `titulo`, `descricao`, `dataInicio`, `dataFim` | mixed | sim | Evento |
| `capaUrl`, `capaStoragePath` | string | não | Capa |
| `imagensUrls`, `imagensStoragePaths` | array | não | Galeria |
| `videoUrl`, `videoStoragePath` | string | não | Vídeo MP4 |
| `youtubeVideoId`, `youtubeUrl` | string | não | YouTube embed |
| `source` | string | não | `upload`, `youtube`, `image_link` |
| `mediaUploadState` | string | sim | Estado upload |
| `published` | bool | sim | Visível |
| `createdAt`, `updatedAt` | Timestamp | sim | |

### 4.3 Patrimônio (`igrejas/{id}/patrimonio/{itemId}`)

| Campo | Tipo | Obrigatório | Uso |
|-------|------|-------------|-----|
| `nome`, `categoria`, `valor`, `local` | mixed | sim | Bem |
| `foto01Url`…`foto04Url` | string | não | Até 4 fotos |
| `foto01StoragePath`…`foto04StoragePath` | string | não | Paths |
| `photoUploadState` | string | sim | `published` \| `uploading` |
| `createdAt`, `updatedAt` | Timestamp | sim | |

### 4.4 Financeiro (`igrejas/{id}/finance/{lancamentoId}`)

| Campo | Tipo | Obrigatório | Uso |
|-------|------|-------------|-----|
| `tipo`, `valor`, `descricao`, `data` | mixed | sim | Lançamento |
| `comprovanteUrl`, `comprovanteLink` | string | não | URL HTTPS (alias) |
| `comprovanteStoragePath` | string | não | Path Storage |
| `comprovanteMimeType`, `comprovanteFileName` | string | não | Viewer |
| `hasComprovante` | bool | sim | Flag rápida |
| `comprovanteUploadState` | string | sim | `published` \| `uploading` |
| `createdAt`, `updatedAt` | Timestamp | sim | |

> **Equivalência WISDOMAPP Financeiro:** campo nested `receipt` → no YAHWEH campos flat `comprovante*` (já implementado em `FinanceComprovantePublishService`).

---

## 5. Fluxos de implementação (copiar padrão)

### 5.1 Fluxo A — Mural com imagens (Avisos / Eventos)

**Modelo:** `ChurchFeedLinearPublishService` + `AvisoStrictPublishService` / `EventoStrictPublishService`

```
1. churchId = ChurchRepository.churchId(hint)
2. docRef = avisos|eventos.doc()  // ID gerado antes do Storage
3. Para cada imagem:
     path = ChurchStorageLayout.avisosImagem(churchId, docId, slot)
     bytes = YahwehMediaUploadPipeline.compressWebp(bytes)
     url = StorageService.putData(path, bytes)
     verificar metadata (ChurchStorageMetadataVerify)
4. Montar payload Firestore (urls + storagePaths + mediaUploadState: published)
5. runFirestorePublishWithRecovery(() => docRef.set(payload))
6. _reloadAvisos() / _reloadEventos()  // Future, NÃO snapshots() no admin
7. Distribuição background: push, site, agenda
```

**Arquivos a usar (já existem):**

| Papel | Ficheiro |
|-------|----------|
| Orquestrador | `lib/services/church_feed_linear_publish_service.dart` |
| Aviso strict | `lib/services/aviso_strict_publish_service.dart` |
| Evento strict | `lib/services/evento_strict_publish_service.dart` |
| Verificação | `lib/services/aviso_publish_verification_service.dart` |
| Load (cache-first) | `lib/services/church_avisos_load_service.dart` |
| Load eventos | `lib/services/church_eventos_load_service.dart` |
| UI avisos | `lib/ui/widgets/instagram_mural.dart` |
| UI eventos | `lib/ui/pages/events_manager_page.dart` |
| Visualização | `lib/ui/widgets/safe_network_image.dart` |

**Correções obrigatórias:**

- [ ] Remover gravações diretas `FirebaseFirestore.instance` dentro de `lib/ui/pages/events_manager_page.dart`
- [ ] Unificar regras Firestore — eliminar bloco duplicado `match /eventos/{docId}` em `firestore.rules`
- [ ] Admin/listagem Web: trocar `snapshots()` por `Future` + botão recarregar (como Wisdom `admin_cursos_tab`)
- [ ] Fallback legado `noticias/` apenas na **leitura**; nunca na gravação
- [ ] Delete: chamar `FirebaseStorageCleanupService` antes de apagar doc

### 5.2 Fluxo B — Patrimônio (4 fotos)

**Modelo:** `PatrimonioStrictPublishService` + `MemberProfilePhotoSaveService`

```
1. docRef = patrimonio.doc()
2. Para foto 1..4:
     path = ChurchStorageLayout.patrimonioImagem(churchId, itemId, n)
     upload → url + storagePath
3. photoUploadState = published
4. runFirestorePublishWithRecovery → set doc
5. Se Storage OK mas Firestore incompleto: PatrimonioPublishVerificationService.repairFromStorage()
```

**Arquivos:**

| Papel | Ficheiro |
|-------|----------|
| Publish | `lib/services/patrimonio_publish_service.dart` |
| Fachada strict | `lib/services/patrimonio_strict_publish_service.dart` |
| Repair | `lib/services/patrimonio_publish_verification_service.dart` |
| UI | `lib/ui/pages/patrimonio_page.dart` |
| Fila offline | `EcoFireResilientPublish.queuePatrimonioPublish` |

**Correções obrigatórias:**

- [ ] Extrair lógica de upload da `patrimonio_page.dart` → serviço strict único
- [ ] Garantir `canWritePatrimonioStorage` no utilizador de teste
- [ ] Viewer: `SafeNetworkImage` + zoom (photo_view) — nunca `Image.network` cru

### 5.3 Fluxo C — Financeiro (comprovante PDF/imagem)

**Modelo WISDOMAPP:** `ctUploadReceiptToStorage` (CF) + `ReceiptAttachmentUtils` + `AnexoViewerScreen`  
**Modelo YAHWEH atual:** `FinanceComprovantePublishService` (Storage directo)

```
Fase 1 (já existe — consolidar):
1. saveLancamentoFirst() → doc finance/ sem comprovante
2. FinanceComprovantePublishService.uploadAndAttach()
     path = igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext
3. Patch Firestore: comprovanteUrl, comprovanteStoragePath, hasComprovante
4. finance_comprovante_viewer_sheet.dart → PDF ou imagem

Fase 2 (Web instável — opcional, copiar Wisdom):
5. CF gyUploadFinanceComprovante (base64 → Admin SDK Storage + Firestore)
6. Cliente chama CF em kIsWeb; mobile mantém upload directo
```

**Arquivos:**

| Papel | WISDOMAPP (backup) | YAHWEH (destino) |
|-------|-------------------|------------------|
| Pick/validação | `lib/utils/receipt_attachment_utils.dart` | criar `lib/utils/finance_comprovante_utils.dart` (espelho) |
| Upload | `functions/index.js` → `ctUploadReceiptToStorage` | `finance_comprovante_publish_service.dart` |
| Viewer Web | `lib/screens/anexo_viewer_web.dart` | `finance_comprovante_viewer_sheet.dart` |
| Viewer mobile | `lib/screens/anexo_viewer_screen.dart` | idem |
| Write tx | `lib/services/transaction_save_service.dart` | `finance_lancamento_write_service.dart` |

**Regra Web (WISDOMAPP):** na Web, `await` upload comprovante **antes** de notificar listeners (evita assert Firestore).

---

## 6. Cloud Functions recomendadas (GESTAOYAHWEH)

Criar em `functions/src/` (TypeScript) espelhando Wisdom:

| Função | Quando usar | Path validado |
|--------|-------------|---------------|
| `gyAdminUpsertFeedPost` | Web instável ao publicar aviso/evento | `igrejas/{churchId}/avisos\|eventos/{id}` |
| `gyUploadFinanceComprovante` | Web instável no comprovante | `igrejas/{churchId}/finance/{id}` |
| `gyAdminDeleteFeedPosts` | Exclusão em lote admin | ids[] |

**Template CF (Node — adaptar de WISDOMAPP `functions/index.js`):**

```javascript
// requireChurchStaff(uid, churchId) — gestor, tesoureiro, permissão mural
// decodeAdminFirestoreValue(v) — __DELETE__, _tsMs
exports.gyUploadFinanceComprovante = onCall(async (req) => {
  // 1. auth + validar path igrejas/{churchId}/finance/{lancamentoId}
  // 2. base64 → Buffer (max 15 MB)
  // 3. upload Storage igrejas/{churchId}/financeiro/YYYY_MM/{id}.ext
  // 4. merge Firestore comprovante* + hasComprovante
  // 5. return { ok, comprovanteUrl, storagePath }
});
```

**Bridge Flutter (copiar de Wisdom):**

```
lib/utils/admin_feed_firestore_bridge.dart   ← encode FieldValue → CF
lib/services/functions_service.dart            ← gyUploadFinanceComprovante()
```

---

## 7. Regras Firebase — alinhamento

### 7.1 Firestore (`firestore.rules`)

Verificar blocos em `igrejas/{id}/`:

```
avisos/     → canWriteMuralFeed(churchId)
eventos/    → canWriteMuralFeed(churchId)   // UNIFICAR — remover match duplicado
patrimonio/ → canWritePatrimonio(churchId)
finance/    → canWriteFinance(churchId)
```

**Deploy:**

```powershell
cd C:\gestao_yahweh_premium_final
.\scripts\deploy_firebase_rules.ps1
```

### 7.2 Storage (`storage.rules`)

```
igrejas/{id}/avisos/**      read: public; write: membro igreja, ≤120 MB
igrejas/{id}/eventos/**     read: public; write: membro igreja, ≤120 MB
igrejas/{id}/patrimonio/**  read: membro; write: canWritePatrimonioStorage
igrejas/{id}/financeiro/**  read: membro; write: staff financeiro, ≤15 MB
```

---

## 8. Visualização padronizada (pós-gravação)

| Tipo | Componente YAHWEH | Notas Web |
|------|---------------------|-----------|
| Imagem mural | `SafeNetworkImage` | Nunca `Image.network` para URL Firebase |
| Galeria aviso/evento | `photo_view` + paths resolvidos | Pré-fetch `getDownloadURL` se só tiver `storagePath` |
| Vídeo evento | player dedicado (embed web) | `controlsList=nodownload` (copiar Wisdom `course_video_embed_web.dart`) |
| PDF comprovante | `finance_comprovante_viewer_sheet.dart` | URL directa — não `http.get` (CORS) |
| Patrimônio 4 fotos | `StableStorageImage` / `SafeNetworkImage` | Thumbs em `patrimonio/thumbs/` |

**Resolver URL (padrão único):**

```dart
Future<String> resolveMediaUrl({
  required String? httpUrl,
  required String? storagePath,
}) async {
  final u = (httpUrl ?? '').trim();
  if (u.startsWith('http')) return u;
  final p = (storagePath ?? '').trim();
  if (p.isEmpty) return '';
  return FirebaseStorage.instance.ref(p).getDownloadURL();
}
```

---

## 9. Plano de execução (fases)

### Fase 0 — Backup e baseline (1 dia)

- [ ] Copiar manifesto Wisdom → [`backup_wisdomapp/CURSOS_DICAS_FINANCEIRO_MANIFESTO_BKP.md`](backup_wisdomapp/CURSOS_DICAS_FINANCEIRO_MANIFESTO_BKP.md)
- [ ] Export Firestore teste: `igreja_o_brasil_para_cristo_jardim_goiano` (avisos, eventos, patrimonio, finance)
- [ ] Correr `.\scripts\auditoria_acessos_firestore_storage.ps1`

### Fase 1 — Financeiro (referência mais madura) (2–3 dias)

- [ ] Consolidar `FinanceComprovantePublishService` como único ponto de upload
- [ ] Garantir viewer Web PDF/imagem
- [ ] (Opcional Web) CF `gyUploadFinanceComprovante`
- [ ] Teste: criar lançamento + anexar PDF + abrir comprovante (Web + Android)

### Fase 2 — Avisos (2–3 dias)

- [ ] Refactor `instagram_mural.dart`: publicação só via `AvisoStrictPublishService`
- [ ] Listagem admin Web: Future + reload (sem snapshot durante write)
- [ ] Limpar cache keys `mural_avisos_legacy_*` após migração
- [ ] Teste: publicar aviso com 3 fotos → aparece no mural → abrir imagem

### Fase 3 — Eventos (3–4 dias)

- [ ] Extrair publish de `events_manager_page.dart` → `EventoStrictPublishService`
- [ ] Unificar regras Firestore `eventos/`
- [ ] Suporte vídeo MP4 + YouTube (paths `eventos/videos/`)
- [ ] Teste: evento com capa + vídeo + confirmação presença

### Fase 4 — Patrimônio (2–3 dias)

- [ ] Upload 4 fotos via pipeline strict único
- [ ] Botão «Reparar do Storage» no admin se `photoUploadState != published`
- [ ] Delete com cleanup Storage
- [ ] Teste: cadastrar bem com 4 fotos → inventário → relatório

### Fase 5 — Aceite 3 plataformas

- [ ] DEBUG CHURCH → publicar prova em Web, Android, iOS
- [ ] Preencher tabela secção 10 do [`MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`](MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md)
- [ ] Deploy: `.\scripts\deploy_web_hosting.ps1` + rules

---

## 10. Checklist de aceite por módulo

| Teste | Avisos | Eventos | Patrimônio | Financeiro |
|-------|--------|---------|------------|------------|
| Criar com anexo | ☐ | ☐ | ☐ | ☐ |
| Ver anexo após F5 | ☐ | ☐ | ☐ | ☐ |
| Editar / trocar anexo | ☐ | ☐ | ☐ | ☐ |
| Excluir doc + Storage | ☐ | ☐ | ☐ | ☐ |
| Web (Ctrl+F5) | ☐ | ☐ | ☐ | ☐ |
| Android | ☐ | ☐ | ☐ | ☐ |
| iOS | ☐ | ☐ | ☐ | ☐ |
| Offline mobile (fila) | ☐ | ☐ | ☐ | ☐ |

---

## 11. Comandos deploy

```powershell
cd C:\gestao_yahweh_premium_final

# Regras
.\scripts\deploy_firebase_rules.ps1

# Functions (após implementar gyUploadFinanceComprovante)
cd functions
npm run build
cd ..
firebase deploy --only functions:gyUploadFinanceComprovante,functions:gyAdminUpsertFeedPost

# Web
.\scripts\deploy_web_hosting.ps1
# ou DEPLOY_WINDOWS.bat
```

---

## 12. Mapa rápido Wisdom → YAHWEH

| Conceito Wisdom | Path Wisdom | Equivalente YAHWEH |
|-----------------|-------------|-------------------|
| Curso/Dica | `course_videos/{id}` | `igrejas/{id}/eventos/{id}` (eventos) ou `avisos/{id}` (avisos curtos) |
| Storage curso | `wisdomapp/course_videos/{id}/photo_*` | `igrejas/{id}/eventos/imagens/` |
| Comprovante | `users/{uid}/receipts/{txId}/` | `igrejas/{id}/financeiro/YYYY_MM/{id}.ext` |
| CF gravação Web | `ctAdminUpsertCourseVideo` | `gyAdminUpsertFeedPost` (a criar) |
| CF comprovante | `ctUploadReceiptToStorage` | `gyUploadFinanceComprovante` (a criar) |
| Admin reload | `_reloadCourseVideos()` Future | `_reloadAvisos()` / `_reloadEventos()` Future |
| Viewer | `AnexoViewerScreen` + web embed | `finance_comprovante_viewer_sheet.dart` |

---

*Documento gerado em 2026-06-26. Origem backup: WISDOMAPP `C:\WISDOMAPP`. Destino: GESTAOYAHWEH `C:\gestao_yahweh_premium_final`.*
