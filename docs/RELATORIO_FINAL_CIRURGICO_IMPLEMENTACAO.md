# Relatório final — implementação cirúrgica (Gestão YAHWEH Premium)

**Data:** 2026-06-02  
**Build:** `11.2.295+1730`  
**Escopo:** performance, chat, publicação, uploads, dashboard, sessão, Firestore/Storage — **sem** alterar layout, design, navegação, telas ou fluxos de negócio visíveis.

---

## 1. Arquivos analisados

### Chat (mapa pedido → caminho real)

| Nome pedido | Caminho |
|-------------|---------|
| `church_chat_service.dart` | `flutter_app/lib/services/church_chat_service.dart` |
| `church_chat_instant_send_service.dart` | `flutter_app/lib/services/church_chat_instant_send_service.dart` |
| `church_chat_media_upload_coordinator.dart` | `flutter_app/lib/services/church_chat_media_upload_coordinator.dart` |
| `church_chat_uploads_service.dart` | `flutter_app/lib/services/church_chat_uploads_service.dart` |
| `church_chat_media_outbox_service.dart` | `flutter_app/lib/services/church_chat_media_outbox_service.dart` |
| `church_chat_outbound_pending.dart` | `flutter_app/lib/services/church_chat_outbound_pending.dart` |
| `church_chat_pending_media_cache.dart` | `flutter_app/lib/services/church_chat_pending_media_cache.dart` |
| `church_chat_stuck_cleanup_service.dart` | `flutter_app/lib/services/church_chat_stuck_cleanup_service.dart` |
| `church_chat_local_conversations.dart` | `flutter_app/lib/services/church_chat_local_conversations.dart` |
| `church_media_publish_policy.dart` | `flutter_app/lib/services/church_media_publish_policy.dart` |
| `fast_media_publish_bootstrap.dart` | `flutter_app/lib/services/fast_media_publish_bootstrap.dart` |
| `church_public_feed_service.dart` | `flutter_app/lib/services/church_public_feed_service.dart` |
| `church_tenant_dashboard_doc_service.dart` | `flutter_app/lib/services/church_tenant_dashboard_doc_service.dart` |
| `church_performance_cache_service.dart` | `flutter_app/lib/services/church_performance_cache_service.dart` |

### Publicação / upload / login / bootstrap

- `feed_media_publish_fast.dart`, `feed_media_publish_service.dart`, `mural_fast_publish_service.dart`
- `firebase_upload_policy.dart`, `unified_upload_service.dart`, `media_upload_service.dart`
- `persistent_auth_session_service.dart`, `login_page.dart`, `app_finalize_bootstrap.dart`
- `church_publish_flow_log.dart`, `yahweh_flow_log.dart`, `yahweh_catch_log.dart`
- `igreja_dashboard_moderno.dart`, `panel_dashboard_snapshot_service.dart` (leitura UI ainda parcial)

### Avisos / eventos (nomes pedidos não existem)

- **Não há** `notice_service`, `publish_notice`, `notice_repository`.
- Canónico: `MuralFastPublishService` + `FeedMediaPublishService` + `FeedMediaPublishFast`.

---

## 2. Arquivos corrigidos (esta onda + sessões anteriores)

| Área | Ficheiros |
|------|-----------|
| Chat texto | `church_chat_service.dart`, `church_chat_instant_send_service.dart` |
| Chat recovery | `church_chat_auto_recovery_service.dart` (**novo**), `app_finalize_bootstrap.dart` |
| Warm duplicado | `fast_media_publish_bootstrap.dart`, `login_preferences.dart` (reset ao trocar conta) |
| Upload | `unified_upload_service.dart` |
| Dashboard | `church_tenant_dashboard_doc_service.dart` |
| Logs | `yahweh_flow_log.dart`, `church_publish_flow_log.dart` |
| Publicação | `feed_media_publish_fast.dart`, `mural_fast_publish_service.dart`, `events_manager_page.dart` |
| Login | `persistent_auth_session_service.dart`, `login_page.dart` |
| Índices | `firestore.indexes.json` |
| Versão | `app_version.dart`, `pubspec.yaml`, `web/version.json` |
| Foto membro Firestore-first | `member_profile_photo_update_service.dart`, `members_page.dart`, `church_chat_profile_photo_sheet.dart` |
| Status unificado | `entity_publish_status.dart` |
| Regra Cursor | `.cursor/rules/estabilidade-performance-modulos-criticos.mdc` |

