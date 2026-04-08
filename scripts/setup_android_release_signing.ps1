# Gera keystore de upload + flutter_app/android/key.properties (gitignored).
# Executado pelo build_android_play_store_aab.ps1 se não existir assinatura.
#
# Uso (raiz do repo):
#   .\scripts\setup_android_release_signing.ps1
#   .\scripts\setup_android_release_signing.ps1 -Force   # recria (apaga .jks antigo do caminho configurado)

param(
    [switch] $Force
)

$ErrorActionPreference = "Stop"

function Get-KeytoolPath {
    $candidates = @(
        "$env:JAVA_HOME\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "${env:ProgramFiles(x86)}\Android\android-studio\jbr\bin\keytool.exe",
        "$env:LOCALAPPDATA\Programs\Android\Android Studio\jbr\bin\keytool.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $k = Get-Command keytool -ErrorAction SilentlyContinue
    if ($k) { return $k.Source }
    return $null
}

function New-RandomPassword {
    param([int] $Length = 24)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AndroidDir = Join-Path $RepoRoot "flutter_app\android"
$KeyProps = Join-Path $AndroidDir "key.properties"
$JksName = "upload-keystore.jks"
$JksPath = Join-Path $AndroidDir $JksName

if (-not (Test-Path $AndroidDir)) {
    Write-Error "Pasta android nao encontrada: $AndroidDir"
}

if ((Test-Path $KeyProps) -and -not $Force) {
    $props = @{}
    Get-Content $KeyProps -Encoding UTF8 | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
        $i = $_.IndexOf('=')
        if ($i -gt 0) { $props[$_.Substring(0, $i).Trim()] = $_.Substring($i + 1).Trim() }
    }
    $rel = $props['storeFile']
    if ($rel) {
        $full = [System.IO.Path]::GetFullPath((Join-Path $AndroidDir $rel.Trim()))
        if (Test-Path $full) {
            Write-Host "Assinatura release ja configurada: $KeyProps" -ForegroundColor Green
            exit 0
        }
    }
    Write-Host "Existe key.properties mas o keystore referenciado nao foi encontrado. Corrija ou use -Force." -ForegroundColor Red
    exit 1
}

if ($Force) {
    if (Test-Path $JksPath) { Remove-Item $JksPath -Force }
    if (Test-Path $KeyProps) { Remove-Item $KeyProps -Force }
}

$kt = Get-KeytoolPath
if (-not $kt) {
    Write-Error "keytool nao encontrado. Instale JDK 17+ ou Android Studio."
}

$pass = New-RandomPassword 24
$alias = "upload"
$dname = 'CN=Gestao Yahweh, OU=Mobile, O=Gestao Yahweh, L=Sao Paulo, ST=SP, C=BR'

Write-Host "=== Gerando keystore (upload) ===" -ForegroundColor Cyan
Write-Host "keytool: $kt" -ForegroundColor DarkGray
Set-Location $AndroidDir
& $kt -genkeypair -v `
    -storetype PKCS12 `
    -keystore $JksName `
    -alias $alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storepass $pass `
    -keypass $pass `
    -dname $dname
if ($LASTEXITCODE -ne 0) {
    Write-Error "keytool falhou (codigo $LASTEXITCODE)."
}

$keyContent = @"
# Gerado por scripts/setup_android_release_signing.ps1 — NAO commite (gitignore).
storePassword=$pass
keyPassword=$pass
keyAlias=$alias
storeFile=$JksName
"@
Set-Content -Path $KeyProps -Value $keyContent -Encoding UTF8

Write-Host ""
Write-Host "Concluido:" -ForegroundColor Green
Write-Host "  Keystore: $JksPath"
Write-Host "  Propriedades: $KeyProps"
Write-Host ""
Write-Host "IMPORTANTE: guarde uma copia segura do .jks e das senhas (password manager)." -ForegroundColor Yellow
Write-Host "  Registe SHA-1/SHA-256 na Firebase e no Google Cloud (OAuth) se usar Google Sign-In:" -ForegroundColor Yellow
Write-Host "  .\scripts\print_keystore_fingerprints.ps1 -FromKeyProperties" -ForegroundColor Cyan
Write-Host ""
if (-not $Force) {
    Write-Host "Se esta for a PRIMEIRA publicacao na Play, use esta chave como chave de upload na Console." -ForegroundColor DarkYellow
}
