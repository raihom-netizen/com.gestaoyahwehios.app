# Gera Android App Bundle (.aab) — build rapido (sem clean / sem obfuscate).
# Para enviar à Play Store com assinatura release + obfuscate, use:
#   .\scripts\build_android_play_store_aab.ps1
#
# Pré-requisitos: Flutter, JDK 17+. Produção na Play: android/key.properties + keystore.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "flutter_app")

Write-Host "pub get..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$kp = Join-Path $root "flutter_app\android\key.properties"
if (-not (Test-Path $kp)) {
    Write-Host ""
    Write-Host "AVISO: android\key.properties nao encontrado. O AAB sera assinado com chave DEBUG (a Play rejeita)." -ForegroundColor Yellow
    Write-Host "Use: .\scripts\build_android_play_store_aab.ps1 (exige key.properties) ou copie key.properties.example -> key.properties" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "flutter build appbundle --release..." -ForegroundColor Cyan
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = Join-Path $root "flutter_app\build\app\outputs\bundle\release\app-release.aab"
Write-Host ""
Write-Host "Concluido: $out" -ForegroundColor Green
