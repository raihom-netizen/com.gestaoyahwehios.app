# Auditoria — publicação Avisos / Eventos / Chat

**Data:** 2026-06-01 · **Build:** 11.2.295+1726  
**Referência cruzada:** [DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md](./DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md)

---

## Conclusão executiva

O Storage e as regras Firebase **não** são o gargalo principal. O comportamento («não publica», «Salvando…» infinito, fotos que não aparecem) vem de **pipelines mistos**:

| Sintoma | Causa provável | Onde |
|--------|----------------|------|
| Publicar trava minutos | `drainInFlight` esperava até **40s** por uploads ao anexar | `immediate_media_warm.dart` (corrigido: 2s) |
| Evento não fecha após publicar | `await _applyAgendaSyncAfterSave` antes do `Navigator.pop` | `events_manager_page.dart` (corrigido: `unawaited`) |
| Retry Firestore trava | Caminho de retry fazia **upload → set** (legado) | `events_manager_page.dart` catch ~6915 (corrigido: `FeedMediaPublishService.publish`) |
| Fotos no feed vazias / «uploading» | UI mostra stub antes do merge; ou anexo falhou em silêncio | `publishState: processing` + background finalize |
| Chat não «entrega» | `deliveryStatus` vs `status`; rede; DM bloqueado | `church_chat_service.dart` |
| Erros invisíveis | `catch (_) {}` em outbox/cache | `mural_fast_publish_service.dart` (parcialmente corrigido) |

**Regra Cursor antiga** `avisos-eventos-publicacao-sincrona.mdc` pedia upload-before-Firestore — **contradizia** o código canónico e foi **atualizada** para Firestore-first.

---

## Serviços procurados (nomes do pedido)

| Nome pedido | Equivalente no projeto |
|-------------|------------------------|
| `chat_repository` | `ChurchChatService` + `church_chat_firestore_map.dart` |
| `chat_service` | `church_chat_service.dart`, `church_chat_instant_send_service.dart` |
| `message_service` | mensagens em `messagesCol()` dentro de `ChurchChatService` |
| `mural_service` | `MuralFastPublishService`, `mural_publish_outbox_service.dart` |
| `notice_service` | `FeedMediaPublishService` + `instagram_mural.dart` |
| `evento_service` | `FeedMediaPublishService` + `events_manager_page.dart` |

Não existem ficheiros `*_repository.dart` dedicados ao chat do mural.

---

## Fluxo canónico atual (correto)

```
AVISO / EVENTO (com fotos novas)
  AVISO START / EVENTO START
  → FeedPublishPreflight (drain ≤2s, warm em background)
  → ChurchDataService.setTenantDocument (stub)
  → AVISO FIRESTORE OK / EVENTO FIRESTORE OK
  → Navigator.pop (UI)
  → UPLOAD START (background)
  → Storage slots
  → merge URLs + publishState: published
  → AVISO UPLOAD OK / EVENTO UPLOAD OK
  → AVISO FINAL OK / EVENTO FINAL OK
  → (FCM via Function após published)

CHAT texto
  CHAT START
  → beginTextMessage (Firestore, status=sending)
  → CHAT MESSAGE CREATED
  → finalizeTextMessage (status=sent)
  → CHAT MESSAGE UPDATED
  → CHAT FINAL OK

CHAT mídia
  CHAT START → stub → CHAT MESSAGE CREATED
  → Storage → CHAT FILE UPLOADED
  → completeMediaUploadMessage → CHAT MESSAGE UPDATED → CHAT FINAL OK
```

**Push / WhatsApp:** não bloqueiam o `set` inicial; FCM dispara no servidor quando o documento fica `published` (ver comentário em `mural_fast_publish_service.dart`).

---

## Ficheiros prioritários — achados

### `docs/DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md`

Documenta paridade Chat vs feed; secção E ainda menciona `feed_media_publish_strict` como «upload → Firestore» — **desatualizado**; strict agora delega a `FeedMediaPublishFast`.

### `lib/core/firebase_publish_guard.dart`

Só `ensureFirebaseReadyToPublish()` → bootstrap. **Não** serializa upload/push.

### `lib/core/firebase/firebase_retry.dart`

Retry com backoff + Crashlytics; **rethrow** no fim. OK.

### `lib/core/firebase/firebase_service.dart`

Acesso pós-bootstrap; evita `FirebaseFirestore.instance` estático em serviços novos.

### `lib/core/firebase_upload_policy.dart`

`firestorePendingQueueEnabled = false` — fila `pending_uploads` **não** bloqueia publicação normal.

### `lib/core/evento_aviso_media_policy.dart`

Limites de fotos/vídeo; **sem** pipeline de publicação.

### `lib/core/event_noticia_media.dart` / `event_feed_mural_visibility.dart`

**Leitura/exibição** no feed e galeria — não participam do save. Fotos «não aparecem» se URL ainda vazia ou `publishState != published`.

### `lib/core/noticia_social_service.dart`

Curtidas/RSVP; usa `FirebaseFirestore.instance` direto — **fora** do caminho Publicar; risco `core/no-app` só em interações sociais.

### `lib/services/immediate_feed_photo_attach.dart`

Upload **ao anexar** foto (opcional). Pode deixar `_inFlightPhotoUploads > 0`; publicar espera no máximo **2s**, depois Firestore-first.

### `lib/services/feed_media_publish_strict.dart`

**@Deprecated** — delega a `FeedMediaPublishFast` (Firestore-first).

---

## Onde a publicação ainda pode falhar (checklist DevTools)

1. Procurar `AVISO START` sem `AVISO FIRESTORE OK` → Firestore (rede, regras, assert).
2. `FIRESTORE OK` sem `UPLOAD OK` → Storage/CORS/compressão (ver `[FirebaseApps]`).
3. `UPLOAD OK` sem `FINAL OK` → merge/outbox (`MuralPublishOutboxService`).
4. Chat: `CHAT START` sem `MESSAGE CREATED` → DM bloqueado / auth.
5. `MESSAGE CREATED` sem `FILE UPLOADED` → Storage chat_media.
6. Post no feed com `publishState: processing` eterno → background abortado; usar retry no card ou republicar.

---

## Alterações desta auditoria (código)

- Logs obrigatórios: `lib/core/church_publish_flow_log.dart`
- Retry eventos Firestore-first: `_retryEventPublishFirestoreFirst()`
- Regra Cursor: `.cursor/rules/avisos-eventos-publicacao-sincrona.mdc` alinhada ao fluxo real
- `catch (_) {}` críticos no mural publish → log + continuação

**Não alterado:** telas, design, `firestore.rules`, `storage.rules`.
