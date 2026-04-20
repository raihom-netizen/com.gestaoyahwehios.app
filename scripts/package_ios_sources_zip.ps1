# ZIP das fontes ios/ (sem Pods/build) para Codemagic ou arquivo — nome inclui versão do pubspec.
# Uso (raiz): .\scripts\package_ios_sources_zip.ps1
# Pasta destino: .\scripts\package_ios_sources_zip.ps1 -CopyTo "D:\Temporarios"

param(
    [string] $CopyTo = "D:\Temporarios"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

if (-not (Test-Path $CopyTo)) {
    New-Item -ItemType Directory -Path $CopyTo -Force | Out-Null
}

Set-Location $FlutterApp
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$verLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
$ver = if ($verLine) { ($verLine.Line -replace '^version:\s*', '').Trim() } else { "unknown" }
$zipName = "GestaoYahweh_ios_sources_$($ver -replace '\+', '_build').zip"
$zipPath = Join-Path $CopyTo $zipName
$srcIos = Join-Path $FlutterApp "ios"
$stage = Join-Path $env:TEMP ("yw_ios_stage_" + [Guid]::NewGuid().ToString("N"))
$stageIos = Join-Path $stage "ios"
New-Item -ItemType Directory -Path $stageIos -Force | Out-Null
$null = & robocopy $srcIos $stageIos /E /XD Pods .symlinks build /NFL /NDL /NJH /NJS /nc /ns /np
$rcRobo = $LASTEXITCODE
if ($rcRobo -ge 8) {
    Write-Host "robocopy falhou (codigo $rcRobo)." -ForegroundColor Red
    exit $rcRobo
}
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stageIos -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "ZIP iOS: $zipPath" -ForegroundColor Green
Set-Location $RepoRoot
exit 0
