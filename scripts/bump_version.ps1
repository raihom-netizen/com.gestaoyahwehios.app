# Incrementa APENAS o build (+N) — marketing fixo em 11.2.305.
# Google Play / App Store exigem versionCode/CFBundleVersion sempre maior.
# Uso (raiz): .\scripts\bump_version.ps1
# Ou: .\scripts\bump_version.ps1 -Increment 3
#
# Para mudar a versão de marketing (ex.: 11.2.306), use explicitamente:
# .\scripts\bump_version.ps1 -NewMarketing "11.2.306"

param(
    [int]$Increment = 1,
    [string]$NewMarketing = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $root "flutter_app"
$versionFile = Join-Path $appDir "lib\app_version.dart"
$pubspecFile = Join-Path $appDir "pubspec.yaml"
$webVersionFile = Join-Path $appDir "web\version.json"

$LockedMarketing = "11.2.305"

if (-not (Test-Path $versionFile)) {
    Write-Error "Arquivo nao encontrado: $versionFile"
    exit 1
}

$content = Get-Content $versionFile -Raw -Encoding UTF8
if ($content -notmatch "appVersion\s*=\s*'([^']+)'") {
    Write-Error "Nao foi possivel ler appVersion em app_version.dart"
    exit 1
}
$currentMarketing = $Matches[1]

$pubContent = Get-Content $pubspecFile -Raw -Encoding UTF8
if ($pubContent -notmatch "version:\s*([\d.]+)\+(\d+)") {
    Write-Error "Nao foi possivel ler version: X.Y.Z+N em pubspec.yaml"
    exit 1
}
$pubMarketing = $Matches[1]
$buildNum = [int]$Matches[2] + $Increment

$marketing = if ($NewMarketing.Trim().Length -gt 0) {
    $NewMarketing.Trim()
} else {
    $LockedMarketing
}

if ($NewMarketing.Trim().Length -eq 0 -and $currentMarketing -ne $LockedMarketing) {
    Write-Host "Aviso: app_version.dart tinha $currentMarketing — realinhando marketing para $LockedMarketing" -ForegroundColor Yellow
}
if ($NewMarketing.Trim().Length -eq 0 -and $pubMarketing -ne $LockedMarketing) {
    Write-Host "Aviso: pubspec.yaml tinha $pubMarketing — realinhando marketing para $LockedMarketing" -ForegroundColor Yellow
}

$versionLine = "version: $marketing+$buildNum"

$content = $content -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$marketing'"
if ($content -match "appBuildNumber\s*=") {
    $content = $content -replace "const String appBuildNumber = '\d+'", "const String appBuildNumber = '$buildNum'"
}
Set-Content $versionFile -Value $content -NoNewline -Encoding UTF8

$pubContent = $pubContent -replace "version:\s*[\d.]+\+\d+", $versionLine
Set-Content $pubspecFile -Value $pubContent -NoNewline -Encoding UTF8

$versionJsonPretty = @{
    app_name     = "gestao_yahweh"
    version      = $marketing
    build_number = $buildNum.ToString()
    package_name = "gestao_yahweh"
} | ConvertTo-Json
Set-Content $webVersionFile -Value $versionJsonPretty -Encoding UTF8

Write-Host "Versao atualizada: $marketing+$buildNum" -ForegroundColor Green
Write-Host "  - lib/app_version.dart"
Write-Host "  - pubspec.yaml"
Write-Host "  - web/version.json"
Write-Host ""
Write-Host "Marketing fixo: $LockedMarketing (use -NewMarketing apenas se pedido explicitamente)."
