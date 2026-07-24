# Ponto Base de Memoria — Gestão YAHWEH (GERAL)

**Data:** 2026-07-21 / 2026-07-22  
**Release de referencia:** `11.2.305+2122`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2122`  
**Git (deploy 2122):** `c1b82eb` (`main`) — correção iOS Widget/App Groups em commit seguinte  
**Deploy completo:** 2026-07-21 — functions + web + AAB + ZIP iOS + push + force update  
**Web + forceUpdate:** `config/appVersion` → `minBuildNumber: 2122`, `forceUpdate: true`, `latestVersion: 11.2.305+2122`  
**Anterior memoria:** `PONTO_BASE_MEMORIA_2026-07-20_11.2.305+2120.md` — **removida** (substituida por este ficheiro)

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
| `flutter_app/lib/app_version.dart` | `appVersion='11.2.305'`, `appBuildNumber='2122'` |
| `flutter_app/pubspec.yaml` | `11.2.305+2122` |
| `flutter_app/web/version.json` | `"version":"11.2.305"`, `"build_number":"2122"` |
| Android `targetSdk` / `compileSdk` | **36** (pedido Play / API 36) |

### Artefatos desta release

| Artefato | Caminho |
|----------|---------|
| AAB Play | `D:\Temporarios\GestaoYahweh_11.2.305_build2122_play.aab` (~191 MB / 200374426 bytes) |
| ZIP iOS Codemagic | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2122.zip` (~1 MB) |
| Site | https://gestaoyahweh-21e23.web.app / https://gestaoyahweh.com.br |
| `version.json` web online | `11.2.305+2122` |

---

## Confirmado na 2122

| Melhoria | Status |
|----------|--------|
| Android **targetSdk/compileSdk 36** (Play) | No codigo + AAB 2122 |
| Precos oficiais +R$10; anual = 10× mensal; texto “pague 10 meses use 12” | plan_price / seed / functions / site / admin |
| Leitura publica `config/plans/items` (`allow read: if true`) | Rules locais; **republicar** se GCP 503 |
| Remocao Google Drive backup das functions (se aplicavel no deploy) | Deploy 2122 |
| Force update `config/appVersion` 2122 | Feito no deploy |
| Codemagic iOS: **App Groups + Widget** (`GestaoYahwehWidgetExtension`) | Correcao pos-falha Bootstrap sem App Groups |

### iOS / Codemagic (critico 2122+)

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL`
- Pipeline: ativar App Groups (API, **grupo confirmado na capability**) → apagar perfis App Store antigos → fetch perfil app + widget (retry se `application-groups: []`) → `use-profiles` Runner+extension → ExportOptions com **dois** bundles
- `DEVELOPMENT_TEAM` no target Widget; fail-fast se perfil sem App Groups
- **Fix 2026-07-22:** capability APP_GROUPS vazia gerava perfil Widget com `application-groups: []` — scripts `codemagic_ios_enable_app_groups.py` + `codemagic_ios_ensure_widget_appstore_profile.py` agora reassociam o grupo, apagam perfil mau e recriam até o grupo aparecer.
- Branch: **`main`** — Start **manual** no Codemagic (so iOS)

### Herdado da 2120 / 2118 (preservar)

- Rodape: Início → Cartão → Agenda → Membros → Avisos → Eventos → YahwehChat (+ extras)
- Cartao membro fullscreen; self-only; permissoes CRUD; uploads/chat estaveis
- Midia soft-fail `getDownloadURL`; anti-sumico patrimonio/financeiro/fornecedores
- Offline-first + sem `terminate()` no hot path; paginacao 20
- Storage layout canonico; chat `igrejas/{id}/chats`

### Pendencias

- [ ] Upload AAB **2122** na Play Console (versionCode > ultimo publicado; API 36)
- [ ] Codemagic Start manual apos push da correcao Widget/App Groups → TestFlight
- [ ] Firestore rules: se API 503/hang, **2 etapas** — primeiro ruleset **simples**, depois o **completo** (memória `firestore-rules-publicar-duas-etapas.mdc`); depois `.\scripts\deploy_firebase_rules.ps1 -ForcePublish` / `deploy_firebase_rules_duas_etapas.ps1`

---

## Checklist pos-release (2122)

- [x] Web `version.json` online = `2122`
- [x] AAB em `D:\Temporarios\…build2122…aab`
- [x] ZIP iOS em `D:\Temporarios\…build2122.zip`
- [x] Force update `config/appVersion` 2122
- [ ] Play Console AAB 2122
- [ ] TestFlight IPA (apos fix App Groups)

---

## Referencias Cursor

- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2122.mdc`
- Documento unico: **este arquivo** (`PONTO_BASE_MEMORIA_2026-07-21_11.2.305+2122.md`)
- Memoria `*2120*` **nao** usar — removida
