# Android App Bundle (.aab) para Google Play — release ASSINADO + ofuscação Dart.
# Pré-requisitos: Flutter, JDK 17+ (ou Android Studio com JBR).
# Se não existir key.properties, executa setup_android_release_signing.ps1 (keystore + senhas geradas).
#
# Uso (na raiz do repo, PowerShell):
#   .\scripts\build_android_play_store_aab.ps1
#
# Cópia versionada do .aab: por defeito para D:\Temporarios (pasta de entrega).
# Desativar cópia: .\scripts\build_android_play_store_aab.ps1 -CopyTo ""
#
# Não gerar keystore automaticamente (falha se faltar key.properties):
#   .\scripts\build_android_play_store_aab.ps1 -NoAutoSigning

param(
    [string] $CopyTo = "D:\Temporarios",
    [switch] $NoAutoSigning
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"
$KeyProps = Join-Path $FlutterApp "android\key.properties"
$DebugInfoDir = Join-Path $FlutterApp "debug-info"
$OutAab = Join-Path $FlutterApp "build\app\outputs\bundle\release\app-release.aab"

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $KeyProps)) {
    if ($NoAutoSigning) {
        Write-Host ""
        Write-Host "ERRO: android\key.properties nao encontrado." -ForegroundColor Red
        Write-Host "Execute .\scripts\setup_android_release_signing.ps1 ou retire -NoAutoSigning." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "key.properties ausente - a configurar assinatura release automaticamente..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "setup_android_release_signing.ps1")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not (Test-Path $KeyProps)) {
        Write-Host "ERRO: setup_android_release_signing nao criou key.properties." -ForegroundColor Red
        exit 1
    }
}

Set-Location $FlutterApp

Write-Host "=== flutter clean ===" -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path $DebugInfoDir)) {
    New-Item -ItemType Directory -Path $DebugInfoDir | Out-Null
}

Write-Host "`n=== flutter build appbundle --release --obfuscate --split-debug-info=./debug-info ===" -ForegroundColor Cyan
Write-Host "Guarde a pasta flutter_app\debug-info\ para symbolizar stack traces (Crashlytics / flutter symbolize)." -ForegroundColor DarkGray
flutter build appbundle --release --obfuscate --split-debug-info=./debug-info
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path $OutAab)) {
    Write-Host "Erro: AAB nao gerado em $OutAab" -ForegroundColor Red
    exit 1
}

$verLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
$ver = if ($verLine) { ($verLine.Line -replace '^version:\s*', '').Trim() } else { "unknown" }
$nameVer = "GestaoYahweh_$($ver -replace '\+', '_build')_play.aab"

Write-Host ""
Write-Host "Concluido (assinatura release + obfuscate):" -ForegroundColor Green
Write-Host "  $OutAab"

if ($CopyTo -and $CopyTo.Trim().Length -gt 0) {
    $destDir = $CopyTo.Trim()
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $destFile = Join-Path $destDir $nameVer
    Copy-Item -Path $OutAab -Destination $destFile -Force
    Write-Host "Copiado: $destFile" -ForegroundColor Green
}
