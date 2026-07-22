# Ponto Base de Memoria — Gestão YAHWEH (GERAL)

**Data:** 2026-07-20  
**Release de referencia:** `11.2.305+2120`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2120`  
**Git (ultimo push Codemagic):** `9721fd1` (`main`)  
**Deploy completo:** 2026-07-20 — functions + web + AAB + ZIP iOS + push + force update  
**Web + forceUpdate:** `config/appVersion` → `minBuildNumber: 2120`, `forceUpdate: true`, `latestVersion: 11.2.305+2120`  
**Anterior memoria:** `PONTO_BASE_MEMORIA_2026-07-17_11.2.305+2118.md` — **removida** (substituida por este ficheiro)

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
- **Pedido 2026-07-20 (sessão atual):** rodar **todas** as correções/melhorias pedidas primeiro; **não** bump de versão de release nem deploy até o usuário falar **explicitamente** no final. Código local pode ficar à frente da release `2120`/`2121` sem publicar.
- Nao remover botoes, modulos, campos, indices ou regras sem pedido explicito.
- **Proibido** `*ServiceV2` / novos resolvers no painel — evoluir `ChurchRepository` + servicos existentes.

---

## Versao oficial (codigo)

| Arquivo | Valor |
|---------|-------|
| `flutter_app/lib/app_version.dart` | `appVersion='11.2.305'`, `appBuildNumber='2120'` |
| `flutter_app/pubspec.yaml` | `11.2.305+2120` |
| `flutter_app/web/version.json` | `"version":"11.2.305"`, `"build_number":"2120"` |

### Artefatos desta release

| Artefato | Caminho |
|----------|---------|
| AAB Play | `D:\Temporarios\GestaoYahweh_11.2.305_build2120_play.aab` (~190 MB / 199222562 bytes) |
| ZIP iOS Codemagic | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2120.zip` (~1 MB) |
| bundletool | `D:\Temporarios\bundletool-all-1.18.3.jar` |
| Site | https://gestaoyahweh-21e23.web.app |
| `version.json` web online | `11.2.305+2120` (confirmado 2026-07-20) |

## Confirmado no HEAD (`9721fd1`) — 2026-07-20

| Melhoria | Status |
|----------|--------|
| Rodapé shell: **Início → Cartão → Agenda → Membros → Avisos → Eventos → YahwehChat** (+ extras) | No commit |
| Cartão membro fullscreen + Voltar ao Painel (Web/Android/iOS); self-only vê carteirinha | No commit |
| Módulos mobile/web estreita em tela cheia (`shellModuleFullBleed`) + `ModuleHeaderPremium` Voltar | No commit |
| Membro comum self-only: só o próprio cadastro (UI + `firestore.rules`) | No commit |
| Permissões CRUD: financeiro, fornecedores, patrimônio, membros, avisos/eventos, cadastro igreja, master | No commit |
| Uploads/chat estáveis: timeouts, sem compressão duplicada, gate Firebase mais tolerante | No commit |
| Analyze preflight: `FilePicker` 11 (`YahwehFilePicker`) + `formatUploadErrorForUser` sem ambiguidades | No commit |
| Deploy: functions (incl. retry `setUserActive`), web **2120**, AAB+ZIP **2120**, push `main`, force update | Confirmado |
| Storage rules | OK nesta sessão |
| Firestore rules / índices via GCP | **Pendência:** API `firebaserules.googleapis.com` 503 intermitente — repetir `.\scripts\deploy_firebase_rules.ps1 -ForcePublish` |

### Herdado da 2118 (preservar)

| Melhoria | Status |
|----------|--------|
| Mídia sem hang (~82%): `getDownloadURL` soft-fail + path-only; timeouts URL 8s | Herdado |
| YahwehChat DM instantâneo (Membros / aniversariantes / hub) | Herdado |
| Anti-sumiço ao trocar módulo: patrimônio / financeiro / fornecedores | Herdado |
| Limpeza BPC: só `membros` (+ preservar MP igreja); Master MP raiz OK | Herdado |
| Script `scripts/cleanup_bpc_keep_membros_only.cjs` | No repo |
| Login/cadastro modernizados; rodapé linha única | Herdado |

