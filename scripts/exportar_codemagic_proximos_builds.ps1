# Exportação para próximos builds iOS na Codemagic (disparo SEMPRE manual por si).
# Não inicia build. Gera pasta em D:\Temporarios para colar secrets / referência.
#
# Uso (raiz do repo):
#   .\scripts\exportar_codemagic_proximos_builds.ps1
#
# Antes (se tiver Mac): copie para IOS\  →  .p12 Apple Distribution  +  .mobileprovision App Store
param(
    [string]$OutRoot = "D:\Temporarios\GESTAO_YAHWEH_CODEMAGIC_MANUAL"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EncodeScript = Join-Path $RepoRoot "scripts\encode_ios_codemagic_secrets.ps1"

if (-not (Test-Path $OutRoot)) {
    New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
}

# Limpar cópias antigas desta exportação
Get-ChildItem -Path $OutRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $OutRoot -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$manual = @"
GESTÃO YAHWEH — Codemagic iOS (builds só MANUAIS)
=================================================
Gerado: $(Get-Date -Format "yyyy-MM-dd HH:mm")

POLÍTICA
--------
• O repositório NÃO dispara build iOS no push (sem «triggering» no codemagic.yaml).
• Você dispara quando quiser: Codemagic → Start new build → workflow
  «iOS Build - Gestao YAHWEH (TestFlight)» → branch main.

SE A UI FICAR «Branches are loading»
------------------------------------
• Application settings → Repository → Reconnect GitHub
• Ou «Build commit» com o hash do último push (git log -1)
• Ou API: .\scripts\trigger_codemagic_ios_build.ps1 (opcional; precisa token)

SECRETS (grupo appstore_credentials) — modo automático (só .p8)
---------------------------------------------------------------
  APP_STORE_CONNECT_PRIVATE_KEY   = IOS\AuthKey_85X9UNAT43.p8 (multilinha)
  APP_STORE_CONNECT_KEY_IDENTIFIER = 85X9UNAT43  (ou no YAML)
  APP_STORE_CONNECT_ISSUER_ID      = 77a1debb-f68b-418d-9fe3-af0f37b40585

  Opcional (se já tiver par estável): CM_CERTIFICATE + CM_PROVISIONING_PROFILE (Base64)
  → ficheiros em subpasta secrets\ desta exportação (se existirem .p12/.mobileprovision em IOS\)

DEPLOY COMPLETO (Firebase + AAB + ZIP iOS) SEM disparar Codemagic
-----------------------------------------------------------------
  .\scripts\deploy_completo.ps1 -SkipGitPush

Depois faça push ou build manual na Codemagic quando quiser o IPA.

VALIDAÇÃO NO BUILD
------------------
Passo «Verificar variaveis» → OK: modo API-only automático
Passo 11 → OK: identidade Apple Distribution no keychain

Repo: https://github.com/raihom-netizen/com.gestaoyahwehios.app.git
"@
$manualPath = Join-Path $OutRoot "00_DISPARO_BUILD_MANUAL.txt"
[IO.File]::WriteAllText($manualPath, $manual.TrimStart(), [Text.UTF8Encoding]::new($false))

$secretsDir = Join-Path $OutRoot "secrets"
New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null

if (Test-Path $EncodeScript) {
    Push-Location $RepoRoot
    try {
        & $EncodeScript
    } catch {
        Write-Host "AVISO: encode_ios_codemagic_secrets: $_" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
    $srcSecrets = "D:\Temporarios\gestao_yahweh_codemagic"
    if (Test-Path $srcSecrets) {
        Get-ChildItem -Path $srcSecrets -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $secretsDir $_.Name) -Force
        }
    }
}

# Cópia de referência do YAML (só leitura)
$yamlSrc = Join-Path $RepoRoot "codemagic.yaml"
if (Test-Path $yamlSrc) {
    Copy-Item -LiteralPath $yamlSrc -Destination (Join-Path $OutRoot "codemagic.yaml.referencia") -Force
}

Write-Host ""
Write-Host "OK: exportação em $OutRoot" -ForegroundColor Green
Write-Host "  00_DISPARO_BUILD_MANUAL.txt"
if (Test-Path $secretsDir) {
    $n = (Get-ChildItem $secretsDir -File -ErrorAction SilentlyContinue).Count
    if ($n -gt 0) { Write-Host "  secrets\ ($n ficheiros para colar na Codemagic)" }
}
Write-Host ""
Write-Host "Build iOS: dispare manualmente na Codemagic quando quiser." -ForegroundColor Cyan
try { Start-Process explorer.exe -ArgumentList $OutRoot } catch {}
