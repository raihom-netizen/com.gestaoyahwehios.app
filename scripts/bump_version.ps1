# Script unico para subir a versao do Gestao YAHWEH.
# Atualiza: lib/app_version.dart, pubspec.yaml e web/version.json.
# Uso: .\scripts\bump_version.ps1   (incrementa patch: 9.0.2 -> 9.0.3)
# Ou:  .\scripts\bump_version.ps1 -Patch 2  (sobe 2 patches)

param(
    [int]$Patch = 1
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $root "flutter_app"
$versionFile = Join-Path $appDir "lib\app_version.dart"
$pubspecFile = Join-Path $appDir "pubspec.yaml"
$webVersionFile = Join-Path $appDir "web\version.json"

if (-not (Test-Path $versionFile)) {
    Write-Error "Arquivo nao encontrado: $versionFile"
    exit 1
}

# Ler versao atual de app_version.dart (ex: '9.0.2')
$content = Get-Content $versionFile -Raw -Encoding UTF8
if ($content -match "appVersion\s*=\s*'([^']+)'") {
    $current = $Matches[1]
} else {
    Write-Error "Nao foi possivel ler appVersion em app_version.dart"
    exit 1
}

$segments = $current -split '\.'
$major = [int]($segments[0])
$minor = [int]($segments[1])
$patchVal = if ($segments.Length -ge 3) { [int]($segments[2]) } else { 0 }
$patchVal += $Patch
$newVersion = "$major.$minor.$patchVal"

# Ler build number do pubspec (ex: 9.0.2+3 -> 3)
$pubContent = Get-Content $pubspecFile -Raw -Encoding UTF8
$buildNum = 1
if ($pubContent -match "version:\s*[\d.]+\+(\d+)") {
    $buildNum = [int]$Matches[1] + $Patch
}
$versionLine = "version: $newVersion+$buildNum"

# Atualizar app_version.dart (marketing + build; labels completos derivam em Dart)
$content = $content -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newVersion'"
if ($content -match "appBuildNumber\s*=") {
    $content = $content -replace "const String appBuildNumber = '\d+'", "const String appBuildNumber = '$buildNum'"
}
Set-Content $versionFile -Value $content -NoNewline -Encoding UTF8

# Atualizar pubspec.yaml (linha version: X.Y.Z+N)
$pubContent = $pubContent -replace "version:\s*[\d.]+\+\d+", $versionLine
Set-Content $pubspecFile -Value $pubContent -NoNewline -Encoding UTF8

# Gerar web/version.json (copiado no build para build/web)
$versionJson = @{
    app_name = "gestao_yahweh"
    version = $newVersion
    build_number = $buildNum.ToString()
    package_name = "gestao_yahweh"
} | ConvertTo-Json -Compress
$versionJsonPretty = @{
    app_name = "gestao_yahweh"
    version = $newVersion
    build_number = $buildNum.ToString()
    package_name = "gestao_yahweh"
} | ConvertTo-Json
$webDir = Join-Path $appDir "web"
if (-not (Test-Path $webDir)) { New-Item -ItemType Directory -Path $webDir | Out-Null }
Set-Content (Join-Path $webDir "version.json") -Value $versionJsonPretty -Encoding UTF8

Write-Host "Versao atualizada para $newVersion (build $buildNum)"
Write-Host "  - lib/app_version.dart"
Write-Host "  - pubspec.yaml"
Write-Host "  - web/version.json"
Write-Host ""
Write-Host "Proximo passo: flutter build web (ou deploy). O version.json sera incluido no build."