### Igreja piloto BPC (estado banco)

- Tenant: `igreja_o_brasil_para_cristo_jardim_goiano`
- Mantido: coleção `membros` + fotos Storage `igrejas/{id}/membros/`
- Limpeza 2118: eventos/avisos/financeiro/chat/patrimônio/caches limpos — dados de piloto a recriar conforme uso
- Mercado Pago igreja: confirmar em Configurações se necessário

---

## Painel Igreja — modulos shell (`igreja_clean_shell.dart`)

Indices em `flutter_app/lib/core/church_shell_indices.dart`.

| # | Modulo | Nota |
|---|--------|------|
| 0 | Painel / Dashboard | `_dashboard_cache` / `_panel_cache` — sem scan completo |
| 1 | Cadastro da Igreja | Logo Storage canónico; leitura directa `igrejas/{id}` |
| 2 | Configurações | Trocar conta; DEBUG CHURCH (só master/adm) |
| 3 | Membros | Referência canónica; self-only = só o próprio |
| 4 | Departamentos | `ChurchRepository` + load service |
| 5 | Visitantes | idem |
| 6 | Cargos | idem |
| 7 | Avisos (mural) | até 5 fotos; `PublicationEngine` / strict publish |
| 8 | Eventos | até 5 fotos + 1 vídeo 90s 720p |
| 9 | Pedidos de oração | |
| 10 | Agenda | só texto; sem mídia pesada |
| 11 | Minha escala | |
| 12 | Escala geral | |
| 13 | Cartão membro | Carteirinha digital; atalho rodapé após Início |
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

### Rodapé mobile (ordem fixa 2120)

```
Início → Cartão → Agenda → Membros → Avisos → Eventos → YahwehChat
→ Dízimos / Visitantes / Orações / Escala / Utilitários (extras roláveis)
```

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

## Novidades 2026-07-20 (obrigatorio preservar)

### Rodapé + Cartão membro

1. Atalho **Cartão** no rodapé (índice 13) logo após Início.
2. Ordem completa: Início / Cartão / Agenda / Membros / Avisos / Eventos / YahwehChat / extras.
3. Self-only: `MemberCardPage` com `cnhFullscreenOnly`; staff mantém abas gestão.
4. Voltar ao Painel via `ModuleHeaderPremium` em todos os módulos (exceto índice 0).

### Permissões / self-only membros

- `AppPermissions.isSelfOnlyMemberAccess` — membro comum nunca vê diretório.
- `MembersPage` load self-only; sem realtime de directory.
- Rules: `canReadAllMembros` / `canReadOwnMembroDoc`; `_panel_cache/members_directory` só staff.
- CRUD alinhado: líder mural só apaga o que criou; fornecedores/patrimônio/financeiro granulares; cadastro igreja só gestão.

### Uploads / chat

- Timeouts chat mídia ~90s; gate Firebase 8s; fila só com payload.
- Sem compressão duplicada no pipeline transacional.
- Batch avisos timeout ~55s.
- `ChurchCtModuleUpload` + `YahwehFilePicker` (file_picker 11 sem `.platform`).
- `formatUploadErrorForUser` só em `firebase_user_facing_error` (facade não reexporta).

### Mídia / upload (padrao CT + anti-hang) — herdado 2118

1. Picker → **bytes** (`Uint8List`) — **nunca** `putFile` na Web.
2. Comprimir (JPEG/WebP; vídeo H.264 720p eventos).
3. Upload Storage path: `igrejas/{churchId}/{modulo}/…` via facade / EcoFire / `YahwehMediaUploadPipeline`.
4. `getDownloadURL` com timeout curto + soft-fail → aceitar **path-only**.
5. Validar → gravar Firestore **uma vez** (`storagePath` + URL se disponível).
6. Offline mobile: fila em disco + `BackgroundUploadWorker`.
7. **Proibido:** fila `pending_uploads` Firestore no hot path; hang infinito em URL.

### Cache módulos (anti-sumiço) — herdado