### Onda +1730 (bloco crítico utilizador)

- **Foto perfil:** cadastro grava primeiro (`photoUploadState: uploading`); upload em `scheduleBackgroundPhotoUpload` (Membros + Chat).
- **Status:** `creating` → `uploading` → `published` / `error` em avisos/eventos; patrimônio alinhado a `EntityPublishStatus`.
- **Logs:** `MEMBER PHOTO START/SUCCESS/ERROR`, `EVENT SUCCESS/ERROR`, `NOTICE SUCCESS/ERROR`, `UPLOAD SUCCESS`.

---

## 3. Serviços duplicados encontrados

| Camada | Função | Estado |
|--------|--------|--------|
| `church_chat_media_outbox_service` | Retoma pós-crash (SharedPreferences) | **Mantido** — necessário offline |
| `church_chat_uploads_service` | Espelho `chat_uploads` no Firestore | **Mantido** — UI progresso; recovery fecha órfãos |
| `church_chat_outbound_pending` | Fila memória envio | **Mantido** — dedupe por `clientMessageId` |
| `pending_uploads` (Firestore global) | Fila antiga | **Desligado** (`firestorePendingQueueEnabled = false`) |
| Warm Storage | `FastMediaPublishBootstrap` + chamadas no chat/mural | **Dedupe** — 1× por sessão, timeout 60s |
| Contadores painel | Streams RT + `_panel_cache` + `dashboard/home` | **Em migração** — SOT `dashboard_stats` + `dashboard/home` |

---

## 4. Filas removidas / desativadas

- Fila Firestore `pending_uploads` para avisos/eventos/chat — **não usada** em publicação nova.
- Texto no chat — **sem** outbox nem Cloud Function; gravação directa Firestore.
- `ImmediateMediaWarm.drainInFlight` — cap **~2s** (antes ~40s bloqueava «Publicar»).
- Warm Storage repetido por envio — **sessão única** em `FastMediaPublishBootstrap`.

---

## 5. Gargalos removidos

- Publicar aviso/evento à espera de upload + warm longo.
- Retry eventos com upload-before-Firestore (~170 linhas legado removidas).
- `GoogleSignIn.signInSilently` / express login no cold start.
- Texto chat: fase `sending` + finalize duplo → **uma** escrita `sent`.
- Recovery automática mensagens `sending`/`uploading`/`queued` > 12 min no arranque.

---

## 6. Índices criados / reforçados (`firestore.indexes.json`)

Já existiam (pedido): `churchId` + `createdAt`, `eventDate`, `noticeDate`, `memberId`, `chatId`+`createdAt`, etc.

**Adicionados nesta onda (messages / recovery):**

- `senderUid` ASC + `deliveryStatus` ASC  
- `senderUid` ASC + `deliveryStatus` ASC + `createdAt` DESC  
- `deliveryStatus` ASC + `createdAt` DESC  

**Deploy:** `.\scripts\deploy_firebase_rules.ps1` (inclui índices).

---

## 7. Queries otimizadas

- Recovery chat: threads `.limit(40)`, mensagens presas `.limit(25)` com `orderBy createdAt`.
- Fallback sem índice: `.limit(30)` + filtro cliente.
- Política global: leituras de listagem devem usar `.limit(20)` + `orderBy` (vários serviços já alinhados em sessões anteriores; painel ainda tem streams com cap próprio).
- `ChurchTenantDashboardDocService`: leitura **cache-first** de `dashboard/home` e `dashboard_stats/summary`.

---

## 8. Uploads corrigidos

| Parâmetro | Valor |
|-----------|--------|
| Timeout | 60s (`UnifiedUploadService`) |
| Retry máximo | 3 tentativas |
| Logs | `UPLOAD START` / `UPLOAD SUCCESS` / `UPLOAD ERROR` (+ YahwehFlowLog nos fluxos de publicação) |

Storage: extensões validadas na política existente (`firebase_upload_policy` / pipeline mídia).

---

## 9. Chat corrigido

### Texto
- `writeTextMessageFirestoreOnce()` — `messagesRef.add` com `deliveryStatus`/`status: sent`, sem CF, sem fila intermédia.
- UI: `ChurchChatInstantSendService` chama o método acima.

