# Base estável — Gestão YAHWEH (produção)

**Tag Git:** `baseline-11.2.295-1819`  
**Commit:** `30da39e` (deploy completo 2026-06-05)  
**Versão:** `11.2.295+1819`

Ponto de partida **antes das próximas melhorias** (jun/2026). Base validada em produção: web online, AAB Play, push GitHub, correções carteirinha, chat igreja, avisos e eventos.

## Antes de cada melhoria ou deploy

1. **Toolchain no PATH** (PowerShell na raiz; inclui **gcloud** auto):
   ```powershell
   . .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
   firebase --version
   flutter --version
   gcloud --version
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
- IPA no CI: sempre **`GestaoYahweh.ipa`** após `codemagic_ios_normalize_ipa_for_asc.sh`.
- Chat/avisos/eventos: `prepareForChatWrite` / leituras resilientes — não reintroduzir `prepareForCriticalWrite` a cada envio.

## Dart — evitar regressão de compilação

- Parâmetros opcionais com valor por defeito exigem **expressão constante** (`const`).
- Não usar getters (`kEffectiveMuralFeedWebpQuality`) como default; passar na chamada ou usar `kPremiumMuralFeedWebpQuality` (const).

## Artefactos de referência (último deploy)

| Artefacto | Caminho típico |
|-----------|----------------|
| Web | https://gestaoyahweh-21e23.web.app |
| AAB | `D:\Temporarios\GestaoYahweh_11.2.295_build1819_play.aab` |
| ZIP iOS | `D:\Temporarios\GestaoYahweh_ios_sources_11.2.295_build1819.zip` |
| Backup geral | `D:\Temporarios\bkp_estado_geral_2026-06-05_build1819\` |

## Voltar a esta base

```powershell
git fetch origin
git checkout baseline-11.2.295-1819
```

Restaurar a partir do bundle (máquina nova):

```powershell
git clone gestao_yahweh_11.2.295_1819.bundle gestao_yahweh_restored
cd gestao_yahweh_restored
git checkout baseline-11.2.295-1819
```

## Baseline anterior

- `baseline-11.2.295-1603` — commit `e77b4b5` (2026-05-22)
