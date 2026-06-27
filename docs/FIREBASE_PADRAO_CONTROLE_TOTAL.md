# Firebase — padrão Controle Total (Gestão YAHWEH)

> **Mapeamento completo CT / WisdomApp ↔ YAHWEH (paths, gateway, leituras, gravações, gaps):**  
> [`docs/MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`](MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md)  
> **Plano anexos Avisos/Eventos/Patrimônio/Financeiro + backup Wisdom:**  
> [`docs/IMPLEMENTACAO_ANEXOS_AVISOS_EVENTOS_PATRIMONIO_FINANCEIRO.md`](IMPLEMENTACAO_ANEXOS_AVISOS_EVENTOS_PATRIMONIO_FINANCEIRO.md)

## Princípio

1. **Ficheiros (Storage):** `putData` / `putFile` com utilizador autenticado → URL → gravar URL no documento de negócio.
2. **Dados (Firestore):** `set` / `update` com `FieldValue.serverTimestamp()` nas coleções da igreja (`avisos`, `eventos`, `membros`, `chat_threads/.../messages`).
3. **Sem fila Firestore** de upload (`pending_uploads` descontinuada no cliente; limpeza por migração + função agendada).
4. **Offline (só app mobile):** fila em disco `ApplicationDocuments/pending_uploads/` + SharedPreferences (`yahweh_pending_uploads_v1`), como o CT (`pending_storage_uploads_v1`).
5. **Web:** persistência Firestore desligada; long-polling; uploads imediatos (sem IndexedDB de fila).

## Bootstrap Firebase (único)

1. **`main.dart`:** `await FirebaseBootstrap.ensureInitialized()` — **único** `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
2. **`FirebaseBootstrapService.initialize()`:** só health check + `configureFirestoreForOfflineAndSpeed` — **não** chama `initializeApp` de novo.
3. **Publicar (avisos, eventos, chat texto, património):** `ensureFirebaseCore(requireAuth: true)` — init + JWT, sem reconnect/fila.

## Cliente (Flutter)

| Ficheiro | Função |
|----------|--------|
| `lib/core/firebase/firebase_bootstrap.dart` | `ensureInitialized()` — único `initializeApp` |
| `lib/core/firebase_bootstrap.dart` | `ensureFirebaseCore()` — guard CT para gravações |
| `lib/core/firebase_upload_policy.dart` | Liga/desliga fila Firestore |
| `lib/core/firestore_app_config.dart` | Settings Firestore (CT web/mobile) |
| `lib/services/firestore_simple_write.dart` | Merge + timestamps servidor |
| `lib/services/yahweh_media_upload_pipeline.dart` | Compressão + `putData` + retry |
| `lib/services/storage_upload_persistence_service.dart` | Fila disco (mobile) |
| `lib/services/pending_uploads_migration.dart` | Limpeza única da fila antiga |
| `lib/services/church_chat_stuck_cleanup_service.dart` | Botão **Limpar** no chat — apaga stubs/filas no Firestore |

## Regras

- **Storage:** paths `igrejas/{id}/…` — write = auth + limite de tamanho (`authMediaWriteMax`), MIME flexível (`octet-stream` aceite).
- **Firestore:** multi-tenant mantido; `pending_uploads` — cliente **não cria** novos docs (só `delete` para limpar).

## Functions

- `scheduledPurgeStalePendingUploads` — apaga jobs `pending_uploads` com mais de 7 dias (manutenção).

## Deploy

```powershell
.\scripts\deploy_firebase_rules.ps1
# Se alterou functions:
cd functions; npm run build; cd ..
firebase deploy --only functions:scheduledPurgeStalePendingUploads
.\scripts\deploy_web_hosting.ps1
```
