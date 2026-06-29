# Atualiza ícones e logos em TODAS as frentes a partir de assets/icon/app_icon.png
# Execute sempre que trocar o escudo em assets/icon/app_icon.png
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$src = Join-Path $root "assets\icon\app_icon.png"
if (-not (Test-Path $src)) {
  Write-Error "Arquivo não encontrado: $src"
}

Write-Host "Sincronizando LOGO_GESTAO_YAHWEH + web/brand..." -ForegroundColor Cyan
Copy-Item -Force $src (Join-Path $root "assets\LOGO_GESTAO_YAHWEH.png")
Copy-Item -Force $src (Join-Path $root "web\brand\gestao_yahweh_mark.png")

Write-Host "Gerando ícones Android / iOS / Web / Windows / macOS..." -ForegroundColor Cyan
& flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$icon192 = Join-Path $root "web\icons\Icon-192.png"
if (Test-Path $icon192) {
  Copy-Item -Force $icon192 (Join-Path $root "web\favicon.png")
}

Write-Host "OK — ícones atualizados:" -ForegroundColor Green
Write-Host "  assets/icon/app_icon.png (fonte)"
Write-Host "  assets/LOGO_GESTAO_YAHWEH.png (painel, login, master)"
Write-Host "  web/brand/gestao_yahweh_mark.png (URL pública)"
Write-Host "  web/icons/* + favicon.png (PWA / divulgação)"
Write-Host "  android/mipmap-*/ic_launcher.png"
Write-Host "  ios/Runner/Assets.xcassets/AppIcon.appiconset/*"
Write-Host "  windows/runner/resources/app_icon.ico"
Write-Host ""
Write-Host "Próximo passo (quando autorizar deploy): flutter build web + hosting / AAB iOS." -ForegroundColor Yellow
