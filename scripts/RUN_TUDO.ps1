$ErrorActionPreference = 'Stop'
$SCRIPTS = Join-Path $PSScriptRoot "."

Write-Host "==> Rodando deploy produção..." -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File (Join-Path $SCRIPTS "DEPLOY_PRODUCAO_YAHWEH.ps1")

Write-Host "==> Gerando Android (APK/AAB)..." -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File (Join-Path $SCRIPTS "BUILD_ANDROID_YAHWEH.ps1")

Write-Host "✅ Tudo concluído (deploy + Android)." -ForegroundColor Green
