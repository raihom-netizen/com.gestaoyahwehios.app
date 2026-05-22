# Base estável — Gestão YAHWEH (produção)

**Tag Git:** `baseline-11.2.295-1603`  
**Commit:** `e77b4b5` (deploy completo 2026-05-22)  
**Versão:** `11.2.295+1603`

Esta base foi validada em produção: web online, AAB Play, push GitHub, correções iOS (TestFlight) e upload rápido (chat / avisos / eventos).

## Antes de cada melhoria ou deploy

1. **Toolchain no PATH** (PowerShell na raiz):
   ```powershell
   . .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
   firebase --version
   flutter --version
   ```
2. **Análise Dart** (ficheiros alterados ou gate global):
   ```powershell
   .\scripts\flutter_analyze_relax.ps1
   ```
   Corrigir sempre linhas `error -` antes de merge/deploy.
3. **Versão** (só quando for entregar build nova): alinhar `app_version.dart`, `pubspec.yaml`, `web/version.json` — ver `.cursor/rules/controle-versao.mdc`.

## Deploy completo (autorizado)

```powershell
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
.\scripts\deploy_completo.ps1 -CopyTo "D:\Temporarios"
```

## iOS (Codemagic / TestFlight)

- `Info.plist`: **sem** `remote-notification` em `UIBackgroundModes` enquanto não houver `aps-environment` no perfil.
- `LSApplicationQueriesSchemes`: **sem** `http` / `https`.
- CI valida IPA: `scripts/codemagic_ios_validate_ipa_before_upload.sh`
- Guia: `IOS/CODEMAGIC_INVALID_BINARY.md`
- IPA no CI: sempre **`GestaoYahweh.ipa`** após `codemagic_ios_normalize_ipa_for_asc.sh` (evita falha Publishing com «Gestão Yahweh - Igrejas.ipa»).
- Upload rápido (chat/avisos/eventos): regras Firestore `chatTenantMemberFast`, `muralPostPublishFinalizeAllowed` — deploy `.\scripts\deploy_firebase_rules.ps1` (sem nova versão do app).

## Dart — evitar regressão de compilação

- Parâmetros opcionais com valor por defeito exigem **expressão constante** (`const`).
- Não usar getters (`kEffectiveMuralFeedWebpQuality`) como default; passar na chamada ou usar `kPremiumMuralFeedWebpQuality` (const).

## Artefactos de referência (último deploy)

| Artefacto | Caminho típico |
|-----------|----------------|
| Web | https://gestaoyahweh-21e23.web.app |
| AAB | `D:\Temporarios\GestaoYahweh_11.2.295_build1603_play.aab` |
| ZIP iOS | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.295_build1603.zip` |

## Voltar a esta base

```powershell
git fetch origin
git checkout baseline-11.2.295-1603
```
