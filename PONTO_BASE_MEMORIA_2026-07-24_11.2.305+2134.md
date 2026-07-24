# Ponto Base de Memoria — Gestão YAHWEH (GERAL)

**Data:** 2026-07-24  
**Release de referencia:** `11.2.305+2134`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2134`  
**Git (codigo + CI iOS):** `main` — ver commits recentes de signing/Push/TDLib/dotenv  
**Web + forceUpdate (deploy 2134):** `config/appVersion` → `11.2.305+2134` (quando publicado)  
**Anterior memoria:** `PONTO_BASE_MEMORIA_2026-07-21_11.2.305+2122.md` — **substituida** por este ficheiro  

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
- **Chat principal = Yahweh Chat nativo** (`ChurchChatHubPage` / Firestore) — **nao** TDLib na UI principal.

---

## Versao oficial (codigo)

| Arquivo | Valor |
|---------|-------|
| `flutter_app/lib/app_version.dart` | `appVersion='11.2.305'`, `appBuildNumber='2134'` |
| `flutter_app/pubspec.yaml` | `11.2.305+2134` |
| `flutter_app/web/version.json` | alinhar no deploy |
| Android `targetSdk` / `compileSdk` | **36** |

### Artefatos (2134)

| Artefato | Caminho / nota |
|----------|----------------|
| AAB Play | `D:\Temporarios\GestaoYahweh_11.2.305_build2134_play.aab` (se gerado no deploy) |
| ZIP iOS Codemagic | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2134.zip` |
| Site | https://gestaoyahweh-21e23.web.app / https://gestaoyahweh.com.br |

---

## Confirmado na 2134 (+ fixes CI iOS 2026-07-24)

| Melhoria | Status |
|----------|--------|
| Deploy web + AAB + ZIP + force update 2134 | Feito (sessao anterior) |
| Chat UI = Yahweh Chat nativo (nao hub TDLib) | Codigo |
| `libtdjson` **removido do pubspec** (CI) | Fix archive: `flutter_libtdjson/libtdjson.a` ausente (binario gitignore) |
| Asset dotenv = **`.env.example`** (nao `.env`) | Fix archive: Missing asset `.env` |
| App Groups: capability API + Xcode REGISTER + align entitlements | Pipeline |
| Match **exacto** Bundle ID na ASC (evitar Widget antes do app) | Scripts |
| ExportOptions path no passo Aplicar perfis (`cwd` ios/) | Fix |
| **Push:** `PUSH_NOTIFICATIONS` via API + `aps-environment` + align anti Binário inválido | 2026-07-24 |

### iOS / Codemagic (critico)

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL` | ASC Key: `85X9UNAT43`
- Branch: **`main`** — Start **manual** (somente iOS; **nunca** AAB no Codemagic)
- Assinatura estavel: P12 + `CM_PROVISIONING_PROFILE` + sync ASC (`fetch_profile_matching_p12` / ensure profile)
- Pipeline (ordem): Sign In with Apple → **Push** → App Groups → registar grupos Xcode → apagar perfis antigos → P12/perfil → Widget profile → **align App Groups** → **align Push** → pods → IPA → validate IPA → ASC
- `codemagic_ios_align_push_entitlements.py`: se perfil **sem** `aps-environment`, remove Push dos entitlements **e** `remote-notification` do Info.plist (evita «Binário inválido»)
- `codemagic_ios_enable_push_notifications.py`: liga `PUSH_NOTIFICATIONS` no App ID antes de recriar perfis
- UI Codemagic por vezes fica em «codemagic.yaml is loading…» — refresh / Ctrl+F5 / `scripts/trigger_codemagic_ios_build.ps1`

### Herdado (preservar)

- Rodape: Início → Cartão → Agenda → Membros → Avisos → Eventos → YahwehChat (+ extras)
- Cartao membro fullscreen; self-only; permissoes CRUD; uploads/chat estaveis
- Midia soft-fail `getDownloadURL`; anti-sumico patrimonio/financeiro/fornecedores
- Offline-first + sem `terminate()` no hot path; paginacao 20
- Storage layout canonico; chat `igrejas/{id}/chats`
- Android API 36; precos +R$10 / anual 10×

### Pendencias

- [ ] Codemagic Start apos fix Push → TestFlight (IPA ja gerava; falhava so na validacao)
- [ ] Confirmar no log: «Perfil Runner tem aps-environment: True» (FCM background iOS)
- [ ] Se App Groups stripped: marcar `group.com…` no portal e regenerar perfis
- [ ] Firestore rules: se API 503, **2 etapas** (`firestore-rules-publicar-duas-etapas.mdc`)

---

## Checklist pos-release (2134)

- [x] Codigo marketing `11.2.305` + build `2134`
- [x] Fixes CI: libtdjson, `.env.example`, App Groups, Push align
- [ ] TestFlight IPA aceite (pos-fix Push)
- [ ] Play Console AAB (versionCode > ultimo)

---

## Referencias Cursor

- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2134.mdc`
- Documento unico: **este arquivo** (`PONTO_BASE_MEMORIA_2026-07-24_11.2.305+2134.md`)
- Memoria `*2122*` / `*2120*` **nao** usar como ponto ativo
