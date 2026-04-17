# Deploy web Gestao YAHWEH - build release + Firebase Hosting apenas
# Uso (na raiz do repo):  .\scripts\deploy_web_hosting.ps1
# Requisitos: Flutter no PATH, Firebase CLI logado (`firebase login`)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado em $FlutterApp" -ForegroundColor Red
    exit 1
}

Set-Location $FlutterApp
Write-Host "=== flutter clean (evita locks / ficheiros duplicados no build web no Windows) ===" -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== flutter build web --release (CanvasKit / GPU, fotos 4K e crop) ===" -ForegroundColor Cyan
# FLUTTER_WEB_USE_SKIA=true = CanvasKit (padrão para performance com mídia HD na web).
# HTML/DOM (alternativa): .\scripts\deploy_web_hosting_html_dom.ps1
# --no-tree-shake-icons: ícones só via IconData dinâmico (menu lateral) não viram quadrados vazios na web.
flutter build web --release --no-tree-shake-icons --dart-define=FLUTTER_WEB_USE_SKIA=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $RepoRoot
Write-Host "`n=== firebase deploy --only hosting ===" -ForegroundColor Cyan
firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Concluido. Hosting: https://gestaoyahweh-21e23.web.app" -ForegroundColor Green
