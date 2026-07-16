# Ponto Base de Memoria — Gestão YAHWEH (GERAL)

**Data:** 2026-07-15  
**Release de referencia:** `11.2.305+2107`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2107`  
**Git (ultimo push Codemagic):** `ee35c40` (`main`) — pendente push build 2107 (Crashlytics + custo reads)  
**Deploy completo:** 2026-07-15 — regras/índices + Cloud Functions + web + AAB + ZIP iOS + push + force update  
**Hotfix 2026-07-16:** Crashlytics iOS (`_deptsFuture` LateInit + Json Infinity); menos reads membros; `scheduledRefreshPanelCaches` 60min; igrejas teste purged.  
**Web + forceUpdate:** `config/appVersion` → alinhar no próximo deploy (`11.2.305+2107`)  
**Anterior memoria:** `BKP_MEMORIA_PONTO_PARTIDA_YAHWEH.md` (2034) — **removida** (substituida por este ficheiro)

**Firebase:** `gestaoyahweh-21e23`  
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
**Web producao:** https://gestaoyahweh-21e23.web.app  

**Este e o unico ponto de memoria ativo.**

---

## Regra principal

- Toda melhoria parte deste ponto: **somar sem regredir**.
- Nao mudar `appVersion` (`11.2.305`) sem ordem explicita do usuario — so incrementar `appBuildNumber` / `+N`.
- **Paridade obrigatoria:** Web + Android + iOS — mesma experiencia e mesmos paths `igrejas/{churchId}/…`.
- **Performance critica:** cache-first; sem queries pesadas / varreduras no caminho quente da UI; paginacao **20**.
- Preservar `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`.
- Temporarios **sempre** em `D:\Temporarios` (AAB, ZIP iOS, logs, bundletool).
- Deploy via `.\scripts\deploy_completo.ps1` **somente** com pedido explicito; force update via `.\scripts\publish_force_update_online.ps1`.
- Nao remover botoes, modulos, campos, indices ou regras sem pedido explicito.
- **Proibido** `*ServiceV2` / novos resolvers no painel — evoluir `ChurchRepository` + servicos existentes.

---

## Versao oficial (codigo)

| Arquivo | Valor |
|---------|-------|
| `flutter_app/lib/app_version.dart` | `appVersion='11.2.305'`, `appBuildNumber='2106'` |
| `flutter_app/pubspec.yaml` | `11.2.305+2106` |
| `flutter_app/web/version.json` | `"version":"11.2.305"`, `"build_number":"2106"` |

### Artefatos desta release

| Artefato | Caminho |
|----------|---------|
| AAB Play | `D:\Temporarios\GestaoYahweh_11.2.305_build2106_play.aab` (~190 MB) |
| ZIP iOS Codemagic | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2106.zip` |
| bundletool | `D:\Temporarios\bundletool-all-1.18.3.jar` |
| Site | https://gestaoyahweh-21e23.web.app |
| `version.json` web online | `11.2.305+2106` |

## Confirmado no HEAD (`ee35c40`) — 2026-07-15

| Melhoria | Status |
|----------|--------|
| Painel igreja: menos tempestade de warmup; leitura capada; membros lista otimizada | No commit |
| Eventos/Avisos: sync Firebase, preview/progresso mídia, offline fila, gate anti `core/no-app` | No commit |
| Mídia unificada (logo, patrimônio, financeiro, fornecedores, cadastro público) | No commit |
| Chat Telegram-fast: texto/foto/áudio, outbox, progresso global, DM canSend cache | No commit |
| Master / site público / divulgação: mídia + prefetch caps + erros amigáveis | No commit |
| Pagamentos: Play `us-central1`, package `com.gestaoyahweh.app`, PIX/cartão Checkout Pro, doações | No commit |
| Utilitarios alinhados Controle Total (PDF, editor, Foto/Câmera→PDF, OCR) | No commit |
| Deploy: regras/índices OK, functions, web 2106, AAB+ZIP, push `main`, force update | Confirmado |

