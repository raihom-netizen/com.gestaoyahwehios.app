# Mapeamento WISDOMAPP → Gestão YAHWEH — Mídia (foto, vídeo, áudio)

**Data:** 2026-06-28  
**Origem (referência):** `C:\WISDOMAPP`  
**Destino (implementação):** `C:\gestao_yahweh_premium_final\flutter_app`  
**Firebase destino:** `gestaoyahweh-21e23`  
**Objetivo:** mesmo padrão de inclusão de imagens/vídeos e gravação de áudio simples (estilo WhatsApp) em **todos** os módulos que usam mídia — de forma **cirúrgica**, sem reescrever o app inteiro.

**Docs irmãos (não duplicar):**
- `docs/PADRAO_MESTRE_WISDOMAPP_YAHWEH_TOTAL.md`
- `docs/MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`
- `docs/IMPLEMENTACAO_ANEXOS_AVISOS_EVENTOS_PATRIMONIO_FINANCEIRO.md`
- `docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md`

---

## 1. O que o usuário deve ver (paridade visual)

| Tela | Comportamento alvo |
|------|-------------------|
| **Chat Igreja** | Bolha local imediata; barra «A enviar imagem… 82%» / «A enviar áudio… 85%»; microfone ao lado do `+` |
| **Novo Aviso** | «Fotos anexadas (N)» + miniaturas com X; botão «Adicionar foto (N/5)»; compressão ~150 KB |
| **Novo Evento** | «Adicionar foto ou vídeo (N)»; progresso de vídeo com % |
| **Financeiro / Patrimônio / Membros** | Mesmo gate Firebase + compressão + barra de progresso antes de gravar Firestore |

**Erro a eliminar (screenshots):** `Firebase não inicializou (core/no-app)` ao publicar aviso/evento → ver **§6**.

---

## 2. Arquitetura de referência — WISDOMAPP

### 2.1 Contrato único (Controle Total)

```
Validar entrada
  → Comprimir (se imagem/vídeo)
  → Firebase Storage putData (+ metadata + cacheControl)
  → Obter downloadUrl + storagePath
  → Gravar Firestore UMA vez (com URLs)
  → UI: viewer seguro (Web-safe)
```

**Nunca:** doc Firestore «uploading» fantasma que fica com spinner infinito.  
**Nunca:** `Firestore.terminate()` em fluxo de publicar/anexar.

### 2.2 Arquivos-chave WISDOMAPP (copiar lógica, não copiar paths Storage)

| Papel | Arquivo WISDOMAPP |
|-------|-------------------|
| Comprovante / anexo genérico | `lib/utils/receipt_attachment_utils.dart` |
| Upload imagem curso/dica | `lib/services/course_video_image_service.dart` |
| Upload vídeo curso | `lib/services/course_video_file_service.dart` |
| Resolver URLs + resultado upload | `lib/utils/course_media_url_resolver.dart` |
| Compressão ocorrências | `lib/screens/ocorrencias_screen.dart` (`_compressImageInIsolate`) |
| Fila offline Storage | `lib/services/pending_storage_upload_service.dart` |
| Guard Web Firestore | `lib/utils/firestore_web_guard.dart` |
| Admin cursos (UI multi-foto) | `lib/screens/admin_cursos_tab.dart` |

### 2.3 Limites WISDOMAPP (referência numérica)

| Tipo | Limite |
|------|--------|
| Imagem curso | máx. 12 MB entrada → resize 1920 px, JPEG 88% |
| Comprovante financeiro | máx. 5 MB; PDF/PNG/JPG |
| Storage metadata | `contentType` explícito + `cacheControl: public, max-age=31536000, immutable` |

---

## 3. Arquitetura alvo — Gestão YAHWEH (já existe — consolidar)

### 3.1 Pipeline central (usar em TODOS os módulos novos)

