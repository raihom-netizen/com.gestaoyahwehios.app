# Deploy web + regras Firestore/Storage (uso pontual)
# Hosting somente (recomendado): na raiz do repo execute ..\scripts\deploy_web_hosting.ps1
# Execute no PowerShell (Flutter + Firebase CLI no PATH)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "=== Build web (release) ===" -ForegroundColor Cyan
flutter pub get
flutter build web --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Deploy Firebase (hosting + firestore + storage) ===" -ForegroundColor Cyan
Set-Location (Split-Path -Parent $root)
firebase deploy --only "hosting,firestore,storage"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Concluido. Web online + regras Firestore/Storage ===" -ForegroundColor Green
