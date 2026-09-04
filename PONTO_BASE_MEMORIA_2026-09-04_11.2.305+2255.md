# Ponto Base de Memória — Gestão YAHWEH (GERAL)

**Data:** 2026-09-04
**Release de referência:** `11.2.305+2255`
**Marketing:** `11.2.305`
**Build / versionCode:** `2255`
**Git:** `main` — entrega de eventos e release `2255`
**Web + forceUpdate:** `config/appVersion` com `latestVersion/publishedBuild=11.2.305+2255`, `minBuildNumber=2254` preservado, `forceUpdate=true`, `webRefresh=true`
**Anterior:** `PONTO_BASE_MEMORIA_2026-09-02_11.2.305+2254_ARQUIVADA.md`

**Firebase:** `gestaoyahweh-21e23`
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`
**Web produção:** https://gestaoyahweh-21e23.web.app

**Este é o único ponto de memória ativo.**

## Regras principais

- Evoluir serviços existentes, sem duplicatas, mantendo arquitetura offline-first.
- Não mudar o marketing `11.2.305` sem ordem explícita; incrementar apenas o build.
- Paridade Web/Android/iOS e paths canônicos `igrejas/{churchId}/…`.
- Upload de mídia: Storage → validar → Firestore uma vez.
- Build/deploy apenas mediante autorização explícita.

## Entrega 2255 — Eventos

- Somente eventos permanentes (sem validade) são arquivados na Galeria.
- Evento com validade permanece visível até 24 horas depois do vencimento e então é removido do Firestore, subcoleções e pasta canônica no Storage.
- Função agendada `scheduledCleanupExpiredTemporaryEvents`, região `us-central1`, a cada 6 horas, confirmada `ACTIVE`.
- Feed do painel, módulo Eventos e site público usam padrão social: mídia primeiro, texto abaixo e ações comentar/compartilhar depois.
- Site público reproduz fotos e vídeos de eventos no mesmo carrossel.

## Release e artefatos

- `flutter_app/lib/app_version.dart`: `11.2.305+2255`.
- `flutter_app/pubspec.yaml`: `version: 11.2.305+2255`.
- `flutter_app/web/version.json`: `11.2.305`, build `2255`, UTF-8 sem BOM.
- AAB Play: `D:\Temporarios\GestaoYahweh_11.2.305_build2255_play.aab` — 237503604 bytes — SHA-256 `DB5B8C3908EF08292A0E48B69BF87B2AF39D539928F909DF3B422175E90E7AAD`.
- ZIP iOS: `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2255.zip` — 108279324 bytes — SHA-256 `1ACFA5852B03EC63917E08DB9ECE87C27D6DAF4F43B1AB9845E828D450458073`.
- AAB validado: MainActivity, AD_ID e 62 bibliotecas `.so` compatíveis com páginas de 16 KB. Bundletool local não estava instalado; essa validação opcional foi ignorada.

## Firebase / backend

- Firestore Rules, Storage Rules e índices publicados e validados pelo deploy completo.
- Cloud Functions publicadas; limpeza temporária confirmada ativa.
- Hosting publicado com build `2255`.
- `minBuildNumber=2254` foi preservado para não bloquear usuários antes da aprovação nas lojas.

## iOS / GitHub Actions

- Repositório: `raihom-netizen/com.gestaoyahwehios.app`, branch `main`.
- Workflow: `.github/workflows/ios_testflight.yml`, disparo manual, runner `macos-26` e Xcode 26+ com SDK iOS instalado.
- Build: `flutter build ios --release --no-codesign` → archive → export IPA → TestFlight.
- Preservar Sign in with Apple, Push, App Groups, Widget, perfis e `.env.example`; nunca incluir `.env`.