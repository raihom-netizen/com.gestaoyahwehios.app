# Android App Bundle (.aab) para Google Play -- release ASSINADO + ofuscação Dart.
# Pré-requisitos: Flutter, JDK 17+ (ou Android Studio com JBR).
# Se não existir key.properties, executa setup_android_release_signing.ps1 (keystore + senhas geradas).
#
# Uso (na raiz do repo, PowerShell):
#   .\scripts\build_android_play_store_aab.ps1
#
# Comportamento padrao: incrementa automaticamente +1 no build/versionCode
# antes de gerar o AAB (evita erro Play Console de codigo de versao ja usado).
#
# Cópia versionada do .aab: por defeito para D:\Temporarios (pasta de entrega).
# Desativar cópia: .\scripts\build_android_play_store_aab.ps1 -CopyTo ""
#
# Não gerar keystore automaticamente (falha se faltar key.properties):
#   .\scripts\build_android_play_store_aab.ps1 -NoAutoSigning

param(
    [string] $CopyTo = "D:\Temporarios",
    [switch] $NoAutoSigning,
    [switch] $SkipPubGet
)

    $ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")
$BumpBuildScript = Join-Path $RepoRoot "scripts\bump_build.ps1"
$FlutterApp = Join-Path $RepoRoot "flutter_app"
$KeyProps = Join-Path $FlutterApp "android\key.properties"
$DebugInfoDir = Join-Path $FlutterApp "debug-info"
$OutAab = Join-Path $FlutterApp "build\app\outputs\bundle\release\app-release.aab"
$MainActivityDexToken = "com/gestaoyahweh/app/MainActivity"

# Cache Gradle do repo (evita SSL Tag mismatch em downloads Maven/Gradle corrompidos).
$projectGradleHome = Join-Path $RepoRoot ".gradle-build-cache"
if (Test-Path (Join-Path $projectGradleHome "caches")) {
    $env:GRADLE_USER_HOME = $projectGradleHome
}
if (-not $env:JAVA_HOME -or -not (Test-Path $env:JAVA_HOME)) {
    $toolchainJdk = "C:\dev\gestao-yahweh-toolchain\jdk-17"
    if (Test-Path $toolchainJdk) {
        $env:JAVA_HOME = $toolchainJdk
        $env:PATH = "$toolchainJdk\bin;$env:PATH"
    }
}

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

function Assert-ReleaseManifestHasAdIdPermission {
    param([string] $FlutterAppPath)

    $merged = Join-Path $FlutterAppPath "build\app\intermediates\merged_manifests\release\processReleaseManifest\AndroidManifest.xml"
    if (-not (Test-Path $merged)) {
        $androidDir = Join-Path $FlutterAppPath "android"
        Write-Host "Manifest fundido nao encontrado; a gerar via Gradle..." -ForegroundColor DarkGray
        Push-Location $androidDir
        try {
            .\gradlew.bat :app:processReleaseManifest 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle processReleaseManifest falhou (exit $LASTEXITCODE)."
            }
        } finally {
            Pop-Location
        }
    }

    if (-not (Test-Path $merged)) {
        throw "Nao foi possivel localizar o AndroidManifest release fundido em:`n  $merged"
    }

    $adId = "com.google.android.gms.permission.AD_ID"
    $text = Get-Content -Path $merged -Raw -Encoding UTF8
    if ($text -notmatch [regex]::Escape($adId)) {
        throw @"
ERRO Play Console: o AAB nao tera a permissao obrigatoria $adId.
Corrija flutter_app\android\app\src\main\AndroidManifest.xml e volte a gerar o bundle.
"@
    }

    Write-Host "Play AD_ID: permissao presente no manifesto release fundido." -ForegroundColor Green
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

function Remove-AabLegacyAbiLibs {
    param([string] $AabPath)

    $legacyAbiRegex = '(^|/)lib/(armeabi-v7a|armeabi|x86|x86_64|mips|mips64)(/|$)'

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::Open(
        $AabPath,
        [System.IO.Compression.ZipArchiveMode]::Update
    )
    try {
        $toRemove = @(
            $zip.Entries | Where-Object {
                $name = ($_.FullName -replace '\\', '/').ToLowerInvariant()
                $name -match $legacyAbiRegex -or
                    $name -match '^bundle-metadata/.*/(armeabi-v7a|armeabi|x86|x86_64|mips|mips64)/' -or
                    $name -eq 'base/native.pb'
            }
        )
        if ($toRemove.Count -eq 0) {
            Write-Host "AAB: nenhuma biblioteca ABI legada (32-bit) para remover." -ForegroundColor DarkGray
            return
        }
        foreach ($entry in $toRemove) {
            $entry.Delete()
        }
        Write-Host "AAB: removidas $($toRemove.Count) entradas ABI legadas/metadados (publicamos só arm64-v8a)." -ForegroundColor Yellow
    }
    finally {
        $zip.Dispose()
    }
}

