# Build web com CanvasKit — equivalente ao deploy padrão [deploy_web_hosting.ps1].
# Uso (na raiz): .\scripts\deploy_web_hosting_canvaskit.ps1
# HTML/DOM: .\scripts\deploy_web_hosting_html_dom.ps1 — mídia cross-origin pode ser mais simples; CanvasKit exige CORS no Storage (cors.json).
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

Set-Location $FlutterApp
Write-Host "=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== flutter build web --release (CanvasKit / FLUTTER_WEB_USE_SKIA=true) ===" -ForegroundColor Cyan
flutter build web --release --dart-define=FLUTTER_WEB_USE_SKIA=true
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $RepoRoot
Write-Host "`n=== firebase deploy --only hosting ===" -ForegroundColor Cyan
firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Concluido | Hosting: https://gestaoyahweh-21e23.web.app ===" -ForegroundColor Green
