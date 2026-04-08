# Lista SHA-1 e SHA-256 (keytool -list -v) para OAuth / Firebase / Play Console.
# Uso:
#   .\scripts\print_keystore_fingerprints.ps1 -Debug
#   .\scripts\print_keystore_fingerprints.ps1 -FromKeyProperties
#   .\scripts\print_keystore_fingerprints.ps1 -Keystore "C:\caminho\upload-keystore.jks" -StorePass "senha" -Alias upload
#
# Se "keytool" nao estiver no PATH, o script tenta Android Studio JBR.

param(
    [switch] $Debug,
    [switch] $FromKeyProperties,
    [string] $Keystore = "",
    [string] $StorePass = "",
    [string] $Alias = "",
    [string] $KeyPass = ""
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

$kt = Get-KeytoolPath
if (-not $kt) {
    Write-Error "keytool nao encontrado. Instale JDK ou Android Studio."
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Props = Join-Path $RepoRoot "flutter_app\android\key.properties"

if ($FromKeyProperties) {
    if (-not (Test-Path $Props)) {
        Write-Error "Nao encontrado: $Props. Copie key.properties.example para key.properties e preencha."
    }
    $lines = Get-Content $Props -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' }
    $map = @{}
    foreach ($line in $lines) {
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim()
        $map[$k] = $v
    }
    $rel = $map['storeFile']
    if ([string]::IsNullOrWhiteSpace($rel)) { Write-Error "storeFile em falta em key.properties" }
    $androidDir = Split-Path $Props -Parent
    $Keystore = [System.IO.Path]::GetFullPath((Join-Path $androidDir $rel.Trim()))
    $StorePass = $map['storePassword']
    $Alias = $map['keyAlias']
    $KeyPass = $map['keyPassword']
}

if ($Debug) {
    $Keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
    $StorePass = "android"
    $Alias = "androiddebugkey"
    $KeyPass = "android"
}

if ([string]::IsNullOrWhiteSpace($Keystore) -or -not (Test-Path $Keystore)) {
    Write-Error "Keystore invalido ou vazio. Use -Debug, -FromKeyProperties ou -Keystore com caminho absoluto."
}

Write-Host "keytool: $kt" -ForegroundColor DarkGray
Write-Host "Keystore: $Keystore" -ForegroundColor Cyan
Write-Host ""
& $kt -list -v -keystore $Keystore -alias $Alias -storepass $StorePass -keypass $KeyPass