| Camada | Arquivo | Função |
|--------|---------|--------|
| **Gate UI** | `lib/core/yahweh_module_media_gate.dart` | `ensureReadyForPick` / `ensureReadyForPublish` por módulo |
| **Publish strict** | `lib/services/transactional_media_publish_pipeline.dart` | compress → upload → resultado (Firestore no caller) |
| **Upload bytes** | `lib/services/yahweh_media_upload_pipeline.dart` | compressão por módulo, retry, fila, progresso |
| **Limites** | `lib/core/media_upload_limits.dart` | tetos foto/vídeo/áudio |
| **Áudio chat** | `lib/services/audio_service.dart` (`ChatAudioService`) | grava `.m4a` / web blob `voice_*.m4a` |
| **Envio chat mídia** | `lib/services/church_chat_media_send_service.dart` | Storage → Firestore **uma vez** |
| **Progresso UI chat** | `lib/ui/widgets/church_chat_pending_voice_bubble.dart` | «A enviar áudio... N%» |
| **Progresso UI chat** | `lib/ui/widgets/church_chat_upload_progress.dart` | imagem/vídeo |
| **Bootstrap Firebase** | `lib/core/firebase_bootstrap.dart` + `firebase_bootstrap_service.dart` | evita `core/no-app` |
| **Web guard** | `lib/utils/firestore_web_guard.dart` | paridade WISDOMAPP |

### 3.2 Dois modos de publish

| Modo | Módulos | Comportamento |
|------|---------|---------------|
| **strict** | Avisos, Eventos, Patrimônio, Financeiro, Membros, Cadastro | Sem doc até Storage OK |
| **optimisticLocal** | Chat Igreja | Bolha local + progresso + outbox se offline |

### 3.3 Storage canónico (gravar só aqui)

```
igrejas/{churchId}/
├── avisos/imagens/{postId}_{slot}.webp
├── eventos/imagens|videos|thumbs/{eventoId}_{slot}.webp
├── patrimonio/imagens|thumbs/{itemId}_foto0N.webp
├── financeiro/YYYY_MM/{lancamentoId}.{jpg|png|pdf}
├── chat_media/{threadId}/{messageId}_{kind}.{ext}
├── membros/{membroId}/foto_perfil.webp
└── configuracoes/logo_igreja.webp
```

**Legado (só leitura):** `noticias/`, `mural_avisos/`, `events/`, paths raiz antigos.

---

## 4. Matriz cirúrgica — todos os módulos com mídia

Legenda: ✅ padronizado | ⚠️ parcial (migrar caller) | 🔲 legado / duplicado

