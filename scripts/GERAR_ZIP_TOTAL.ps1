$ErrorActionPreference = 'Stop'
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ZIP="$env:USERPROFILE\Desktop\GESTAO_YAHWEH_PRODUCAO_IGREJAS_COMPLETO.zip"

if (Test-Path $ZIP) { Remove-Item $ZIP -Force }

# opcional: reduzir peso
if (Test-Path "$ROOT\functions\node_modules") { Remove-Item "$ROOT\functions\node_modules" -Recurse -Force }
if (Test-Path "$ROOT\flutter_app\build") { Remove-Item "$ROOT\flutter_app\build" -Recurse -Force }

Compress-Archive -Path "$ROOT\*" -DestinationPath $ZIP -Force
Write-Host "✅ ZIP gerado: $ZIP" -ForegroundColor Green