- Load services: **não** sobrescrever RAM/Hive com lista vazia da rede se já havia dados.
- Pós-save: evitar `invalidate` destrutivo desnecessário.
- Módulos: patrimônio, financeiro, fornecedores (e padrão similar agenda/eventos).

### Chat Igreja

- Texto otimista; mídia Storage → Firestore.
- DM: abrir thread **já** (peer local); `ensureDm` em background.
- Path: `igrejas/{churchId}/chats/.../messages`; Storage `chat_media/`.

### Mercado Pago

- Igreja: `igrejas/{churchId}/config/mercado_pago` (+ `private/mercado_pago` se existir).
- Master: `config/mercado_pago` (coleção raiz) — **não apagar** em limpezas de tenant.
- Script limpeza BPC preserva docs MP da igreja.

### Limpeza / piloto

- Script: `scripts/cleanup_bpc_keep_membros_only.cjs` (`--execute`, `--also-legacy`).
- Keep: `membros` + `config/mercado_pago` + `private/mercado_pago`.

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
| Upload / midia | `ChurchMediaUploadFacade`, `ChurchCtModuleUpload`, `StorageService`, `YahwehMediaUploadPipeline`, `DirectStorageUrlPublish`, `upload_storage_task` |
| Avisos / Eventos | `PublicationEngine`, `AvisoStrictPublishService`, `EventoStrictPublishService` |
| Chat | `ChurchChatService`, `ChurchChatFastSendService`, `ChatStrictPublishService`, `church_member_contact_chat` |
| Load / cache | `church_*_load_service.dart` (patrimonio, finance, fornecedores, agenda, eventos…) |
| Dashboard | `IgrejaDashboardModerno`, `ChurchTenantDashboardDocService`, `_panel_cache` |
| Pagamentos | `BillingService`, Mercado Pago functions, `church_donations_page` |
| Utilitarios | `utilitarios_photo_service`, `utilitarios_local_service`, OCR service |
| Sync offline | `SyncEngine`, `HiveLocalStore`, `TenantOfflineWrite` |
| Permissões | `AppPermissions`, `ChurchRolePermissions`, `roles_permissions.dart` |

Utils: `firestore_web_guard`, `yahweh_file_picker`, `immediate_media_attach_feedback`, `safe_network_image`.

---

## Cloud Functions (resumo)

Projeto `gestaoyahweh-21e23` — `functions/src/index.ts` + siblings:

- Billing / Play / Mercado Pago (licenças + doações igreja)
- Push FCM (`pushNovoConteudo`, agenda)
- Feed / mídia bridges (`gyAdminUpsertFeedPost`, `gyPublicMemberSignup`, etc.)
- Cache público / dashboard stats
- Chat retention / cleanup Storage
- Admin / auditoria / force version helpers
- `setUserActive` — confirmado OK no retry 2026-07-20

Deploy: passo `[2/6]` de `deploy_completo.ps1` ou `firebase deploy --only functions`.

---

## Firebase — paths canonicos

### Firestore