### Foto / PDF / vídeo / áudio
- Fluxo mantido (optimistic): stub `sending`/`uploading` → UI → upload background → `mediaUrl`/`fileUrl` → `sent`.
- Paralelismo: `church_chat_media_upload_coordinator` (máx. 3).

### Presas
- `ChurchChatAutoRecoveryService.recoverOnSessionStart()` no `AppFinalizeBootstrap`.
- Marca texto antigo como `sent`; mídia com URL como `sent`; sem URL → `abandonMediaUploadMessage`.
- Limpa `chat_uploads` órfãos > 12 min.

---

## 10. Avisos corrigidos

Fluxo canónico **Firestore-first**:

1. `set`/`add` documento (sem URL ou placeholder)  
2. Sucesso → fecha UI  
3. Upload background  
4. `update` URLs  
5. Push FCM / agenda em background  

Ficheiros: `FeedMediaPublishFast`, `MuralFastPublishService`, `instagram_mural.dart`.

---

## 11. Eventos corrigidos

Mesmo pipeline que avisos + `events_manager_page` sem retry upload-before-Firestore.

Agenda Google/push: `unawaited` após fechar modal.

---

## 12. Dashboard otimizado

- **SOT leitura:** `ChurchTenantDashboardDocService` — `igrejas/{id}/dashboard/home` + `dashboard_stats/summary`.
- **Escrita contadores:** `mergeCounters()` em mutações (não em tempo real na UI).
- **Proibido ideal:** contar membros/avisos/eventos/escalas em RT na UI — `igreja_dashboard_moderno.dart` ainda usa alguns streams `_panel_cache`; próximo passo é só trocar fonte dos números **sem mudar layout**.

---

## 13. Testes realizados

| Teste | Resultado |
|-------|-----------|
| `dart analyze` nos serviços alterados | OK após fix `YahwehFlowLog.chatAutoRecover` |
| Stress 1000 membros / 50k mensagens | **Não executado** (requer ambiente dedicado) |
| Deploy web / AAB | **Não executado** nesta sessão — usar scripts quando autorizado |

**Validação manual recomendada:**

1. Chat: enviar texto → aparece imediato com ✓.  
2. Chat: foto → bolha `sending` → URL → `sent`.  
3. Aviso com 3 fotos → «Publicar» fecha rápido; fotos aparecem depois.  
4. Evento idem.  
5. Matar app com upload a meio → reabrir → recovery no arranque.  
6. Login: sessão Firebase → painel; biometria só se activa.  
7. Dashboard: números vêm de `dashboard/home` sem spinner longo.

---

## Objetivo final (checklist)

| Meta | Estado |
|------|--------|
| Chat estilo WhatsApp (texto imediato, mídia optimista) | Implementado |
| Avisos gravando | Firestore-first |
| Eventos gravando | Firestore-first |
| Upload fotos/vídeos | Pipeline unificado + timeout/retry |
| Dashboard instantâneo | Parcial — doc service OK; UI ainda com streams legados |
| Login automático | Firebase `currentUser` + biometria opcional |
| Sem travamentos / loading infinito | Melhorado; monitorizar em produção |
| Android / iOS / Web rápidos | Depende de deploy + testes reais |

---

## Deploy

```powershell
# Só índices + regras
.\scripts\deploy_firebase_rules.ps1

# Só web
.\scripts\deploy_web_hosting.ps1

# Produção completa
.\scripts\deploy_completo.ps1
```

**Web:** https://gestaoyahweh-21e23.web.app (Ctrl+F5 após deploy).

---

## Pendências conscientes (não bloqueiam build)

- Substituir **globalmente** `catch (_) {}` por `rethrow` — **rejeitado** (quebraria fluxos que dependem de fallback).
- Unificar outbox chat com eliminação total de `chat_uploads` — risco em UI de progresso.
- Dashboard UI: remover streams de contagem RT mantendo o mesmo visual.
- Carteirinha / carta transferência: auditar `member_card_page.dart` (muitos `catch` silenciosos) — fase seguinte.
- Teste de carga formal.

---

*Documento gerado para fechar o pedido «RELATÓRIO FINAL OBRIGATÓRIO» do prompt cirúrgico.*