---

## Painel Igreja — modulos shell (`igreja_clean_shell.dart`)

Indices em `flutter_app/lib/core/church_shell_indices.dart`.

| # | Modulo | Nota |
|---|--------|------|
| 0 | Painel / Dashboard | `_dashboard_cache` / `_panel_cache` — sem scan completo |
| 1 | Cadastro da Igreja | Logo Storage canónico; leitura directa `igrejas/{id}` |
| 2 | Configurações | Trocar conta; DEBUG CHURCH (só master/adm) |
| 3 | Membros | Referência canónica de carga/cache-first |
| 4 | Departamentos | `ChurchRepository` + load service |
| 5 | Visitantes | idem |
| 6 | Cargos | idem |
| 7 | Avisos (mural) | até 5 fotos; `PublicationEngine` / strict publish |
| 8 | Eventos | até 5 fotos + 1 vídeo 90s 720p |
| 9 | Pedidos de oração | |
| 10 | Agenda | só texto; sem mídia pesada |
| 11 | Minha escala | |
| 12 | Escala geral | |
| 13 | Cartão membro | PDF local |
| 14 | Certificados | |
| 15 | Cartas / transferências | |
| 16 | Relatórios | |
| 17 | Informações | |
| 18 | Aprovações rápidas | |
| 19 | Financeiro | comprovantes Storage `financeiro/YYYY_MM/` |
| 20 | Patrimônio | até 5 fotos/bem |
| 21 | Fornecedores | compromissos + comprovantes |
| 22 | Doação | PIX/cartão → igreja (MP) |
| 23 | Chat Igreja | Telegram-fast; paginação 20–30 |
| 24 | Utilitários | PDF, foto, colagem, vídeo, Foto→PDF, OCR |

### Fluxos Utilitarios (preservar)

- `utilitarios_pdf_tools_flow.dart`
- `utilitarios_photo_edit_flow.dart` — editor Cores/Texto/Cortar/Borrar
- `utilitarios_photo_collage_flow.dart`
- `utilitarios_photo_camera_pdf_flow.dart` — câmera, até 20 fotos → PDF
- `utilitarios_photo_text_extract_flow.dart` + service — OCR ML Kit

---

## Painel Master (`admin_panel_page.dart`)

Areas principais (preservar):

| Area | Conteudo |
|------|----------|
| Igrejas | Dashboard, lista, planos, usuarios, Controle 360, Mercado Pago, recebimentos, gestores, Torre de Comando |
| Sistema | Dashboard, alertas, auditoria, customizacao, suporte, Multi-Admin, precos, niveis, sugestoes |
| Divulgacao / Marketing | CMS `public/` + `app_public/`; clientes showcase |
| Diagnostic | Firebase saude, multi-tenant, aviso global, legal, versao minima, migrar membros, feature flags |

Acesso diagnostico avancado: so roles master/adm (`DiagnosticAccessPolicy`).

---

## Novidades 2026-07-15 (obrigatorio preservar)

### Mídia / upload (padrao CT)

1. Picker → **bytes** (`Uint8List`) — **nunca** `putFile` na Web.
2. Comprimir (JPEG/WebP; vídeo H.264 720p eventos).
3. Upload Storage path: `igrejas/{churchId}/{modulo}/…` via facade / `DirectStorageUrlPublish` / `ChurchMediaUploadFacade`.
4. Validar → gravar Firestore **uma vez** (URL + `storagePath`).
5. Offline mobile: fila em disco `StorageUploadPersistenceService` + `BackgroundUploadWorker`.
6. **Proibido:** fila `pending_uploads` Firestore; `FirebaseBootstrap.reset()` no hot path de publish.

### Chat Igreja

- Texto otimista; mídia Storage → Firestore; bolha offline “Na fila…”.
- `GlobalUploadProgress`; áudio UI cedo; gate upload timeout curto → fila.
- Path: `igrejas/{churchId}/chats/.../messages`; Storage `chat_media/`.

