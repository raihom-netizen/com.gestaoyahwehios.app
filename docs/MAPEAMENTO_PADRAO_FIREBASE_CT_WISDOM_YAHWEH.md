# Mapeamento Firebase — Controle Total / WisdomApp ↔ Gestão YAHWEH

**Objetivo:** Web, Android e iOS usam **os mesmos caminhos, o mesmo gateway e o mesmo fluxo de leitura/gravação** — como no Controle Total (CT) e no WisdomApp (Wisdom), adaptado ao modelo **multi-igreja** do YAHWEH.

**Referências locais**

| Projeto | Pasta |
|---------|--------|
| Controle Total | `C:\Controletotalapp_Independente\flutter_app` |
| WisdomApp | `C:\WisdomApp\lib` |
| Gestão YAHWEH | `C:\gestao_yahweh_premium_final\flutter_app` |

**Docs relacionados:** `docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md`, `IMPLEMENTACAO_ALINHAMENTO_CONTROLE_TOTAL.md`, `.cursor/rules/igrejas-arquitetura-final.mdc`

---

## 1. O que é igual (fundamentos CT/Wisdom → YAHWEH)

Estes padrões **não dependem** do path `users/` vs `igrejas/` — são os que eliminam “funciona no Android e quebra na Web”.

| Fundamento | Controle Total / Wisdom | Gestão YAHWEH (canónico) | Estado |
|------------|-------------------------|---------------------------|--------|
| **Um só `Firebase.initializeApp`** | `main.dart` → bootstrap único | `FirebaseBootstrapService.ensureInitializedOnce()` | ✅ |
| **Web: sem persistência agressiva + long-polling** | `persistenceEnabled: false` (web) | `configureFirestoreForOfflineAndSpeed()` | ✅ |
| **Mobile: cache Firestore + offline** | persistence ON | idem | ✅ |
| **Prep leve antes de gravar (sem `terminate`)** | CT evita matar cliente antes do write | `FirestoreWebGuard.prepareForPublishWrite()` | ✅ (2026-06-26) |
| **Recovery só após erro + 1 retry** | `runWithWebRecovery` / retry | `runFirestorePublishWithRecovery`, `runChatWriteWithRecovery` | ✅ |
| **Detecção `client has already been terminated`** | `FirestoreWebGuard.isClientTerminated` | idem | ✅ |
| **Leitura web com recovery** | `firestoreQueryGetReliable`, retry | `FirestoreReadResilience` + `runWithWebRecovery` | ✅ |
| **Upload: Storage → metadados Firestore** | URL no doc de negócio | `ChurchStorageLayout` + strict publish | ✅ (módulos strict) |
| **Imagens web: não `Image.network` cru** | pipeline Storage | `SafeNetworkImage` | ✅ |
| **Paginação listas (~20)** | limites por ecrã | `YahwehPerformanceV4.defaultPageSize = 20` | ✅ |
| **Sessão Auth persistente** | `AppSessionCache` + Firebase Auth | `PersistentAuthSessionService` + `AuthService` | ✅ |

---

## 2. O que é diferente (modelo de dados — não copiar paths à letra)

| | Controle Total / Wisdom | Gestão YAHWEH |
|---|-------------------------|---------------|
| **Tenant lógico** | `users/{uid}` (pessoa / conta) | `igrejas/{churchId}` (igreja) |
| **Finanças** | `users/{uid}/transactions` | `igrejas/{churchId}/finance` |
| **Contas bancárias** | `users/{uid}/finance_accounts` | `igrejas/{churchId}/contas` |
| **Escalas** | `users/{uid}/scales` | `igrejas/{churchId}/escalas` |
| **Chat** | — (não existe igual) | `igrejas/{churchId}/chats/{threadId}/messages` |
| **Membros** | — | `igrejas/{churchId}/membros` |
| **Storage raiz** | `users/{uid}/…`, `comprovantes/{uid}/…` | `igrejas/{churchId}/…` |
| **Gateway único** | **Não tem** — serviços + telas dispersas | **`ChurchRepository`** + `ChurchFirestoreAccess` |

