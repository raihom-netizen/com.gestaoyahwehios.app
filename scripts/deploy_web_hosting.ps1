# Deploy web Gestao YAHWEH - build release + Firebase Hosting
# Uso (na raiz):  .\scripts\deploy_web_hosting.ps1
# Padrao CT: SEM flutter clean por padrao (rapido). Use -Clean so quando necessario.
#
# -SkipPubGet: salta pub get (deploy completo ja fez)
# -Clean: forca flutter clean

param(
    [switch] $SkipPubGet,
    [switch] $Clean
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")
$FlutterApp = Join-Path $RepoRoot "flutter_app"

function Remove-PathRobust {
    param([Parameter(Mandatory = $true)][string]$PathToRemove)

    if (-not (Test-Path $PathToRemove)) { return }
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            Remove-Item -Path $PathToRemove -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path $PathToRemove)) { return }
        }
        catch {
            Start-Sleep -Milliseconds (200 * $attempt)
        }
    }

    try {
        cmd /c "rmdir /s /q \"$PathToRemove\"" | Out-Null
    }
    catch {}
}

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado em $FlutterApp" -ForegroundColor Red
    exit 1
}

Set-Location $FlutterApp
if (-not $SkipPubGet) {
    if ($Clean) {
        Write-Host "=== flutter clean (-Clean) ===" -ForegroundColor Cyan
        flutter clean
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } else {
        Write-Host "=== flutter clean PULADO (padrao rapido CT; use -Clean se precisar) ===" -ForegroundColor DarkGray
    }
    Write-Host "=== flutter pub get ===" -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "=== flutter clean / pub get saltados (-SkipPubGet) ===" -ForegroundColor DarkGray
}

# Limpeza pontual so da pasta web (evita assets duplicados no Windows) — nao e flutter clean.
Remove-PathRobust -PathToRemove (Join-Path $FlutterApp "build\web")
Remove-PathRobust -PathToRemove (Join-Path $FlutterApp "build\web\assets")
Remove-PathRobust -PathToRemove (Join-Path $FlutterApp "build\web\assets\assets")

Write-Host "`n=== flutter build web --release (CanvasKit) ===" -ForegroundColor Cyan
. (Join-Path $RepoRoot "scripts\flutter_invoke_with_retry.ps1")
$buildExit = Invoke-FlutterWithRetry -Label "Web hosting" -MaxAttempts 3 -InitialWaitSec 15 -Arguments @(
    "build", "web", "--release", "--pwa-strategy=none", "--no-wasm-dry-run", "--no-tree-shake-icons",
    "--dart-define=FLUTTER_WEB_USE_SKIA=true"
)
if ($buildExit -ne 0) { exit $buildExit }

Set-Location $RepoRoot
Write-Host "`n=== firebase deploy --only hosting ===" -ForegroundColor Cyan
$firebaseCmd = Join-Path $env:APPDATA 'npm\firebase.cmd'
if (Test-Path $firebaseCmd) {
    & $firebaseCmd deploy --only hosting --project gestaoyahweh-21e23 --force --non-interactive
} else {
    firebase deploy --only hosting --project gestaoyahweh-21e23 --force --non-interactive
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Hosting OK." -ForegroundColor Green
Write-Host "Concluido. Hosting: https://gestaoyahweh-21e23.web.app" -ForegroundColor Green
