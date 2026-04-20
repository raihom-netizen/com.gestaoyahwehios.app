# Incrementa apenas o número de build (+N) em pubspec e web/version.json.
# Google Play / App Store exigem código de build sempre maior que o já enviado.
# Uso (raiz): .\scripts\bump_build.ps1
# Ou: .\scripts\bump_build.ps1 -Increment 3

param(
    [int] $Increment = 1
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $root "flutter_app"
$pubspecFile = Join-Path $appDir "pubspec.yaml"
$webVersionFile = Join-Path $appDir "web\version.json"

$pubContent = Get-Content $pubspecFile -Raw -Encoding UTF8
if ($pubContent -notmatch "version:\s*([\d.]+)\+(\d+)") {
    Write-Error "Nao foi possivel ler version: X.Y.Z+N em pubspec.yaml"
    exit 1
}
$marketing = $Matches[1]
$buildNum = [int]$Matches[2] + $Increment
$versionLine = "version: $marketing+$buildNum"
$pubContent = $pubContent -replace "version:\s*[\d.]+\+\d+", $versionLine
Set-Content $pubspecFile -Value $pubContent -NoNewline -Encoding UTF8

$vj = @{
    app_name = "gestao_yahweh"
    version = $marketing
    build_number = $buildNum.ToString()
    package_name = "gestao_yahweh"
} | ConvertTo-Json
Set-Content $webVersionFile -Value $vj -Encoding UTF8

Write-Host "Build incrementado: $marketing+$buildNum (pubspec + web/version.json)" -ForegroundColor Green