**Regra:** portar **comportamento** do CT (retry, cache-first, publish order), **nunca** paths `users/{uid}` no painel igreja.

**WisdomApp** = fork CT + módulo `course_videos` + Storage `wisdomapp/…` — irrelevante para igreja, excepto os utilitários Web (`firestore_web_guard.dart`, etc.) já espelhados no YAHWEH.

---

## 3. Equivalência conceitual por módulo

| Módulo CT/Wisdom | Path CT | Módulo YAHWEH | Firestore YAHWEH | Storage YAHWEH |
|------------------|---------|---------------|------------------|----------------|
| Transação financeira | `users/{uid}/transactions/{id}` | Lançamento | `igrejas/{id}/finance/{id}` | `igrejas/{id}/financeiro/YYYY_MM/{id}.ext` |
| Conta bancária | `users/{uid}/finance_accounts/{id}` | Conta | `igrejas/{id}/contas/{id}` | — |
| Comprovante | `comprovantes/{uid}/…` | Comprovante | campos no doc `finance` | `financeiro/YYYY_MM/{lancamentoId}.jpg` |
| Lembrete / agenda | `users/{uid}/reminders/{id}` | Agenda igreja | `igrejas/{id}/agenda/{id}` | — |
| Escala | `users/{uid}/scales/{id}` | Escalas | `igrejas/{id}/escalas/{id}` | — |
| Notas | `users/{uid}/notes/{id}` | — | — | — |
| Perfil | `users/{uid}` | Cadastro igreja | `igrejas/{id}` (doc raiz) | `configuracoes/logo_igreja.png` |
| — | — | Membro | `igrejas/{id}/membros/{membroId}` | `membros/fotos/{id}.webp` + `thumbs/` |
| — | — | Aviso | `igrejas/{id}/avisos/{avisoId}` | `avisos/imagens/{postId}_*.webp` |
| — | — | Evento | `igrejas/{id}/eventos/{eventoId}` | `eventos/imagens|videos|thumbs/` |
| — | — | Patrimônio | `igrejas/{id}/patrimonio/{itemId}` | `patrimonio/imagens|thumbs/` |
| — | — | Chat | `igrejas/{id}/chats/{chatId}/messages/{msgId}` | `chat_media/{images|videos|audio|docs}/` |

---

## 4. Árvore canónica Gestão YAHWEH (única verdade)

### 4.1 Firestore

```
igrejas/{churchId}/
├── membros/
├── departamentos/
├── cargos/
├── visitantes/
├── eventos/
├── avisos/          (ou mural_avisos legado — só leitura/migração)
├── patrimonio/
├── chats/{chatId}/messages/
├── agenda/
├── escalas/
├── finance/         ← coleção real (UI diz «financeiro»)
├── finance_logs/
├── finance_mp_notifications/
├── fornecedores/
├── fornecedor_compromissos/
├── pedidosOracao/
├── contas/
├── config/mercado_pago
├── _dashboard_cache/
└── _panel_cache/
```

**Resolver ID (obrigatório em todo módulo):**

```dart
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

final churchId = ChurchRepository.churchId(widget.tenantId);
// ou ChurchContext.currentChurchId após login
```

**Proibido no painel pós-login:** `tenants/`, `church_aliases/`, `TenantResolverService.resolveOperationalChurchDocId`, `FirebaseFirestore.instance` em `lib/ui/`.

### 4.2 Storage (bucket `gestaoyahweh-21e23.firebasestorage.app`)

```
igrejas/{churchId}/
├── configuracoes/          logo, banner, assinatura
├── membros/fotos|thumbs/
├── avisos/imagens/
├── eventos/imagens|videos|thumbs/
├── patrimonio/imagens|thumbs/
├── financeiro/YYYY_MM/     comprovantes
├── chat_media/images|videos|audio|docs|thumbs/
├── certificados/
└── cartao_membro/
```

**Paths:** só via `ChurchStorageLayout.*` ou `FirebasePaths.storage*()` — nunca string solta.

---

## 5. Gateway único — mapa de classes (YAHWEH > CT)

