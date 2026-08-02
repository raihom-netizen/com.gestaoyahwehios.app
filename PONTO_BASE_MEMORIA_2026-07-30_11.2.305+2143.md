# Ponto Base de Memória — Gestão YAHWEH (ARQUIVADA)

**Data:** 2026-07-30  
**Release de referencia:** `11.2.305+2143`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2143`  
**Git:** `main` — commit `bfb8a5a`  
**Web + forceUpdate:** `config/appVersion` = `11.2.305+2143`, `minBuildNumber=2143`, `forceUpdate=true`, `webRefresh=true`  
**Anterior:** `PONTO_BASE_MEMORIA_2026-07-24_11.2.305+2134_ARQUIVADA.md`

**Firebase:** `gestaoyahweh-21e23`  
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
**Web producao:** https://gestaoyahweh-21e23.web.app  

**Memória histórica. Ponto ativo:** `PONTO_BASE_MEMORIA_2026-07-30_11.2.305+2145.md`

---

## Regra principal

- Toda melhoria parte deste ponto: **somar sem regredir**.
- Nao mudar `appVersion` (`11.2.305`) sem ordem explicita; incrementar apenas `appBuildNumber` / `+N`.
- **Paridade obrigatoria:** Web + Android + iOS e paths `igrejas/{churchId}/…`.
- Cache-first, paginacao 20, sem scans pesados no caminho quente e sem cache vazio apagar dados validos.
- Deploy/build somente com pedido explicito e ao final.
- Painel pos-login usa `ChurchRepository`; proibidos novos resolvers, `*ServiceV2` e novas escritas em `tenants/{id}`.
- Publicacao de midia: Storage → validar → Firestore uma vez.
- Chat principal: Yahweh Chat nativo/Firestore; TDLib nao volta para a UI principal.

---

## Versao oficial confirmada

- `flutter_app/lib/app_version.dart`: `appVersion='11.2.305'`, `appBuildNumber='2143'`
- `flutter_app/pubspec.yaml`: `version: 11.2.305+2143`
- `flutter_app/web/version.json`: `version=11.2.305`, `build_number=2143`
- Web publicada e consultada online com build `2143`.
- Git `main` sincronizada com `origin/main` no commit `bfb8a5a`.

## Artefatos 2143

- AAB Play: `D:\Temporarios\GestaoYahweh_11.2.305_build2143_play.aab`
  - Tamanho: `231079868` bytes
  - SHA-256: `206B0DB16530393BA9888A5365AE5E300667070B8065CA4FB3C8DAE4A2163FB2`
- ZIP iOS: `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2143.zip`
  - Tamanho: `108279087` bytes
  - SHA-256: `0431AAB01162235F0422B809E811BBD6BF1C12CD43866C2832960AEC78FB61CC`
- Log: `D:\Temporarios\deploy_completo_2143_2026-07-30.log`

## Android / Play

- `targetSdk=36`, `compileSdk=36`, NDK `28.2.13676358`.
- AGP `8.13.2` mantido por compatibilidade com plugins Flutter que ainda aplicam Kotlin Gradle Plugin.
- R8 otimizado ativo:
  - `isMinifyEnabled=true`
  - `isShrinkResources=true`
  - `android.r8.optimizedResourceShrinking=true`
- AAB release assinado, ofuscado, MainActivity validada, AD_ID confirmado e 62 bibliotecas `.so` validadas para page size 16K.
- **Pendente externo:** carregar o AAB `2143` na Play Console e aguardar processamento. O force update `2143` ja esta ativo.

## Firebase / backend

- Firestore rules: remoto = local, `OK`.
- Storage rules: remoto = local, `OK`.
- Firestore indexes: remoto = local, `OK`.
- Todas as Cloud Functions foram compiladas e publicadas no deploy completo.
- Documento remoto `config/appVersion` confirmado em `11.2.305+2143`.
- Nenhuma migracao ad hoc de dados foi necessaria neste release.
- Se a API Rules retornar 429/503: fluxo simples → completa; nunca deixar bridge como release final.

## iOS / Codemagic

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL`
- Branch: `main`; Codemagic somente iOS e Start manual.
- Preservar Sign in with Apple, Push, App Groups, perfis, align entitlements, IPA e validação ASC.
- **Pendente externo:** iniciar build `2143` no Codemagic e confirmar IPA/TestFlight.

## Preservar critico

- Offline-first + `FirestoreWebGuard`, sem `terminate()` no hot path.
- `PublicationEngine`, `ChurchRepository`, `ChurchStorageLayout` e chat `igrejas/{id}/chats`.
- Anti-sumico de patrimônio, financeiro e fornecedores.
- Mídia path-only/soft-fail e Web sem `putFile`.
- Menus/drawers fora de `SelectableRegion`.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.

## Aceite

- Deploy técnico `2143`: **APROVADO** (Web, AAB, ZIP iOS, regras, índices, Functions, Git e force update confirmados).
- Aceite funcional E2E Web/Android/iOS: **INCOMPLETO** até executar DEBUG CHURCH e testes 1–11 nas três plataformas.
- Play/TestFlight: **INCOMPLETO** até upload/processamento externo dos artefatos.

## Referências históricas

- Regra superseded: `.cursor/rules/ponto-base-memoria-11-2-305-2143.mdc`
- Ponto ativo: `PONTO_BASE_MEMORIA_2026-07-30_11.2.305+2145.md`
