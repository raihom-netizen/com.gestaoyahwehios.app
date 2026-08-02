param(
    [switch]$WebOnly,
    [switch]$NoCodemagicPush,
    [switch]$Clean,
    [switch]$ForceFunctions,
    [switch]$SkipRules,
    [switch]$SkipFunctionsDeploy,
    [switch]$HostingOnly,
    [string]$CopyTo = 'D:\TEMPORARIOS',
    [string]$LogTo = ''
)
# Deploy Gestao YAHWEH — mesmo padrao rapido do Controle Total.
#
# Uso (raiz C:\gestao_yahweh_premium_final):
#   .\deploy.ps1                  -> COMPLETO: web+Firebase PRIMEIRO, depois AAB/iOS + CodeMagic
#   .\deploy.ps1 -WebOnly         -> RAPIDO: pub get + build web (SEM clean) + Firebase (sem AAB/iOS)
#   .\deploy.ps1 -WebOnly -HostingOnly -> ainda mais rapido (so hosting)
#   .\deploy.ps1 -Clean           -> inclui flutter clean (so quando necessario)
#   .\deploy.ps1 -NoCodemagicPush -> completo sem push CodeMagic
#
# Politica: NAO forcar app_config/version no deploy.
# Temporarios: D:\TEMPORARIOS. CodeMagic = so iOS (Start manual).
# Nunca firebase deploy sem Validate-HostingPreDeploy.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$flutterDir = Join-Path $root "flutter_app"
Set-Location $root

function Get-YahwehVersionInfo {
    $v = "1.0.0"; $pub = 1; $vc = 1
    $vf = Join-Path $flutterDir "lib\constants\app_version.dart"
    if (-not (Test-Path $vf)) {
        $vf = Join-Path $flutterDir "lib\core\app_version.dart"
    }
    if (Test-Path $vf) {
        $raw = Get-Content $vf -Raw
        if ($raw -match "current\s*=\s*'([^']+)'") { $v = $Matches[1] }
        if ($raw -match "buildNumber\s*=\s*(\d+)") { $pub = [int]$Matches[1] }
        if ($raw -match "versionCode\s*=\s*(\d+)") { $vc = [int]$Matches[1] }
    } else {
        $pubspec = Get-Content (Join-Path $flutterDir "pubspec.yaml") -Raw
        if ($pubspec -match 'version:\s*([^\s\r\n]+)') {
            $line = $Matches[1].Trim()
            if ($line -match '^(.+)\+(\d+)$') {
                $v = $Matches[1]
                $pub = [int]$Matches[2]
                $vc = $pub
            } else { $v = $line }
        }
    }
    return @{ Version = $v; Build = $pub; VersionCode = $vc; Tag = "$v+$pub" }
}

function Write-YahwehVersionJson {
    param($Ver)
    $publicDir = Join-Path $flutterDir "build\web"
    if (-not (Test-Path $publicDir)) { return }
    $path = Join-Path $publicDir "version.json"
    $json = @{
        version     = $Ver.Version
        buildNumber = $Ver.Build
        versionCode = $Ver.VersionCode
        releaseTag  = $Ver.Tag
    } | ConvertTo-Json -Compress
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8)
    Write-Host "  version.json: $($Ver.Tag)" -ForegroundColor Green
}

function Fix-YahwehWebBootstrap {
    $bootstrapPath = Join-Path $flutterDir "build\web\flutter_bootstrap.js"
    if (-not (Test-Path $bootstrapPath)) { return }
    $bc = Get-Content $bootstrapPath -Raw -Encoding UTF8
    if ($bc -match '_flutter\.loader\.load\s*\(\s*\)') {
        $bc = $bc -replace '_flutter\.loader\.load\s*\(\s*\)', '_flutter.loader.load({serviceWorkerSettings:null})'
        Set-Content -Path $bootstrapPath -Value $bc -NoNewline -Encoding UTF8
        Write-Host "  flutter_bootstrap.js: load sem service worker" -ForegroundColor Green
    }
    $assetBin = Join-Path $flutterDir "build\web\assets\AssetManifest.bin.json"
    $assetJson = Join-Path $flutterDir "build\web\assets\AssetManifest.json"
    if ((Test-Path $assetBin) -and (-not (Test-Path $assetJson))) {
        Copy-Item $assetBin $assetJson -Force
    }
}