```
igrejas/{churchId}/
  membros, avisos, eventos, patrimonio, finance,
  chats/{chatId}/messages, departamentos, cargos, visitantes,
  escalas, agenda, fornecedores, fornecedor_compromissos,
  _panel_cache/*, _dashboard_cache/*, config/mercado_pago

users/{uid}                 # perfil Auth global
app_public/*                # marketing / site institucional
public_church_slugs/{slug}  # leitura publica; write CF
config/appVersion           # force update
config/mercado_pago         # Mercado Pago Master (ADM)
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
| `firestore.rules` | ACL tenant; chats/membros/finance/avisos/eventos; self-only membros |
| `storage.rules` | Escrita só sob `igrejas/{churchId}/…` (+ `public/` marketing) |
| `firestore.indexes.json` | Listas painel, feeds, chats, finance, escalas |
| `firebase.json` | Hosting → `flutter_app/build/web` |

Publicar regras (autorizado): `.\scripts\regras_gcp_automatico_forcado.ps1` ou passo `[1/6]` do deploy completo.

**Nota 2120:** Storage OK; Firestore rules/índices — se API 503, repetir `-ForcePublish` (não bloqueia web/AAB).

---

## Deploy / Codemagic

```powershell
cd C:\gestao_yahweh_premium_final
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
.\scripts\deploy_completo.ps1 -CopyTo "D:\Temporarios" -ForceFunctions
.\scripts\publish_force_update_online.ps1   # so apos validar
```

| Item | Valor |
|------|-------|
| Branch iOS | `main` |
| Commit release | `9721fd1` |
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
scripts/cleanup_bpc_keep_membros_only.cjs
codemagic.yaml
firebase.json / firestore.rules / storage.rules / firestore.indexes.json
flutter_app/lib/app_version.dart
flutter_app/lib/core/church_shell_indices.dart
flutter_app/lib/core/church_storage_layout.dart
flutter_app/lib/core/repositories/church_repository.dart
flutter_app/lib/ui/igreja_clean_shell.dart
flutter_app/lib/ui/admin_panel_page.dart
flutter_app/lib/ui/pages/members_page.dart
flutter_app/lib/ui/pages/member_card_page.dart
flutter_app/lib/services/app_permissions.dart
flutter_app/lib/services/publication_engine.dart
flutter_app/lib/services/church_chat_service.dart
flutter_app/lib/services/church_ct_module_upload.dart
flutter_app/lib/services/church_patrimonio_load_service.dart
flutter_app/lib/services/church_finance_load_service.dart
functions/src/index.ts
prompt_mestre_cursor.md
AGENTS.md
```

---

## Checklist pos-release (2120)

- [x] Web `version.json` online = `2120`
- [x] AAB em `D:\Temporarios\…build2120…aab`
- [x] ZIP iOS em `D:\Temporarios\…build2120.zip`
- [x] Push `main` `9721fd1`
- [x] Force update `config/appVersion` 2120
- [x] Cloud Functions (incl. `setUserActive`)
- [x] Storage rules OK
- [ ] Firestore rules/índices GCP (repetir se 503 persistir)
- [ ] Start Codemagic → TestFlight
- [ ] Upload AAB Play Console (versionCode **2120** > ultimo publicado)
- [ ] Ctrl+F5 web — painel igreja + master; rodapé Cartão/Membros
- [ ] Android: instalar AAB — cartão / chat / avisos / eventos / patrimônio / financeiro
- [ ] BPC: confirmar Mercado Pago da igreja nas Configurações se necessário

---

## Sessão 2026-07-20 — Membros / Patrimônio (código local, SEM deploy)

### Patrimônio
- Lista/detalhe leem slots `foto01`…`foto05` via `ChurchCanonicalMediaContract`.
- Delete Firestore+Storage; máx. 5 fotos; pending cache no card.
- Storage: `create/update` vs `delete` separados em `patrimonio`.

### Membros — foto automática (padrão CT)
- Path canônico: `igrejas/{churchId}/membros/{folder}/foto_perfil.jpg`.
- `fotoUrl` / `fotoThumbUrl` / `photoStoragePath` / `fotoUrlCacheRevision`.
- Diretório: merge respeita `fotoUrlCacheRevision` (evita foto velha no cache).
- Save: invalidação de cache **síncrona** + sync `users` / Auth / chat.
- Cartão: `imageCacheRevision` + foto full.
- UI: texto “atualização automática…”.

### Cadastro público
- Visitante: doc id aleatório + **sempre** `gyPublicMemberSignup` (Web/Android/iOS).
- CF: auth, validação, anti-duplicata CPF/email, força `pendente`, remove privilégios.
- Firestore rules mais estritas no create/update público.
- Storage membros: delete separado (como patrimônio).

### Deploy
- **NÃO** publicar até ordem explícita no final de todas as correções pedidas.

---

## Proxima manutencao

- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2120.mdc`
- Documento unico: **este arquivo** (`PONTO_BASE_MEMORIA_2026-07-20_11.2.305+2120.md`)
- Proximo build: so `+N` / `appBuildNumber` (marketing `11.2.305` ate ordem explicita)
- Ao criar nova memoria: renomear/substituir este ficheiro + a regra `.mdc` e **apagar** a memoria anterior (como Controle Total)
