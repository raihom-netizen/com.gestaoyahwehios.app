# Setup TDLib multiplataforma (Android + iOS estático) — Gestão YAHWEH
# Uso (raiz): .\scripts\setup_tdlib.ps1
#            .\scripts\setup_tdlib.ps1 -AndroidOnly
#            .\scripts\setup_tdlib.ps1 -IosOnly
param(
    [switch] $AndroidOnly,
    [switch] $IosOnly
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"
New-Item -ItemType Directory -Path "D:\TEMPORARIOS\tdlib_download" -Force | Out-Null
Push-Location $FlutterApp
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $dartArgs = @("run", "tool/setup_tdlib.dart")
    if ($AndroidOnly) { $dartArgs += "--android-only" }
    if ($IosOnly) { $dartArgs += "--ios-only" }
    & dart @dartArgs
    $code = $LASTEXITCODE
    Write-Host ""
    Write-Host "Proximos passos:"
    Write-Host "  Android device:  flutter run -d <deviceId>"
    Write-Host "  iOS (no Mac):    cd ios; pod install; cd ..; flutter run -d <simulator>"
    Write-Host "  Rota de teste:   /tdlib-login"
    exit $code
}
finally { Pop-Location }