### Pagamentos / licenças / doações

- Billing Play + callables `us-central1`; package `com.gestaoyahweh.app`.
- Licença igreja: PIX/Checkout Pro; doações `paymentMethod: card` / PIX à igreja.
- Sem demo “Ativar plano” falsa.

### Site público / Master mídia

- Prefetch deduplicado e capped; `SafeNetworkImage` / feedback imediato; thumbs logo Master.

---

## Preservar herdado (2034 e anteriores)

### Tenant unico

```
churchId UMA vez → Firestore igrejas/{churchId}/… → Storage igrejas/{churchId}/…
```

**Proibido no painel pos-login:** `tenants`, `church_aliases`, `church_roots`, `TenantResolverService.resolveOperationalChurchDocId`, `FirebaseFirestore.instance` solto em `lib/ui/`.

### Web Firestore

- Sem `snapshots()` em listas longas na Web → polling / `watchSafe`.
- `FirestoreWebGuard.ensurePanelReadReady` + `runWithWebRecovery(maxAttempts: 4)`.
- Cap painel **14s**; skeleton só se lista vazia; nao limpar cache antes da rede.

### Offline-first

- Cache → UI → refresh silencioso (`SyncEngine`, `TenantOfflineWrite`, `OptimisticFirestoreWrite`).
- Falha de rede **nao** apaga lista visivel se ha dados locais.

---

## Servicos-chave

| Area | Servicos |
|------|----------|
| Auth / sessao | `AuthService`, `PersistentAuthSessionService`, `ChurchContextService` |
| Firestore tenant | `ChurchRepository`, `ChurchDataService`, `ChurchTenantResilientReads` |
| Upload / midia | `ChurchMediaUploadFacade`, `StorageService`, `YahwehMediaUploadPipeline`, `DirectStorageUrlPublish`, `YahwehModuleMediaGate` |
| Avisos / Eventos | `PublicationEngine`, `AvisoStrictPublishService`, `EventoStrictPublishService` |
| Chat | `ChurchChatService`, `ChurchChatFastSendService`, `ChatStrictPublishService` |
| Dashboard | `IgrejaDashboardModerno`, `ChurchTenantDashboardDocService`, `_panel_cache` |
| Pagamentos | `BillingService`, Mercado Pago functions, `church_donations_page` |
| Utilitarios | `utilitarios_photo_service`, `utilitarios_local_service`, OCR service |
| Sync offline | `SyncEngine`, `HiveLocalStore`, `TenantOfflineWrite` |

Utils: `firestore_web_guard`, `immediate_media_attach_feedback`, `safe_network_image`.

---

## Cloud Functions (resumo)

Projeto `gestaoyahweh-21e23` — `functions/src/index.ts` + siblings:

- Billing / Play / Mercado Pago (licenças + doações igreja)
- Push FCM (`pushNovoConteudo`, agenda)
- Feed / mídia bridges (`gyAdminUpsertFeedPost`, `gyPublicMemberSignup`, etc.)
- Cache público / dashboard stats
- Chat retention / cleanup Storage
- Admin / auditoria / force version helpers

Deploy: passo `[2/6]` de `deploy_completo.ps1` ou `firebase deploy --only functions`.

---

## Firebase — paths canonicos

### Firestore

```
igrejas/{churchId}/
  membros, avisos, eventos, patrimonio, finance,
  chats/{chatId}/messages, departamentos, cargos, visitantes,
  escalas, agenda, fornecedores, fornecedor_compromissos,
  _panel_cache/*, _dashboard_cache/*, config/*

users/{uid}                 # perfil Auth global
app_public/*                # marketing / site institucional
public_church_slugs/{slug}  # leitura publica; write CF
config/appVersion           # force update
```

### Storage

