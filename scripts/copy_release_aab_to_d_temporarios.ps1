# Copia o AAB de release (flutter build appbundle) para D:\temporarios
# com nome incluindo versão do pubspec. Execute na raiz do repositório após o build.
# Uso: .\scripts\copy_release_aab_to_d_temporarios.ps1
param(
    [string] $DestDir = "D:\temporarios"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterDir = Join-Path $RepoRoot "flutter_app"
$Aab = Join-Path $FlutterDir "build\app\outputs\bundle\release\app-release.aab"

if (-not (Test-Path $Aab)) {
    Write-Host "ERRO: AAB nao encontrado: $Aab" -ForegroundColor Red
    Write-Host "  Execute antes: cd flutter_app; flutter build appbundle --release"
    exit 1
}

$null = New-Item -ItemType Directory -Force -Path $DestDir

$pub = Get-Content (Join-Path $FlutterDir "pubspec.yaml") -Raw
$ver = "unknown"
if ($pub -match '(?m)^version:\s*(\S+)') {
    $ver = $Matches[1].Trim()
}
$safe = $ver -replace '[\\/:*?"<>|]', '_'
$dest = Join-Path $DestDir "gestao_yahweh_${safe}.aab"

Copy-Item -LiteralPath $Aab -Destination $dest -Force
Write-Host "OK: $dest" -ForegroundColor Green
Write-Host "   (origem: $Aab)"
