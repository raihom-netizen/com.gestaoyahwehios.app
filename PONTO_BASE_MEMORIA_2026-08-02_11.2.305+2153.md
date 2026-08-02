# Ponto Base de Memória — Gestão YAHWEH (GERAL)

**Data:** 2026-08-02  
**Release de referência:** `11.2.305+2153`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2153`  
**Git:** `main` — commit `3710feb`  
**Web + forceUpdate:** `config/appVersion` = `11.2.305+2153`, `minBuildNumber=2153`, `forceUpdate=true`, `webRefresh=true`  
**Anterior:** `PONTO_BASE_MEMORIA_2026-07-30_11.2.305+2145.md` (arquivada)

**Firebase:** `gestaoyahweh-21e23`  
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
**Web produção:** https://gestaoyahweh-21e23.web.app

**Este é o único ponto de memória ativo.**

---

## Regra principal

- Toda melhoria parte deste ponto: **somar sem regredir**.
- Não mudar `appVersion` (`11.2.305`) sem ordem explícita; incrementar apenas `appBuildNumber` / `+N`.
- **Paridade obrigatória:** Web + Android + iOS e paths `igrejas/{churchId}/…`.
- Cache-first, paginação 20, sem scans pesados no caminho quente e sem cache vazio apagar dados válidos.
- Deploy/build somente com pedido explícito e ao final.
- Painel pós-login usa `ChurchRepository`; proibidos novos resolvers, `*ServiceV2` e novas escritas em `tenants/{id}`.
- Publicação de mídia: Storage → validar → Firestore uma vez.
- Chat principal de produção: Yahweh Chat (Firestore) + TDLib (Telegram in-app) no Android; iOS com gate/`codemagic_ios_tdlib_auto.sh` e fallback Firebase se o linker nativo falhar.
- Web TDLib: paridade UX via Telegram Web embutido (`TdlibWebParity`) — sem FFI no browser.

---

## Versão oficial confirmada

- `flutter_app/lib/app_version.dart`: `appVersion='11.2.305'`, `appBuildNumber='2153'`
- `flutter_app/pubspec.yaml`: `version: 11.2.305+2153`
- `flutter_app/web/version.json`: `version=11.2.305`, `build_number=2153`
- Web publicada com build `2153` (confirmado em `https://gestaoyahweh-21e23.web.app/version.json`).
- Git `main` sincronizada com `origin/main` no commit `3710feb`.

## Artefatos 2153

- AAB Play: `D:\Temporarios\GestaoYahweh_11.2.305_build2153_play.aab`
  - Tamanho: `244087333` bytes
  - SHA-256: `84C0FF189F0798254CFB010106BD1868993B4E7B8C26081348611CCE6714829A`
- ZIP iOS: `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2153.zip`
  - Tamanho: `108279323` bytes
  - SHA-256: `8846C5C8B040D225BBC0EEDDC56729BA48A20564030CBD44069917ACE7089D98`

## Android / Play

- `targetSdk=36`, `compileSdk=36`, NDK `28.2.13676358`.
- AGP `8.13.2`.
- R8 otimizado ativo:
  - `isMinifyEnabled=true`
  - `isShrinkResources=true`
  - `android.r8.optimizedResourceShrinking=true`
- AAB release assinado, ofuscado, validado (MainActivity, AD_ID, 16K) e copiado para `D:\Temporarios`.
- TDLib Android no artefato; push background via `tdlibFirebaseMessagingBackgroundHandler` + `TdlibBackgroundPushStore`.
- **Pendente externo:** carregar/processar o AAB `2153` na Play Console.

## Firebase / backend

- Firestore rules: remoto = local, `OK` (preflight deploy 2153).
- Storage rules: remoto = local, `OK`.
- Firestore indexes: remoto = local, `OK`.
- Cloud Functions: deploy completo na passagem inicial do release; republicação posterior sem alterações detectadas.
- Documento remoto `config/appVersion` confirmado em `11.2.305+2153` (`forceUpdate=true`, `webRefresh=true`).
- Se a API Rules retornar 429/503: fluxo simples → completa; nunca deixar bridge como release final.

## Yahweh Chat / TDLib — build 2153

- Hub TDLib: conversas/grupos/contatos, mute/arquivo, filtro igreja, sync, atalhos busca/sessões/dashboard.
- Thread: voz, mídia, retry, rascunhos, typing, pin, forward, reações, presença.
- Push app fechado: isolate FCM + paths de sessão; foreground FCM/APNs.
- Web: banner/CTA Telegram Web (`TdlibWebParity`).
- iOS: `YAHWEH_TDLIB_IOS_ENABLED` + `scripts/codemagic_ios_tdlib_auto.sh` (try-native / auto-fallback).
- Correção crítica no deploy: `tdlib_background_push_io.dart` restabelecido (export recursivo quebrava o AAB).

## Mídia e módulos críticos — build 2153

- Uploads e exibição reforçados em Avisos, Eventos, Chat, Master, site e cadastro público.
- Microfone iOS: permissão nativa sequencial + Ajustes se permanentemente negado.
- Chat preserva conversas/grupos diante de resultados vazios transitórios.
- Patrimônio confirma upload + Firestore antes do sucesso.
- Financeiro e Fornecedores: comprovantes pelo `storagePath` canônico.
- Utilitários / YouTube embed / galeria Instagram: evolução incremental no mesmo release.

## iOS / Codemagic

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL`
- Branch: `main`; Codemagic somente iOS e início **manual**.
- Preservar Sign in with Apple, Push, App Groups, perfis, entitlements, IPA e validação ASC.
- Soft-fail TDLib nativo: se linker falhar → Yahweh Chat Firebase, sem crash.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.
- **Pendente externo:** disparar build Codemagic a partir de `3710feb` e confirmar IPA/TestFlight.

## Preservar crítico

- Offline-first + `FirestoreWebGuard`, sem `terminate()` no hot path.
- `PublicationEngine`, `ChurchRepository`, `ChurchStorageLayout` e chat `igrejas/{id}/chats`.
- Anti-sumiço de patrimônio, financeiro, fornecedores e conversas.
- Mídia path-only/soft-fail e Web sem `putFile`.
- Menus/drawers fora de `SelectableRegion`.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.
- Não forçar TDLib iOS nativo em produção sem validar archive e aparelho real.

## Aceite

- Deploy técnico `2153`: **APROVADO** para Web, AAB, ZIP iOS, regras, índices, Git, force update e functions (passagem inicial).
- Build IPA/TestFlight: **INCOMPLETO** até o Codemagic concluir a partir do commit `3710feb`.
- Aceite funcional E2E Web/Android/iOS: **INCOMPLETO** até executar DEBUG CHURCH e testes 1–11 nas três plataformas.
- Play: **INCOMPLETO** até upload e processamento externo do AAB `2153`.

## Referências

- Ponto ativo: `PONTO_BASE_MEMORIA_2026-08-02_11.2.305+2153.md`
- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2153.mdc`
- Memórias `2145`, `2143`, `2134`, `2122` e anteriores são históricas.
