# Atualiza os ícones do PWA (instalador web) a partir de assets/icon/app_icon.png
# Execute este script sempre que trocar o ícone em assets/icon/app_icon.png
# Requer: Flutter no PATH (ou ajuste $flutter abaixo)

$ErrorActionPreference = "Stop"
# scripts/ está dentro de flutter_app; ir para flutter_app
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "Gerando ícones web a partir de assets/icon/app_icon.png..." -ForegroundColor Cyan
& flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Ícones atualizados em web/icons/ (Icon-192.png, Icon-512.png, etc.)." -ForegroundColor Green
Write-Host "Próximo passo: flutter build web --release e depois deploy (ex.: firebase deploy --only hosting)." -ForegroundColor Yellow