Write-Host "=== Gestao YAHWEH deploy (padrao CT) ===" -ForegroundColor Cyan
Write-Host "  Modo: $(if ($WebOnly) { 'WebOnly RAPIDO' } else { 'COMPLETO' })" -ForegroundColor Yellow

# --- WebOnly: caminho rapido (igual Controle Total) ---
if ($WebOnly) {
    Write-Host "`n=== 1/4 Dependencias (sem clean por padrao) ===" -ForegroundColor Cyan
    Set-Location $flutterDir
    if ($Clean) {
        Write-Host "  flutter clean (-Clean)..." -ForegroundColor Gray
        flutter clean
        if ($LASTEXITCODE -ne 0) { Set-Location $root; exit 1 }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Set-Location $root; exit 1 }

    Write-Host "`n=== 2/4 Build Flutter Web ===" -ForegroundColor Cyan
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter build web --release --pwa-strategy=none --no-wasm-dry-run --no-tree-shake-icons --dart-define=FLUTTER_WEB_USE_SKIA=true 2>&1 | ForEach-Object { Write-Host $_ }
    $ErrorActionPreference = $eap
    if ($LASTEXITCODE -ne 0) { Set-Location $root; exit 1 }
    Set-Location $root

    Fix-YahwehWebBootstrap
    $ver = Get-YahwehVersionInfo
    Write-YahwehVersionJson -Ver $ver

    Write-Host "`n=== 3/4 Validate-HostingPreDeploy ===" -ForegroundColor Cyan
    & (Join-Path $root "scripts\Validate-HostingPreDeploy.ps1") -Root $root
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host "`n=== 4/4 Firebase ===" -ForegroundColor Cyan
    $fbArgs = @{ Root = $root }
    if ($HostingOnly) { $fbArgs.HostingOnly = $true }
    elseif ($SkipFunctionsDeploy -and -not $ForceFunctions) { $fbArgs.SkipFunctions = $true }
    & (Join-Path $root "scripts\Invoke-FirebaseDeploy.ps1") @fbArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "`n=== WebOnly concluido ===" -ForegroundColor Green
    Write-Host "  Versao: $($ver.Tag)" -ForegroundColor Cyan
    Write-Host "  Site: https://gestaoyahweh.com.br (Ctrl+F5)" -ForegroundColor Yellow
    Write-Host "  Force update: so no Admin apos testar (nao foi forcado)." -ForegroundColor DarkGray
    exit 0
}

# --- Completo: web+Firebase primeiro via pipeline legado, AAB/iOS depois ---
$completo = Join-Path $root "scripts\deploy_completo.ps1"
if (-not (Test-Path $completo)) {
    Write-Host "ERRO: $completo nao encontrado." -ForegroundColor Red
    exit 1
}

$invokeArgs = @{ CopyTo = $CopyTo }
if ($NoCodemagicPush) { $invokeArgs.SkipGitPush = $true }
if ($Clean) { $invokeArgs.ForceClean = $true }
if ($ForceFunctions) { $invokeArgs.ForceFunctions = $true }
if ($SkipRules) { $invokeArgs.SkipRules = $true }
if ($SkipFunctionsDeploy) { $invokeArgs.SkipFunctionsDeploy = $true }
if ($LogTo) { $invokeArgs.LogTo = $LogTo }

Write-Host "`n=== Completo via scripts\deploy_completo.ps1 ===" -ForegroundColor Cyan
Write-Host "  (Web/Firebase sobem antes do AAB; AAB em $CopyTo; CodeMagic so iOS)" -ForegroundColor DarkGray
& $completo @invokeArgs
exit $LASTEXITCODE
