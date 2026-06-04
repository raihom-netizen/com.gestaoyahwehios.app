# Instala toolchain Gestao YAHWEH num PC Windows formatado.
# Uso: .\scripts\setup_dev_machine_windows.ps1

param(
    [string] $DevRoot = 'C:\dev\gestao-yahweh-toolchain',
    [switch] $SkipAndroidSdk,
    [switch] $SkipFlutter
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$FlutterDir = Join-Path $DevRoot 'flutter'
$JdkDir = Join-Path $DevRoot 'jdk-17'
$AndroidSdk = Join-Path $DevRoot 'android-sdk'
$GitDir = Join-Path $DevRoot 'Git'
$Downloads = Join-Path $DevRoot 'downloads'
New-Item -ItemType Directory -Force -Path $DevRoot, $Downloads | Out-Null

function Download-File {
    param([string]$Url, [string]$Out, [long]$MinBytes = 100KB)
    $dir = Split-Path $Out -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ((Test-Path $Out) -and (Get-Item $Out).Length -ge $MinBytes) {
        Write-Host "OK (cache): $Out"
        return
    }
    if (Test-Path $Out) { Remove-Item $Out -Force -ErrorAction SilentlyContinue }
    Write-Host "Download: $Url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $lastErr = ''
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                & curl.exe --retry 3 --retry-delay 2 -L -C - -o $Out $Url
                if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
            } elseif (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Start-BitsTransfer -Source $Url -Destination $Out -ErrorAction Stop
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
            }
            if ((Test-Path $Out) -and (Get-Item $Out).Length -ge $MinBytes) {
                Write-Host "OK: $Out ($((Get-Item $Out).Length) bytes)"
                return
            }
            $lastErr = 'ficheiro demasiado pequeno apos download'
        } catch {
            $lastErr = $_.Exception.Message
            Write-Host "  tentativa $attempt falhou: $lastErr"
        }
        Start-Sleep -Seconds (3 * $attempt)
    }
    throw "Download falhou apos 20 tentativas: $Url - $lastErr"
}