O YAHWEH **já está à frente** do CT neste ponto. Toda tela/serviço do painel igreja deve usar:

| Papel | Classe | Ficheiro |
|-------|--------|----------|
| **Facade única** | `ChurchRepository` | `lib/core/repositories/church_repository.dart` |
| Paths Firestore | `ChurchDataPaths` | `lib/core/data/church_data_paths.dart` |
| Paths Storage | `ChurchStorageLayout` | `lib/core/church_storage_layout.dart` |
| Paths fachada | `FirebasePaths` | `lib/core/firebase_paths.dart` |
| Leituras | `ChurchFirestoreAccess.listOnce` | `lib/core/data/church_firestore_access.dart` |
| Sessão tenant | `ChurchContext` / `ChurchContextService` | `lib/core/tenant/church_context.dart` |
| Resiliência web leitura | `FirestoreWebGuard` + `FirestoreReadResilience` | `lib/utils/firestore_web_guard.dart` |
| Resiliência web gravação | `runFirestorePublishWithRecovery` | `lib/utils/firestore_publish_recovery.dart` |
| Chat gravação | `runChatWriteWithRecovery` | `FirestoreWebGuard` |
| Upload | `StorageService` / `YahwehMediaUploadPipeline` | `lib/services/storage_service.dart` |

**Equivalente CT (referência):** `firestore_user_doc_id.dart` → no YAHWEH: `ChurchRepository.churchId(hint)`.

---

## 6. Leitura de dados — fluxo idêntico Web = Android = iOS

```
1. churchId = ChurchRepository.churchId(hint)
2. [Web] await FirestoreWebGuard.ensurePanelReadReady()
3. FirestoreReadResilience / ChurchFirestoreAccess.listOnce
   └─ runWithWebRecovery (até 3× em falha transitória)
4. Cache: RAM → Hive → Source.cache → servidor (background)
5. UI: skeleton só se lista vazia; cap 14s web
6. Erro: ChurchPanelErrorBody com mensagem real (não apagar lista em cache)
```

**Referência por módulo (copiar padrão):**

| Módulo | Load service | Página |
|--------|--------------|--------|
| Membros | `MemberRepository` | `members_page.dart` |
| Cargos | `church_cargos_load_service.dart` | `cargos_page.dart` |
| Visitantes | `church_visitantes_load_service.dart` | `visitors_page.dart` |
| Avisos | `church_avisos_load_service.dart` | `instagram_mural.dart` |
| Eventos | `church_eventos_load_service.dart` | `events_manager_page.dart` |
| Patrimônio | cache + `ChurchRepository.patrimonio` | `patrimonio_page.dart` |
| Financeiro | `ChurchUiCollections.financeiro` | `finance_page.dart` |
| Chat | `ChurchChatService` | `church_chat_thread_page.dart` |
| Dashboard | `_dashboard_cache` + snapshot | `igreja_dashboard_moderno.dart` |

**Proibido web:** dezenas de `.snapshots()` paralelos no painel (`FirestoreWebGuard.disableLiveSnapshotsOnWeb`).

---

## 7. Gravação / upload — fluxo idêntico (strict publish)

Padrão Controle Total aplicado no YAHWEH (módulos críticos):

```
1. Validar formulário (antes de «Publicando…» / spinner)
2. prepareForPublishWrite()  ← leve, NUNCA terminate preventivo
3. Comprimir mídia local (WebP ~75–80%, 1024px perfil)
4. Upload Storage (ChurchStorageLayout)
5. Verificar metadata Storage
6. runFirestorePublishWithRecovery → gravar Firestore UMA vez
7. Sucesso UI → distribuição background (site, push, agenda)
8. Se falhar: recovery + 1 retry; senão erro real ao utilizador
```

| Módulo | Serviço strict |
|--------|----------------|
| Aviso | `AvisoStrictPublishService` → `ChurchFeedLinearPublishService` |
| Evento | `EventoStrictPublishService` → idem |
| Patrimônio | `PatrimonioStrictPublishService` → `PatrimonioPublishService` |
| Comprovante | `FinanceComprovantePublishService` |
| Foto membro | `MemberProfilePhotoSaveService` |
| Chat texto | `ChurchChatInstantSendService` / `runChatWriteWithRecovery` |
| Chat mídia | `ChatStrictPublishService` → Storage → Firestore `storagePath` |

