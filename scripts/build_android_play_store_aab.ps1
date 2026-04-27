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

function Get-AndroidSdkPath {
    param([string] $FlutterAppPath)

    $localProps = Join-Path $FlutterAppPath "android\local.properties"
    if (Test-Path $localProps) {
        $sdkLine = Select-String -Path $localProps -Pattern "^sdk\.dir=" | Select-Object -First 1
        if ($sdkLine) {
            $value = ($sdkLine.Line -replace "^sdk\.dir=", "").Trim()
            if ($value) {
                return $value.Replace("\\:", ":").Replace("\\", "\")
            }
        }
    }

    if ($env:ANDROID_SDK_ROOT) { return $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { return $env:ANDROID_HOME }
    return $null
}

function Get-LlvmReadelfPath {
    param([string] $SdkPath)

    if (-not $SdkPath -or -not (Test-Path $SdkPath)) {
        throw "Android SDK nao encontrado. Configure sdk.dir em flutter_app\android\local.properties ou ANDROID_SDK_ROOT."
    }

    $ndkRoot = Join-Path $SdkPath "ndk"
    if (-not (Test-Path $ndkRoot)) {
        throw "Pasta NDK nao encontrada em '$ndkRoot'. Instale NDK 28+ no Android SDK Manager."
    }

    $ndkCandidates =
        Get-ChildItem -Path $ndkRoot -Directory -ErrorAction Stop |
        Sort-Object Name -Descending

    foreach ($ndk in $ndkCandidates) {
        $readelf = Join-Path $ndk.FullName "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"
        if (Test-Path $readelf) {
            return $readelf
        }
    }

    throw "llvm-readelf.exe nao encontrado em nenhuma versao do NDK dentro de '$ndkRoot'."
}

function Test-SharedObject16k {
    param(
        [string] $ReadelfExe,
        [string] $SoPath
    )

    $output = & $ReadelfExe -lW $SoPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao inspecionar ELF: $SoPath`n$output"
    }

    $loadLines = @($output | Where-Object { $_ -match "^\s*LOAD\s+" })
    if ($loadLines.Count -eq 0) {
        throw "Nao foi possivel localizar segmentos LOAD em '$SoPath'."
    }

    foreach ($line in $loadLines) {
        $tokens = @($line -split "\s+" | Where-Object { $_ -ne "" })
        $alignToken = $tokens[-1]
        if (-not ($alignToken -match "^0x[0-9A-Fa-f]+$")) {
            throw "Nao foi possivel ler alinhamento do segmento LOAD em '$SoPath': $line"
        }

        $alignValue = [Convert]::ToInt64($alignToken, 16)
        if ($alignValue -lt 16384) {
            return [PSCustomObject]@{
                IsCompatible = $false
                AlignmentHex = $alignToken
            }
        }
    }

    return [PSCustomObject]@{
        IsCompatible = $true
        AlignmentHex = "0x4000+"
    }
}

function Assert-Aab16kCompatibility {
    param([string] $AabPath, [string] $FlutterAppPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gy_16k_check_" + [System.Guid]::NewGuid().ToString("N"))
    [System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($AabPath, $tmpDir)
        $soFiles = @(Get-ChildItem -Path $tmpDir -Recurse -Filter "*.so" -File)
        if ($soFiles.Count -eq 0) {
            Write-Host "Aviso: nenhum .so encontrado no AAB para validar 16K." -ForegroundColor Yellow
            return
        }

        $sdkPath = Get-AndroidSdkPath -FlutterAppPath $FlutterAppPath
        $readelf = Get-LlvmReadelfPath -SdkPath $sdkPath
        $incompatible = @()

        foreach ($so in $soFiles) {
            $check = Test-SharedObject16k -ReadelfExe $readelf -SoPath $so.FullName
            if (-not $check.IsCompatible) {
                $incompatible += [PSCustomObject]@{
                    File = $so.FullName.Replace($tmpDir + "\", "")
                    Alignment = $check.AlignmentHex
                }
            }
        }

        if ($incompatible.Count -gt 0) {
            Write-Host ""
            Write-Host "ERRO 16K PAGE SIZE: bibliotecas nativas incompatíveis encontradas no AAB:" -ForegroundColor Red
            foreach ($item in $incompatible) {
                Write-Host "  - $($item.File) (align=$($item.Alignment))" -ForegroundColor Red
            }
            throw "Build bloqueado para evitar rejeicao na Play Console (16KB memory page size)."
        }

        Write-Host "Validacao 16K concluida: $($soFiles.Count) bibliotecas .so compativeis." -ForegroundColor Green
    }
    finally {
        if (Test-Path $tmpDir) {
            Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

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

Write-Host "`n=== validacao 16K page size no AAB ===" -ForegroundColor Cyan
Assert-Aab16kCompatibility -AabPath $OutAab -FlutterAppPath $FlutterApp
Write-Host "Play 16K: NDK r28+ + validacao automatica de .so no AAB." -ForegroundColor DarkGray

$verLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
$ver = if ($verLine) { ($verLine.Line -replace '^version:\s*', '').Trim() } else { "unknown" }
$nameVer = "GestaoYahweh_$($ver -replace '\+', '_build')_play.aab"

Write-Host ""
Write-Host "Concluido (assinatura release + obfuscate):" -ForegroundColor Green
Write-Host "  $OutAab"

if ($ver -match '\+(\d+)\s*$') {
    $vc = $Matches[1]
    Write-Host ""
    Write-Host "Google Play (evitar erros ao guardar/lancar):" -ForegroundColor Yellow
    Write-Host "  Este AAB tem versionCode=$vc - tem de ser MAIOR que o maior ja usado (Producao / testes)." -ForegroundColor Gray
    Write-Host "  Carregue ESTE .aab em Artefactos antes de gravar (evita: nao adiciona nem remove pacotes)." -ForegroundColor Gray
}

if ($CopyTo -and $CopyTo.Trim().Length -gt 0) {
    $destDir = $CopyTo.Trim()
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $destFile = Join-Path $destDir $nameVer
    Copy-Item -Path $OutAab -Destination $destFile -Force
    Write-Host "Copiado: $destFile" -ForegroundColor Green
}

Set-Location $RepoRoot
