# Motor de Mensagens — Chat Igreja (Gestão YAHWEH)

Arquitetura oficial inspirada em apps de mensagens modernos (WhatsApp-like), **sem cópia literal** — adaptada ao contexto da igreja.

## Paths

| Camada | Path |
|--------|------|
| Firestore threads | `igrejas/{churchId}/chats/{chatId}` |
| Firestore mensagens | `igrejas/{churchId}/chats/{chatId}/messages/{messageId}` |
| Storage mídia | `igrejas/{churchId}/chat_media/{images\|videos\|audio\|documents}/` |
| Storage thumbs | `igrejas/{churchId}/chat_media/thumbs/` |

Bucket: `gs://gestaoyahweh-21e23.firebasestorage.app/igrejas/{churchId}/chat_media/`

## Porta única

```dart
import 'package:gestao_yahweh/core/chat_engine/chat_messaging_engine.dart';

// Abrir conversa (cache → rede, 30 msgs)
final docs = await ChatMessagingEngine.openConversation(
  churchId: churchId,
  chatId: chatId,
);

// Realtime cauda (30)
final stream = ChatMessagingEngine.watchRecentMessages(
  churchId: churchId,
  chatId: chatId,
);

// Paginação infinita
final older = await ChatMessagingEngine.loadOlderMessagesPage(
  churchId: churchId,
  chatId: chatId,
  startAfterDoc: oldestDoc,
);

// Texto otimista
ChatMessagingEngine.sendText(
  churchId: churchId,
  chatId: chatId,
  text: 'Olá',
);
```

## Modelo de mensagem (Firestore)

| Campo | Descrição |
|-------|-----------|
| `senderId` | UID remetente |
| `type` | text, image, video, audio, pdf, document, … |
| `text` | Corpo (texto/links) |
| `thumbnailUrl` / `thumbStoragePath` | **Só miniatura na lista** |
| `mediaUrl` / `storagePath` | Mídia completa — download **só ao clicar** |
| `status` / `deliveryStatus` | sending → sent → delivered → read |
| `readBy` | map uid → timestamp |
| `replyTo` | resposta |
| `forwarded` | encaminhada |
| `deleted` | apagada para todos |

## Performance (obrigatório)

- **30 mensagens** por página (`FirebasePerformanceLimits.chatMessagesPage`)
- **Proibido** carregar histórico inteiro
- **Proibido** baixar mídia completa ao abrir conversa
- Imagens: **WEBP 75%** (`ChurchChatMediaPrepare` + CF `churchPerformancePack`)
- Vídeos: **máx. 90s**, compressão H264 em background
- Envio: **stub Firestore primeiro**, upload Storage em segundo plano (`OptimisticChatMediaUpload`)
- Cache: `ChatLocalCacheEngine` (SharedPreferences + Hive)
- 1 listener por conversa: `StreamListenerRegistry`

## Presença

- `ChatPresenceEngine.setTyping` → «Fulano está digitando…»
- `recordingAudio` → «gravando áudio…»
- `chat_presence/{uid}` → online / visto por último

## Grupos

- `ChatThreadRepository.createGroup` / `updateGroup`
- Admins: `promoteAdmin`, `removeMember`
- `deleteGroupForEveryone` + auditoria em `chat_audit`

## Exclusão

| Ação | Comportamento |
|------|---------------|
| Apagar para mim | `hiddenForUids` |
| Apagar para todos | `delete()` mensagem |
| Excluir conversa | `hideThreadForUser` — histórico preservado |
| Limpar conversa local | `clearConversationLocal` |

## Auditoria

```dart
debugPrint(ChatMessagingEngine.auditReport());
```

Métricas: abertura conversa, fetch_recent, load_older, upload (via `ChatEngineAudit`).

## Módulos (`lib/core/chat_engine/`)

| Arquivo | Função |
|---------|--------|
| `chat_messaging_engine.dart` | Facade pública |
| `chat_message_repository.dart` | Firestore mensagens + paginação |
| `chat_thread_repository.dart` | Threads e grupos |
| `chat_presence_engine.dart` | Typing / online |
| `chat_local_cache_engine.dart` | Offline cache |
| `chat_engine_paths.dart` | Paths Storage/Firestore |
| `chat_models.dart` | `ChatMessage`, `ChatThread` |
| `chat_message_payload.dart` | Payloads canónicos |
| `chat_engine_audit.dart` | Relatório performance |

## Integração UI

- `church_chat_thread_page.dart` → `ChatMessagingEngine.openConversation`
- `ChurchChatService` → delega streams/paginação ao motor
- Mídia/upload → `OptimisticChatMediaUpload` (mantido; paths via `ChatEnginePaths`)

## Checklist aceite

```
[ ] Abrir conversa < 500ms com cache
[ ] Só 30 msgs na 1ª carga
[ ] Scroll carrega +30 (máx. 50 páginas)
[ ] Texto aparece antes do upload terminar
[ ] Lista mostra só thumbnail — full só no clique
[ ] WEB / Android / iOS — sem INTERNAL ASSERTION
[ ] ChatEngineAudit sem erros em sessão de 10 min
```