| # | Módulo | Tela / serviço principal | Pipeline alvo | Status | Ação cirúrgica |
|---|--------|--------------------------|---------------|--------|----------------|
| 1 | **Chat Igreja** | `church_chat_thread_page.dart` | `ChurchChatMediaSendService` + `ChatAudioService` | ✅ | Manter; garantir `ensureFirebaseReadyForChatSend()` antes de gravar |
| 2 | **Avisos (mural)** | `instagram_mural.dart` | `ChurchFeedLinearPublishService` / `TransactionalMediaPublishPipeline` | ⚠️ | Remover uploads diretos; usar gate + pipeline strict |
| 3 | **Eventos** | `events_manager_page.dart` + trecho mural | `evento_media_upload.dart` + pipeline | ⚠️ | Unificar com mural; um só fluxo de vídeo 720p |
| 4 | **Patrimônio** | `patrimonio_page.dart` | `patrimonio_publish_service.dart` | ⚠️ | `YahwehModuleMediaGate.ensureReadyForPublish` + repair URLs |
| 5 | **Financeiro** | `finance_comprovante_*` | `FinanceComprovantePublishService` | ✅ | Espelhar `ReceiptAttachmentUtils` (WISDOMAPP) |
| 6 | **Membros** | `members_page.dart` | `member_profile_photo_save_service.dart` | ✅ | Gate pick + publish + recover |
| 7 | **Cadastro igreja** | `igreja_cadastro_page.dart` | logo upload + bootstrap | ✅ | Logo galeria/câmera + commit upload |
| 8 | **Certificados** | `certificados_page.dart` | logo galeria | ✅ | Gate logo (Fase 2) |
| 9 | **Divulgação admin (Master)** | `admin_divulgacao_media_page.dart` | upload CMS | ✅ | Pick + upload gate `divulgacao` (menu Master → Divulgação) |
| 10 | **Marketing clientes (Master)** | `admin_marketing_clientes_tab.dart` | capa Storage | ✅ | Pick capa + upload gate (aba Clientes na Divulgação) |
| 11 | **Cadastro público membro** | `public_member_signup_page.dart` | `MemberProfilePhotoSaveService` | ✅ | Gate público (`requireAuth: false`) pick + publish + recover |
| 12 | **Site divulgação público** | `site_public_page.dart` | leitura galeria/vídeo | ✅ | `ensureReadyForPublicMedia` no init |
| 13 | **Site igreja público** | `church_public_page.dart` | leitura fotos/vídeos/logo | ✅ | `ensureReadyForPublicMedia` no init |
| 14 | **Finance smart input** | `finance_smart_input_page.dart` | OCR anexo | ⚠️ | Reutilizar comprovante publish |
| 15 | **Comentários mural** | `mural_comments_sheet.dart` | chat-like | ⚠️ | Usar compress chat profile |
| 16 | **Broadcast chat** | `church_chat_broadcast_sheet.dart` | chat send | ⚠️ | Mesmo send service |

### 4.1 Serviços a **deprecar** (não criar código novo aqui)

Migrar callers gradualmente para `YahwehMediaUploadPipeline` / `TransactionalMediaPublishPipeline`:

- `media_upload_service.dart` (legado)
- Uploads ad-hoc `FirebaseStorage.instance.ref` dentro de páginas UI
- Paths `noticias/` no Firestore ou Storage

---

## 5. Padrão UI — componentes reutilizáveis (criar/usar)

### 5.1 Botão «Adicionar foto» (avisos/eventos)

**Referência YAHWEH:** `instagram_mural.dart` ~L5336  
**Referência WISDOMAPP:** `admin_cursos_tab.dart` «Adicionar fotos»

```dart
// Padrão de label
'Adicionar foto (${existing + novas}/$max)'           // aviso
'Adicionar foto ou vídeo (${existing + novas + videos})' // evento
```

**Antes de abrir picker:**
```dart
if (!await YahwehModuleMediaGate.ensureReadyForPick(
  context: context,
  module: YahwehMediaModule.avisos, // ou .eventos
)) return;
```

### 5.2 Barra de progresso (chat)

**Textos canónicos (não inventar outros):**
- `'A enviar imagem... $pct%'`
- `'A enviar áudio... $pct%'`
- `'A enviar vídeo… $pct%'`

**Widgets:** `church_chat_pending_voice_bubble.dart`, `church_chat_upload_progress.dart`

### 5.3 Gravação de áudio (simples — microfone)

**Serviço:** `ChatAudioService` (`audio_service.dart`)

| Plataforma | Comportamento |
|------------|---------------|
| Android/iOS | `voice_{timestamp}.m4a` em temp dir |
| Web | blob `web_voice_{timestamp}` → bytes via `takeWebRecordingBytes()` |

**Fluxo UI (thread page):**
1. Tap/hold microfone → `startRecording()`
2. Soltar / enviar → `stopRecording(send: true)`
3. Criar `ChurchChatOutboundPending` kind=voice
4. `ChurchChatMediaSendService.send(...)` com `onProgress`

**Não** usar FilePicker para áudio no chat — só gravação in-app.

### 5.4 Compressão de imagens (feed vs chat)

| Perfil | Uso | Alvo |
|--------|-----|------|
| `MediaImageProfile.feed` | Avisos, eventos, patrimônio | ~150–300 KB WebP/JPEG |
| `MediaImageProfile.chat` | Chat fotos | mais leve, 1920 máx |