function Assert-AabNoLegacyAbiEntries {
    param([string] $AabPath)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $legacyAbiRegex = '(^|/)lib/(armeabi-v7a|armeabi|x86|x86_64|mips|mips64)(/|$)|^bundle-metadata/.*/(armeabi-v7a|armeabi|x86|x86_64|mips|mips64)/|^base/native\.pb$'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($AabPath)
    try {
        $leftovers = @(
            $zip.Entries | Where-Object {
                (($_.FullName -replace '\\', '/').ToLowerInvariant()) -match $legacyAbiRegex
            } | Select-Object -ExpandProperty FullName
        )
        if ($leftovers.Count -gt 0) {
            throw "AAB invalido: entradas ABI legadas restantes: $($leftovers -join ', ')"
        }
    }
    finally {
        $zip.Dispose()
    }
    Write-Host "AAB ABI: sem diretórios/arquivos legados vazios (x86_64/x86/armeabi)." -ForegroundColor Green
}

function Find-BundletoolJar {
    $candidates = @()
    $standalone = 'D:\Temporarios\bundletool-all-1.18.3.jar'
    if (Test-Path $standalone) { $candidates += $standalone }

    $known = @(
        (Join-Path $RepoRoot '.gradle-build-cache'),
        (Join-Path $env:USERPROFILE '.gradle\caches')
        'D:\Temporarios\gradle-home-controletotal\caches',
        'D:\Temporarios\gradle-home-controletotal\maven-prefetch-staging'
    )
    foreach ($dir in $known) {
        if (Test-Path $dir) {
            $found = @(Get-ChildItem -Path $dir -Recurse -Filter 'bundletool-all-*.jar' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 1024 * 1024 } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 8)
            foreach ($item in $found) { $candidates += $item.FullName }
        }
    }

    foreach ($jar in $candidates) {
        if (-not (Test-Path $jar)) { continue }
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($jar)
            try {
                $manifest = $zip.GetEntry('META-INF/MANIFEST.MF')
                if ($manifest -ne $null) { return $jar }
            }
            finally {
                $zip.Dispose()
            }
        } catch {
            Write-Host "bundletool ignorado (jar invalido): $jar" -ForegroundColor DarkYellow
        }
    }
    return $null
}