```
igrejas/{churchId}/
  membros/…, avisos/imagens/, eventos/imagens|videos|thumbs/,
  patrimonio/…, financeiro/YYYY_MM/, chat_media/…,
  configuracoes/, cartao_membro/, certificados/, fornecedores/…

public/gestao_yahweh/…      # Master divulgação CMS
```

**SSOT paths:** `lib/core/church_storage_layout.dart`  
**Gateway painel:** `ChurchRepository` + `church_*_load_service.dart`

---

## Regras e indices

| Ficheiro | Papel |
|----------|-------|
| `firestore.rules` | ACL tenant; chats/membros/finance/avisos/eventos |
| `storage.rules` | Escrita só sob `igrejas/{churchId}/…` (+ `public/` marketing) |
| `firestore.indexes.json` | Listas painel, feeds, chats, finance, escalas |
| `firebase.json` | Hosting → `flutter_app/build/web` |

Publicar regras (autorizado): `.\scripts\regras_gcp_automatico_forcado.ps1` ou passo `[1/6]` do deploy completo.

---

## Deploy / Codemagic

```powershell
cd C:\gestao_yahweh_premium_final
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
.\scripts\deploy_completo.ps1 -CopyTo "D:\Temporarios" -ForceFunctions -ForceFirestoreRules
.\scripts\publish_force_update_online.ps1   # so apos validar
```

| Item | Valor |
|------|-------|
| Branch iOS | `main` (push dispara/baseia Codemagic) |
| Commit release | `ee35c40` |
| Start Codemagic | **Manual** na UI |
| Temporarios | `D:\Temporarios` |
| Se bundletool falhar | jar em `D:\Temporarios\bundletool-all-1.18.3.jar` |

Parcial:

| Pedido | Script |
|--------|--------|
| So web | `.\scripts\deploy_web_hosting.ps1` |
| So regras | `.\scripts\deploy_firebase_rules.ps1` / `regras_gcp_automatico_forcado.ps1` |

---

## Arquivos criticos

```
scripts/deploy_completo.ps1
scripts/publish_force_update_online.ps1
scripts/build_android_play_store_aab.ps1
codemagic.yaml
firebase.json / firestore.rules / storage.rules / firestore.indexes.json
flutter_app/lib/app_version.dart
flutter_app/lib/core/church_shell_indices.dart
flutter_app/lib/core/church_storage_layout.dart
flutter_app/lib/core/repositories/church_repository.dart
flutter_app/lib/core/yahweh_module_media_gate.dart
flutter_app/lib/ui/igreja_clean_shell.dart
flutter_app/lib/ui/admin_panel_page.dart
flutter_app/lib/ui/pages/members_page.dart
flutter_app/lib/services/publication_engine.dart
flutter_app/lib/services/church_chat_service.dart
functions/src/index.ts
prompt_mestre_cursor.md
AGENTS.md
```

---

## Checklist pos-release (2106)

- [x] Web `version.json` online = `2106`
- [x] AAB em `D:\Temporarios\…build2106…aab`
- [x] ZIP iOS em `D:\Temporarios\…build2106.zip`
- [x] Push `main` `ee35c40`
- [x] Force update `config/appVersion` 2106
- [x] Regras/índices alinhados (remoto = local no preflight)
- [ ] Start Codemagic → TestFlight
- [ ] Upload AAB Play Console (versionCode **2106** > ultimo publicado)
- [ ] Ctrl+F5 web — painel igreja + master
- [ ] Android: instalar AAB — chat / avisos / eventos / utilitarios

---

## Proxima manutencao

- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2106.mdc`
- Documento unico: **este arquivo** (`PONTO_BASE_MEMORIA_2026-07-15_11.2.305+2106.md`)
- Proximo build: so `+N` / `appBuildNumber` (marketing `11.2.305` ate ordem explicita)
- Ao criar nova memoria: renomear/substituir este ficheiro + a regra `.mdc` e **apagar** a memoria anterior (como Controle Total)