Implementação: `MediaService.compressImageBytes` via `YahwehMediaUploadPipeline.compressImageBytes`.

---

## 6. Correção `core/no-app` (prioridade P0)

Sintoma nas telas **Novo Aviso** / **Novo Evento** ao tocar Publicar.

### Checklist obrigatório em todo fluxo de publish

```dart
// 1) Antes de QUALQUER upload
await YahwehModuleMediaGate.ensureReadyForPublish(
  context: context,
  module: YahwehMediaModule.avisos, // ou .eventos
);

// 2) Relink Storage (Web especialmente)
await FirebaseBootstrapService.ensureStorageAlwaysLinked(
  refreshAuthToken: true,
);

// 3) Retry se core/no-app
catch (e) {
  if (msg.contains('core/no-app') || msg.contains('no-app')) {
    FirebaseBootstrapService.invalidateStorageUploadBootstrap();
    await FirebaseBootstrapService.ensureStorageAlwaysLinked(refreshAuthToken: true);
    // retry upload once
  }
}
```

**Já implementado parcialmente em:** `instagram_mural.dart` L5031–5037 — **replicar** em `events_manager_page.dart` nos handlers de publicar.

**main.dart:** `FirebaseBootstrap.ensureInitialized()` **antes** de `runApp` — não remover.

---

## 7. Plano de implementação cirúrgica (fases)

### Fase 0 — Inventário (1 h) ✅ este documento

### Fase 1 — P0 Publicar estável (1–2 dias)

1. `events_manager_page.dart`: wrap publish com `YahwehModuleMediaGate` + retry `core/no-app`
2. `instagram_mural.dart`: extrair `_publishAviso` / `_publishEvento` para `church_feed_linear_publish_service.dart` (já existe — eliminar duplicata inline)
3. Testar Web + Android: aviso 1 foto, evento 1 foto + 1 vídeo curto

### Fase 2 — Unificar uploads legados (2–3 dias)

Para cada linha ⚠️/🔲 da matriz §4:

1. Substituir `MediaUploadService` / upload direto por:
   ```dart
   await TransactionalMediaPublishPipeline.compressAndUpload(
     rawBytes: bytes,
     storagePath: canonicalPath,
     module: TransactionalMediaModule.strict,
     onProgress: (phase, p) => setState(() => _progress = p),
   );
   ```
2. Gravar Firestore com campos de `church_feed_media_storage_fields.dart`
3. Remover `mediaUploadState: uploading` persistente

### Fase 3 — Chat áudio/foto paridade WhatsApp (1 dia)

1. Confirmar microfone visível em `church_chat_thread_page.dart` input bar
2. Garantir `church_chat_pending_voice_bubble` para **todas** as pending voices
3. Teste: gravar 5 s → ver «A enviar áudio... N%» → mensagem `sent`

### Fase 4 — Módulos secundários (2 dias)

Certificados, marketing, comentários mural — gate + pipeline genérico.

### Fase 5 — Limpeza (1 dia)

- Deletar código morto de paths legados
- Atualizar `app_version.dart` changelog
- Deploy web `gestaoyahweh-21e23.web.app`

---

## 8. Schema Firestore — campos mínimos de mídia

Copiar em **avisos**, **eventos**, **patrimonio**, **finance**:

| Campo | Tipo | Notas |
|-------|------|-------|
| `imagemUrl` / `mediaUrl` | string | 1ª mídia HTTPS |
| `imagemStoragePath` / `storagePath` | string | path interno |
| `imagensUrls` | string[] | galeria |
| `imagensStoragePaths` | string[] | paralelo URLs |
| `videoUrl` | string | eventos |
| `videoStoragePath` | string | eventos |
| `mediaUploadState` | string | **`published`** ou omitir — nunca ficar `uploading` |

Chat (`messages`):