function Assert-AabBundletoolBuildApks {
    param([string] $AabPath)

    $bundletool = Find-BundletoolJar
    if (-not $bundletool) {
        Write-Host "AVISO: bundletool.jar nao encontrado - validacao build-apks ignorada (AAB ja validado em MainActivity/16K/AD_ID)." -ForegroundColor Yellow
        Write-Host "Coloque bundletool-all-*.jar em D:\Temporarios ou descarregue de https://github.com/google/bundletool/releases" -ForegroundColor DarkGray
        return
    }
    $javaExe = 'java'
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
        $javaExe = Join-Path $env:JAVA_HOME 'bin\java.exe'
    } elseif (Test-Path 'C:\dev\gestao-yahweh-toolchain\jdk-17\bin\java.exe') {
        $javaExe = 'C:\dev\gestao-yahweh-toolchain\jdk-17\bin\java.exe'
    }
    $tmpApks = Join-Path ([System.IO.Path]::GetTempPath()) ("gy_bundletool_" + [Guid]::NewGuid().ToString("N") + ".apks")
    try {
        Write-Host "bundletool: $bundletool" -ForegroundColor DarkGray
        Write-Host "java: $javaExe" -ForegroundColor DarkGray
        & $javaExe -jar $bundletool build-apks --bundle=$AabPath --output=$tmpApks --mode=universal --overwrite 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "bundletool build-apks falhou (exit $LASTEXITCODE)."
        }
        if (-not (Test-Path $tmpApks)) {
            throw "bundletool nao gerou APKS em $tmpApks"
        }
        Write-Host "bundletool build-apks: OK ($tmpApks)" -ForegroundColor Green
    }
    finally {
        if (Test-Path $tmpApks) { Remove-Item $tmpApks -Force -ErrorAction SilentlyContinue }
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
            $relative = $so.FullName.Replace($tmpDir + "\", "").Replace("\", "/")
            # Só validamos arm64-v8a -- ABIs legadas são removidas antes desta etapa.
            if ($relative -notmatch '/lib/arm64-v8a/') { continue }

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

function Assert-AabMainActivityPresent {
    param([string] $AabPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gy_main_act_" + [Guid]::NewGuid().ToString("N"))
    [System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($AabPath, $tmpDir)
        $classesDex = Join-Path $tmpDir "base\dex\classes.dex"
        if (-not (Test-Path $classesDex)) {
            throw "AAB invalido: falta base/dex/classes.dex em`n  $AabPath"
        }
        $bytes = [System.IO.File]::ReadAllBytes($classesDex)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($text -notmatch [regex]::Escape($MainActivityDexToken)) {
            throw @"
ERRO Play (ClassNotFoundException): MainActivity nao encontrada em classes.dex.
Manifesto aponta com.gestaoyahweh.app.MainActivity -- regenere o AAB (sem --target-platform android-arm64).
"@
        }
        Write-Host "Play launcher: MainActivity presente em base/dex/classes.dex." -ForegroundColor Green
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

if (-not (Test-Path $BumpBuildScript)) {
    Write-Host "Erro: script de bump nao encontrado em $BumpBuildScript" -ForegroundColor Red
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

if (-not $SkipPubGet) {
    Write-Host "=== flutter clean ===" -ForegroundColor Cyan
    flutter clean
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "`n=== flutter pub get ===" -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "=== flutter clean / pub get saltados (-SkipPubGet) ===" -ForegroundColor DarkGray
    Write-Host "Limpando apenas build/app/outputs/bundle (release anterior)..." -ForegroundColor DarkGray
    $oldBundle = Join-Path $FlutterApp "build\app\outputs\bundle\release\app-release.aab"
    if (Test-Path $oldBundle) { Remove-Item $oldBundle -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n=== auto-bump versionCode/build (+1) ===" -ForegroundColor Cyan
$global:LASTEXITCODE = 0
& $BumpBuildScript -Increment 1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$DataSafetyScript = Join-Path $RepoRoot "scripts\play_store_data_safety_preflight.ps1"
if (Test-Path $DataSafetyScript) {
    Write-Host '`n=== Google Play - Seguranca dos dados (pre-voo) ===' -ForegroundColor Cyan
    & $DataSafetyScript
}

$newVerLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
if ($newVerLine) {
    $newVer = ($newVerLine.Line -replace '^version:\s*', '').Trim()
    Write-Host "Versao ativa para build: $newVer" -ForegroundColor Green
}

if (-not (Test-Path $DebugInfoDir)) {
    New-Item -ItemType Directory -Path $DebugInfoDir | Out-Null
}

Write-Host "`n=== flutter build appbundle --release --obfuscate --split-debug-info=./debug-info ===" -ForegroundColor Cyan
Write-Host "NDK arm64-v8a via android/app/build.gradle.kts (16K). Sem --target-platform (bundle completo para Play)." -ForegroundColor DarkGray
Write-Host "Guarde a pasta flutter_app\debug-info\ para symbolizar stack traces (Crashlytics / flutter symbolize)." -ForegroundColor DarkGray
. (Join-Path $RepoRoot "scripts\flutter_invoke_with_retry.ps1")
$buildExit = Invoke-FlutterWithRetry -Label "AAB Play" -MaxAttempts 5 -InitialWaitSec 25 -Arguments @(
    "build", "appbundle", "--release",
    "--obfuscate", "--split-debug-info=./debug-info"
)
if ($buildExit -ne 0) { exit $buildExit }

if (-not (Test-Path $OutAab)) {
    Write-Host "Erro: AAB nao gerado em $OutAab" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== validacao MainActivity no AAB (Play ClassNotFoundException) ===" -ForegroundColor Cyan
Assert-AabMainActivityPresent -AabPath $OutAab

Write-Host "`n=== validacao Advertising ID (Play Console) ===" -ForegroundColor Cyan
Assert-ReleaseManifestHasAdIdPermission -FlutterAppPath $FlutterApp
Write-Host 'Se a Play ainda acusar erro: Politica do app - ID de publicidade - confirme Sim e carregue ESTE AAB.' -ForegroundColor DarkGray

Write-Host "`n=== validacao ABI ampla no AAB (sem diretorios vazios) ===" -ForegroundColor Cyan
Write-Host "Compatibilidade Play: manter ABIs disponiveis; bundletool valida se algum split ABI ficou vazio." -ForegroundColor DarkGray

Write-Host "`n=== validacao 16K page size no AAB ===" -ForegroundColor Cyan
Assert-Aab16kCompatibility -AabPath $OutAab -FlutterAppPath $FlutterApp
Write-Host "Play 16K: NDK r28+ + validacao automatica de .so no AAB." -ForegroundColor DarkGray

Write-Host "`n=== validacao bundletool build-apks (Play Console local) ===" -ForegroundColor Cyan
Assert-AabBundletoolBuildApks -AabPath $OutAab

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
    Write-Host ""
    Write-Host "SEGURANCA DOS DADOS (obrigatorio se ainda nao fez nesta versao):" -ForegroundColor Yellow
    Write-Host '  Play Console: Politica do app - Seguranca dos dados - declarar E-MAIL (coletado+compartilhado).' -ForegroundColor Gray
    Write-Host "  Guia: docs\PLAY_STORE_SEGURANCA_DADOS_EMAIL.md" -ForegroundColor Gray
    Write-Host "  Pre-voo: .\scripts\play_store_data_safety_preflight.ps1 -Strict" -ForegroundColor Gray
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