function Get-GitExe {
    $candidates = @(
        (Join-Path $GitDir 'cmd\git.exe'),
        (Join-Path $GitDir 'git.exe'),
        (Join-Path $GitDir 'mingw64\bin\git.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Ensure-Git {
    if (Get-GitExe) {
        Write-Host "OK: Git em $GitDir"
        return
    }
    $mingitZip = Join-Path $Downloads 'MinGit.zip'
    Download-File -Url 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/MinGit-2.47.1.2-64-bit.zip' -Out $mingitZip -MinBytes 8000000
    if (Test-Path $GitDir) { Remove-Item $GitDir -Recurse -Force }
    $extract = Join-Path $Downloads 'mingit-extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $mingitZip -DestinationPath $extract -Force
    if (Test-Path $GitDir) { Remove-Item $GitDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $GitDir | Out-Null
    Get-ChildItem $extract -Force | ForEach-Object {
        Move-Item -Path $_.FullName -Destination (Join-Path $GitDir $_.Name) -Force
    }
    if (-not (Get-GitExe)) { throw 'MinGit zip incompleto ou estrutura inesperada' }
    Write-Host 'OK: MinGit instalado.'
}

function Ensure-Jdk17 {
    if (Test-Path (Join-Path $JdkDir 'bin\java.exe')) {
        Write-Host "OK: JDK em $JdkDir"
        return
    }
    $zip = Join-Path $Downloads 'microsoft-jdk-17.zip'
    Download-File -Url 'https://aka.ms/download-jdk/microsoft-jdk-17.0.13-windows-x64.zip' -Out $zip
    $extract = Join-Path $Downloads 'jdk-extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $inner) { throw 'JDK zip vazio' }
    if (Test-Path $JdkDir) { Remove-Item $JdkDir -Recurse -Force }
    Move-Item $inner.FullName $JdkDir
    Write-Host "OK: JDK 17 em $JdkDir"
}

function Ensure-Flutter {
    if ($SkipFlutter) { return }
    $flutterBat = Join-Path $FlutterDir 'bin\flutter.bat'
    if (Test-Path $flutterBat) {
        Write-Host "OK: Flutter em $FlutterDir"
        return
    }
    if (Test-Path $FlutterDir) {
        Remove-Item $FlutterDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $flutterZip = Join-Path $Downloads 'flutter-windows-stable.zip'
    $metaUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    Write-Host 'A obter URL do Flutter stable (Google CDN)...'
    $metaJson = curl.exe -fsSL $metaUrl
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler releases_windows.json' }
    $meta = $metaJson | ConvertFrom-Json
    $stableHash = $meta.current_release.stable
    if (-not $stableHash) { $stableHash = $meta.current_release }
    $hash = $meta.releases | Where-Object {
        ($_.hash -eq $stableHash -or $_.version -eq $stableHash) -and ($_.archive -match 'windows')
    } | Select-Object -First 1
    if (-not $hash) {
        $hash = $meta.releases | Where-Object { $_.channel -eq 'stable' -and $_.archive -match 'windows' } | Select-Object -Last 1
    }
    if (-not $hash) { throw "Release Flutter stable nao encontrada (hash=$stableHash)" }
    $current = $hash.version
    $zipUrl = "https://storage.googleapis.com/flutter_infra_release/releases/$($hash.archive)"
    Write-Host "Download Flutter $current ..."
    Download-File -Url $zipUrl -Out $flutterZip -MinBytes 50000000
    $extract = Join-Path $Downloads 'flutter-extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    # Expand-Archive falha em caminhos longos (.agents, etc.); tar (Windows 10+) e mais fiavel.
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        & tar.exe -xf $flutterZip -C $extract
        if ($LASTEXITCODE -ne 0) { throw "tar extracao Flutter falhou (exit $LASTEXITCODE)" }
    } else {
        Expand-Archive -Path $flutterZip -DestinationPath $extract -Force
    }
    $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $inner) { throw 'Flutter zip vazio' }
    Move-Item $inner.FullName $FlutterDir
    if (-not (Test-Path $flutterBat)) { throw 'Flutter extract falhou' }
    Write-Host "OK: Flutter $current em $FlutterDir"
}

function Ensure-AndroidSdk {
    if ($SkipAndroidSdk) { return }
    $sdkmanager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sdkmanager)) {
        $zip = Join-Path $Downloads 'cmdline-tools.zip'
        Download-File -Url 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -Out $zip
        $extract = Join-Path $Downloads 'android-cmdline'
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $toolsSrc = Join-Path $extract 'cmdline-tools'
        New-Item -ItemType Directory -Force -Path (Join-Path $AndroidSdk 'cmdline-tools') | Out-Null
        $destLatest = Join-Path $AndroidSdk 'cmdline-tools\latest'
        if (Test-Path $destLatest) { Remove-Item $destLatest -Recurse -Force }
        if (Test-Path $toolsSrc) {
            Move-Item $toolsSrc $destLatest
        }
    }
    if (-not (Test-Path $sdkmanager)) { throw "sdkmanager nao encontrado em $AndroidSdk" }

    $env:JAVA_HOME = $JdkDir
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $yesFile = Join-Path $Downloads 'android-licenses-yes.txt'
    ((1..120) | ForEach-Object { 'y' }) -join "`n" | Set-Content -Path $yesFile -Encoding ascii
    Write-Host 'A aceitar licencas Android...'
    Get-Content $yesFile -Raw | & $sdkmanager --sdk_root=$AndroidSdk --licenses 2>&1 | Out-Host
    Write-Host 'A instalar pacotes Android SDK...'
    $packages = @(
        'platform-tools',
        'platforms;android-35',
        'platforms;android-36',
        'build-tools;35.0.0',
        'build-tools;36.0.0',
        'ndk;28.0.13004108'
    )
    foreach ($pkg in $packages) {
        Write-Host "  sdkmanager $pkg"
        Get-Content $yesFile -Raw | & $sdkmanager --sdk_root=$AndroidSdk $pkg 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  AVISO: $pkg terminou com codigo $LASTEXITCODE (continua...)"
        }
    }
    Write-Host "OK: Android SDK em $AndroidSdk"
}

