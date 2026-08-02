# Ponto Base de Memória — Gestão YAHWEH (ARQUIVADA)

**Memória histórica. Ponto ativo:** `PONTO_BASE_MEMORIA_2026-08-02_11.2.305+2153.md`

**Data:** 2026-07-30  
**Release de referência:** `11.2.305+2145`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2145`  
**Git:** `main` — commit `1b2fa7d`  
**Web + forceUpdate:** `config/appVersion` = `11.2.305+2145`, `minBuildNumber=2145`, `forceUpdate=true`, `webRefresh=true`  
**Anterior:** `PONTO_BASE_MEMORIA_2026-07-30_11.2.305+2143.md` (arquivada)

**Firebase:** `gestaoyahweh-21e23`  
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
**Web produção:** https://gestaoyahweh-21e23.web.app

**Arquivada em 2026-08-02 — não usar como memória ativa.**

---

## Regra principal

- Toda melhoria parte deste ponto: **somar sem regredir**.
- Não mudar `appVersion` (`11.2.305`) sem ordem explícita; incrementar apenas `appBuildNumber` / `+N`.
- **Paridade obrigatória:** Web + Android + iOS e paths `igrejas/{churchId}/…`.
- Cache-first, paginação 20, sem scans pesados no caminho quente e sem cache vazio apagar dados válidos.
- Deploy/build somente com pedido explícito e ao final.
- Painel pós-login usa `ChurchRepository`; proibidos novos resolvers, `*ServiceV2` e novas escritas em `tenants/{id}`.
- Publicação de mídia: Storage → validar → Firestore uma vez.
- Chat principal de produção: Yahweh Chat/Firestore.
- TDLib permanece disponível no Android. No iOS, o plugin nativo está desativado no CI até existir binário compatível com o linker atual.

---

## Versão oficial confirmada

- `flutter_app/lib/app_version.dart`: `appVersion='11.2.305'`, `appBuildNumber='2145'`
- `flutter_app/pubspec.yaml`: `version: 11.2.305+2145`
- `flutter_app/web/version.json`: `version=11.2.305`, `build_number=2145`
- Web publicada com build `2145`.
- Git `main` sincronizada com `origin/main` no commit `1b2fa7d`.

## Artefatos 2145

- AAB Play: `D:\Temporarios\GestaoYahweh_11.2.305_build2145_play.aab`
  - Tamanho: `231447156` bytes
  - SHA-256: `C3E155838EFDDB4C83C0243B2E9F9B9BA26B66731B6FF513D8D0C40798E45127`
- ZIP iOS: `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2145.zip`
  - Tamanho: `108279323` bytes
  - SHA-256: `22530D72CD1B389225E42E08E2A13448875950B4BA1B11E59B8ACC83BC1CD999`

## Android / Play

- `targetSdk=36`, `compileSdk=36`, NDK `28.2.13676358`.
- AGP `8.13.2`.
- R8 otimizado ativo:
  - `isMinifyEnabled=true`
  - `isShrinkResources=true`
  - `android.r8.optimizedResourceShrinking=true`
- AAB release assinado, ofuscado e copiado para `D:\Temporarios`.
- TDLib Android configurado no artefato nativo.
- **Pendente externo:** carregar/processar o AAB `2145` na Play Console.

## Firebase / backend

- Firestore rules: remoto = local, `OK`.
- Storage rules: remoto = local, `OK`.
- Firestore indexes: remoto = local, `OK`.
- Cloud Functions sem alterações no deploy `2145`; republicação foi corretamente ignorada.
- Documento remoto `config/appVersion` confirmado em `11.2.305+2145`.
- Se a API Rules retornar 429/503: fluxo simples → completa; nunca deixar bridge como release final.

## Mídia e módulos críticos — build 2145

- Uploads e exibição de imagens, vídeos e arquivos reforçados em Avisos, Eventos, Chat, Master, site e cadastro público.
- Microfone iOS usa permissão nativa sequencial, com abertura de Ajustes quando permanentemente negado.
- Chat preserva conversas e grupos diante de resultados vazios transitórios.
- Chat Firebase prioriza thumbnails e streaming de áudio.
- Patrimônio confirma upload das fotos e Firestore antes de mostrar sucesso.
- Financeiro e Fornecedores abrem comprovantes pelo `storagePath` canônico.
- Remoção/troca de logo e foto do membro invalida caches sem apagar diretórios indevidos.

## iOS / Codemagic

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL`
- Branch: `main`; Codemagic somente iOS e início manual.
- Preservar Sign in with Apple, Push, App Groups, perfis, entitlements, IPA e validação ASC.
- `libtdjson 0.3.0` possui `-force_load` incompatível com o `XCFrameworkIntermediates` do Xcode/CocoaPods atual.
- Commit `1b2fa7d` aplica fallback persistente após cada `flutter pub get`, removendo somente o registro nativo iOS do TDLib.
- O pacote Dart e o plugin Android permanecem disponíveis; o IPA usa Yahweh Chat Firebase.
- **Pendente externo:** executar novo build Codemagic a partir de `1b2fa7d` e confirmar IPA/TestFlight.

## Preservar crítico

- Offline-first + `FirestoreWebGuard`, sem `terminate()` no hot path.
- `PublicationEngine`, `ChurchRepository`, `ChurchStorageLayout` e chat `igrejas/{id}/chats`.
- Anti-sumiço de patrimônio, financeiro, fornecedores e conversas.
- Mídia path-only/soft-fail e Web sem `putFile`.
- Menus/drawers fora de `SelectableRegion`.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.
- Não reativar `YAHWEH_TDLIB_IOS_ENABLED` sem validar archive e execução em aparelho iOS real.

## Aceite

- Deploy técnico `2145`: **APROVADO** para Web, AAB, ZIP iOS, regras, índices, Git e force update.
- Build IPA/TestFlight: **INCOMPLETO** até o Codemagic concluir a partir do commit `1b2fa7d`.
- Aceite funcional E2E Web/Android/iOS: **INCOMPLETO** até executar DEBUG CHURCH e testes 1–11 nas três plataformas.
- Play: **INCOMPLETO** até upload e processamento externo do AAB.

## Referências

- Ponto ativo: `PONTO_BASE_MEMORIA_2026-08-02_11.2.305+2153.md`
- Esta memória `2145` e as anteriores (`2143`, `2134`, `2122`) são históricas.
