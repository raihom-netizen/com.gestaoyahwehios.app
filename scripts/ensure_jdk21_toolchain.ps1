# JDK 21+ para Firebase Emulator Suite (firebase-tools exige Java 21 desde 2025).
# Dot-source: . .\scripts\ensure_jdk21_toolchain.ps1
# Uso: Ensure-Jdk21Toolchain [-Quiet]

function Ensure-Jdk21Toolchain {
    param([switch] $Quiet)

    $root = $env:GESTAO_YAHWEH_TOOLCHAIN_ROOT
    if (-not $root -or -not (Test-Path $root)) {
        $root = 'C:\dev\gestao-yahweh-toolchain'
    }
    $jdkDir = Join-Path $root 'jdk-21'
    $javaExe = Join-Path $jdkDir 'bin\java.exe'

    if (-not (Test-Path $javaExe)) {
        $downloads = Join-Path $root 'downloads'
        New-Item -ItemType Directory -Force -Path $downloads | Out-Null
        $zip = Join-Path $downloads 'microsoft-jdk-21.zip'
        $url = 'https://aka.ms/download-jdk/microsoft-jdk-21.0.6-windows-x64.zip'

        if (-not $Quiet) {
            Write-Host "[JDK21] A instalar Microsoft OpenJDK 21 em $jdkDir ..." -ForegroundColor Yellow
        }

        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 50MB) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                & curl.exe --retry 3 -L -o $zip $url
                if ($LASTEXITCODE -ne 0) { throw "Download JDK 21 falhou: $url" }
            } else {
                Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            }
        }

        $extract = Join-Path $downloads 'jdk21-extract'
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
        if (-not $inner) { throw 'JDK 21 zip vazio ou estrutura inesperada' }
        if (Test-Path $jdkDir) { Remove-Item $jdkDir -Recurse -Force }
        Move-Item $inner.FullName $jdkDir
        if (-not (Test-Path $javaExe)) { throw "java.exe nao encontrado apos extrair JDK 21" }
        if (-not $Quiet) { Write-Host "[JDK21] Instalado: $jdkDir" -ForegroundColor Green }
    } elseif (-not $Quiet) {
        Write-Host "[JDK21] OK: $jdkDir" -ForegroundColor DarkGray
    }

    $env:JAVA_HOME = $jdkDir
    $jdkBin = Join-Path $jdkDir 'bin'
    if ($env:Path -notlike "*$jdkBin*") {
        $env:Path = "$jdkBin;$env:Path"
    }

    $ver = & $javaExe -version 2>&1 | Select-Object -First 1
    if ($ver -notmatch 'version "21') {
        throw "JDK 21 esperado, obtido: $ver"
    }
    return $jdkDir
}