function Set-UserPath {
    $add = @(
        (Join-Path $FlutterDir 'bin'),
        (Join-Path $JdkDir 'bin'),
        (Join-Path $AndroidSdk 'platform-tools'),
        (Join-Path $AndroidSdk 'cmdline-tools\latest\bin'),
        (Join-Path $GitDir 'cmd'),
        (Join-Path $GitDir 'mingw64\bin'),
        $GitDir
    ) | Where-Object { Test-Path $_ }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = $userPath -split ';' | Where-Object { $_.Trim() }
    foreach ($p in $add) {
        if ($parts -notcontains $p) { $parts = @($p) + $parts }
    }
    $sep = ';'
    $newPath = ($parts -join $sep).TrimEnd($sep)
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $JdkDir, 'User')
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $AndroidSdk, 'User')
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $AndroidSdk, 'User')
    $env:Path = ($add -join $sep) + $sep + $env:Path
    $env:JAVA_HOME = $JdkDir
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    Write-Host 'OK: PATH e variaveis Android/Java actualizados.'
}

function Write-LocalProperties {
    param([string]$RepoRoot)
    $props = Join-Path $RepoRoot 'flutter_app\android\local.properties'
    $sdkEsc = $AndroidSdk.Replace('\', '\\')
    $flutterEsc = $FlutterDir.Replace('\', '\\')
    $lines = @(
        "sdk.dir=$sdkEsc",
        "flutter.sdk=$flutterEsc"
    )
    Set-Content -Path $props -Value $lines -Encoding UTF8
    Write-Host "OK: $props"
}

Write-Host '=== Gestao YAHWEH - setup dev Windows ===' -ForegroundColor Cyan
Ensure-Git
Ensure-Jdk17
Ensure-Flutter
Ensure-AndroidSdk
$repoEarly = Split-Path -Parent $PSScriptRoot
$gcloudScript = Join-Path $repoEarly 'scripts\install_google_cloud_sdk.ps1'
if (Test-Path $gcloudScript) {
    . $gcloudScript
    Ensure-GcloudInstalled -RepoRoot $repoEarly | Out-Null
}
Set-UserPath
$repo = Split-Path -Parent $PSScriptRoot
Write-LocalProperties -RepoRoot $repo

Write-Host ''
Write-Host '=== Verificacao ===' -ForegroundColor Cyan
$flutter = Join-Path $FlutterDir 'bin\flutter.bat'
if (Test-Path $flutter) {
    & $flutter --version
    & $flutter doctor -v
}

# Symlinks para plugins Flutter no Windows 10+ exigem Modo de programador (ou terminal Admin).
try {
    reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\DeveloperSettings' /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f 2>$null | Out-Null
    reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v DeveloperMode /t REG_DWORD /d 1 /f 2>$null | Out-Null
} catch { }
Write-Host ''
Write-Host 'IMPORTANTE (Windows): active Modo de programador para builds Flutter com plugins:' -ForegroundColor Yellow
Write-Host '  start ms-settings:developers   (ligar "Modo de programador")' -ForegroundColor Yellow
Write-Host '  Reinicie o terminal depois. Sem isto: "Building with plugins requires symlink support".' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Concluido. Reinicie o terminal e execute:' -ForegroundColor Green
Write-Host "  cd $repo"
Write-Host '  .\scripts\build_android_play_store_aab.ps1'
Write-Host '  .\scripts\package_ios_sources_zip.ps1'