**Firestore chat:** gravar `storagePath` + `status` — **não** `downloadURL` antes do Storage OK.

---

## 8. Sessão e bootstrap (igual CT, adaptado)

| Passo | CT/Wisdom | YAHWEH |
|-------|-----------|--------|
| Arranque | `Firebase.initializeApp` uma vez | `FirebaseBootstrapService.ensureInitializedOnce()` |
| Antes de publicar | Auth + Storage linked | `EcoFirePublishBootstrap.ensureHard` + `ensureFirebaseCore(requireAuth: true)` |
| Bind tenant | `firestoreUserDocIdForAppShell(uid)` | `ChurchContextService.bindChurchId` no login |
| Logout | troca de conta | só «Trocar de conta» |

---

## 9. Gaps conhecidos (auditoria 2026-06-26)

Executar: `.\scripts\auditoria_acessos_firestore_storage.ps1`

| Tipo | Onde ainda aparece | Acção |
|------|-------------------|-------|
| `FirebaseFirestore.instance` em `lib/ui/` | `sistema_informacoes_page`, `global_announcement_overlay`, `editar_precos_planos_page`, … | Migrar para serviço/gateway ou rotas master |
| `TenantResolverService` no painel | `auth_gate`, `igreja_cadastro_page`, `igreja_dashboard_moderno` | Só cadastro público / migração — não listagens |
| `collection('tenants')` | `church_panel_tenant_gateway` (legado), `functions/` | CF legado — não usar no Flutter painel |
| Módulo frota JimSabores | `jimsabores_frota/*` | Fora do escopo igreja — paths próprios |

**Meta:** painel igreja com **zero** acessos directos em `lib/ui/`; DEBUG CHURCH com paths idênticos Web/Android/iOS.

---

## 10. Prova de aceite (3 plataformas)

1. Configurações → **DEBUG CHURCH** → Publicar prova (Web, Android, iOS)
2. Copiar relatório — todos os módulos com path `igrejas/{churchId}/…`
3. Grep legado limpo no painel

| Módulo | Firestore | Storage | Web | Android | iOS |
|--------|-----------|---------|-----|---------|-----|
| Cadastro | `igrejas/{id}` | `configuracoes/` | | | |
| Membros | `…/membros` | `membros/fotos` | | | |
| Avisos | `…/avisos` | `avisos/imagens` | | | |
| Eventos | `…/eventos` | `eventos/` | | | |
| Patrimônio | `…/patrimonio` | `patrimonio/` | | | |
| Financeiro | `…/finance` | `financeiro/` | | | |
| Chat | `…/chats/…/messages` | `chat_media/` | | | |

Igreja teste: `igreja_o_brasil_para_cristo_jardim_goiano`

---

## 11. Checklist «padronizar de vez»

- [ ] Toda tela nova: `ChurchRepository.*` — nunca path manual
- [ ] Toda gravação web: `runFirestorePublishWithRecovery` ou `runChatWriteWithRecovery`
- [ ] Toda leitura web: `ensurePanelReadReady` + `runWithWebRecovery`
- [ ] Todo upload: `ChurchStorageLayout` + `StorageService`
- [ ] Toda imagem URL Storage na web: `SafeNetworkImage`
- [ ] Validar formulário **antes** de spinner de publicação
- [ ] DEBUG CHURCH 3 plataformas antes de declarar concluído
- [ ] `.\scripts\auditoria_acessos_firestore_storage.ps1` sem violações no painel

---

## 12. Comandos úteis

```powershell
# Auditoria paths / legado
.\scripts\auditoria_acessos_firestore_storage.ps1

# Análise Dart (ficheiros tocados)
cd flutter_app
dart analyze --no-fatal-warnings lib/core/repositories/church_repository.dart lib/utils/firestore_web_guard.dart
```

**Web produção:** https://gestaoyahweh-21e23.web.app (Ctrl+F5 após deploy)
