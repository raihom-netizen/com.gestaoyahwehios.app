# Download TDLib (libtdjson) prebuilt — Gestão YAHWEH
# Uso (raiz do repo):  .\scripts\download_tdlib.ps1
# Ou:                  .\scripts\download_tdlib.ps1 -AndroidOnly
#                      .\scripts\download_tdlib.ps1 -IosOnly

param(
    [switch] $AndroidOnly,
    [switch] $IosOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path "D:\TEMPORARIOS\tdlib_download" -Force | Out-Null

Push-Location $FlutterApp
try {
    Write-Host "flutter pub get (deps do tool)..." -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $args = @("run", "tool/download_tdlib.dart")
    if ($AndroidOnly) { $args += "--android-only" }
    if ($IosOnly) { $args += "--ios-only" }

    Write-Host "dart $($args -join ' ')" -ForegroundColor Cyan
    & dart @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