| Campo | Tipo |
|-------|------|
| `type` | `text` \| `image` \| `video` \| `audio` \| `file` |
| `mediaUrl` | string |
| `storagePath` | string |
| `fileName` | string (`voice_1782656949206.m4a`) |
| `durationMs` | int (áudio) |

---

## 9. Checklist por módulo (copiar na PR)

```markdown
- [ ] Pick chama YahwehModuleMediaGate.ensureReadyForPick
- [ ] Publish chama ensureReadyForPublish + ensureStorageAlwaysLinked
- [ ] Upload via YahwehMediaUploadPipeline ou TransactionalMediaPublishPipeline
- [ ] Firestore gravado UMA vez após Storage OK
- [ ] Path Storage canónico (§3.3)
- [ ] UI mostra progresso com texto canónico (§5.2)
- [ ] Retry core/no-app implementado
- [ ] Testado Web + Android
- [ ] Sem StreamBuilder pesado na mesma coleção durante write (Web)
```

---

## 10. Comandos úteis

```powershell
cd C:\gestao_yahweh_premium_final\flutter_app
flutter pub get
dart analyze lib/services/yahweh_media_upload_pipeline.dart lib/core/yahweh_module_media_gate.dart
flutter build web --release
```

Deploy (quando autorizado):
```powershell
cd C:\gestao_yahweh_premium_final
# script de deploy do projeto YAHWEH
```

---

## 11. Resumo executivo

| Item | WISDOMAPP | Gestão YAHWEH (alvo) |
|------|-----------|----------------------|
| Anexo financeiro | `ReceiptAttachmentUtils` | `FinanceComprovantePublishService` ✅ |
| Fotos feed/admin | `CourseVideoImageService` | `TransactionalMediaPublishPipeline` + WebP |
| Vídeo | `CourseVideoFileService` | `MediaService.compressVideo` + evento 720p |
| Áudio | (notificações only) | `ChatAudioService` + chat send ✅ |
| Progresso UI | SnackBar / inline | Bolha WhatsApp + % ✅ chat; estender avisos |
| Firebase init | single `initializeApp` | `FirebaseBootstrap` + gate ✅ |
| Offline | `PendingStorageUploadService` | `EcoFireResilientPublish` + outbox chat |

**Próximo passo:** ~~Fase 3~~ **Fases 1–3 + público/Master (2026-06-28):** avisos/eventos, património/financeiro/certificados, membros, cadastro igreja, divulgação admin + clientes Master, cadastro público membro, sites públicos. **Paridade Web (2026-06-28):** rules `public_church_slugs`, índices `ativo+publicado+createdAt`, polling Firestore web 12s (membros/mural/financeiro/património), cache público anónimo via `_performance_cache`, warmup web alinhado.

---

## 11. Paridade Web = Android = iOS (dados e velocidade)

| Camada | O quê | Arquivo |
|--------|--------|---------|
| **Rules** | `public_church_slugs` leitura pública (slug → churchId) | `firestore.rules` |
| **Índices** | `avisos/eventos`: `ativo + publicado + createdAt DESC` | `firestore.indexes.json` |
| **Leitura listas** | Plain-first + sort cliente (mesmo path `igrejas/{id}/…`) | `church_module_firestore_list_read.dart` |
| **Realtime web** | Polling 12s via `.watchSafe()` (substitui `snapshots()`) | `firestore_stream_utils.dart` |
| **Site público** | Visitante → `_performance_cache/public_feed` (sem `_panel_cache`) | `church_performance_cache_service.dart` |
| **Warmup login** | Web: light + heavy (6s) — membros 16/40 docs | `church_tenant_offline_warmup_service.dart` |

**Deploy obrigatório após alterar rules/índices:**
```powershell
cd C:\gestao_yahweh_premium_final
firebase deploy --only firestore:rules,firestore:indexes
```

---

*Documento gerado para implementação cirúrgica autorizada em `C:\gestao_yahweh_premium_final`.*
