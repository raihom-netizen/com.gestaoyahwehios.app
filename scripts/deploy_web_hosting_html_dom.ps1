# Deploy web Gestao YAHWEH — build HTML/DOM (FLUTTER_WEB_USE_SKIA=false)
# Use quando precisar do renderer DOM (menor peso inicial; CORS/Storage às vezes mais simples).
# Padrão do projeto: CanvasKit — .\scripts\deploy_web_hosting.ps1
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado em $FlutterApp" -ForegroundColor Red
    exit 1
}

Set-Location $FlutterApp
Write-Host "=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== flutter build web --release (renderer HTML/DOM) ===" -ForegroundColor Cyan
flutter build web --release --no-tree-shake-icons --dart-define=FLUTTER_WEB_USE_SKIA=false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $RepoRoot
Write-Host "`n=== firebase deploy --only hosting ===" -ForegroundColor Cyan
firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Concluido. Hosting: https://gestaoyahweh-21e23.web.app" -ForegroundColor Green
