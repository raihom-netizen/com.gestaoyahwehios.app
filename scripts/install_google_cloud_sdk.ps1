# Instala Google Cloud SDK (gcloud + gsutil) automaticamente — Gestao YAHWEH.
# Dot-source: . .\scripts\install_google_cloud_sdk.ps1
# Uso directo: .\scripts\install_google_cloud_sdk.ps1

param(
    [switch] $Quiet,
    [switch] $SkipWinget,
    [string] $InstallRoot = ''
)

$script:GcloudInstallAttempted = $false

function Get-GestaoYahwehToolchainRoot {
    $root = $env:GESTAO_YAHWEH_TOOLCHAIN_ROOT
    if (-not $root -or -not (Test-Path $root)) {
        $root = 'C:\dev\gestao-yahweh-toolchain'
    }
    return $root
}

function Get-GcloudInstallDir {
    param([string] $Root = '')
    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-GestaoYahwehToolchainRoot
    }
    return Join-Path $Root 'google-cloud-sdk'
}

function Add-GcloudInstallPaths {
    param([string] $InstallDir)
    $bins = @(
        (Join-Path $InstallDir 'bin'),
        "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin",
        "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin",
        "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin"
    )
    foreach ($b in $bins) {
        if ((Test-Path $b) -and ($env:Path -notlike "*$b*")) {
            $env:Path = "$b;$env:Path"
        }
    }
}

function Test-GcloudAvailable {
    return [bool](Get-Command gcloud -ErrorAction SilentlyContinue)
}

function Install-GcloudViaWinget {
    if ($SkipWinget) { return $false }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
    if (-not $Quiet) {
        Write-Host '   [gcloud] winget install Google.CloudSDK (max 8 min)...' -ForegroundColor DarkGray
    }
    $job = Start-Job -ScriptBlock {
        winget install --id Google.CloudSDK -e --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            winget install Google.CloudSDK --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
        }
    }
    $done = Wait-Job $job -Timeout 480
    if (-not $done) {
        Stop-Job $job -Force -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) { Write-Host '   [gcloud] winget timeout - tentar zip...' -ForegroundColor DarkYellow }
        return $false
    }
    Receive-Job $job | Out-Null
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Add-GcloudInstallPaths -InstallDir (Get-GcloudInstallDir)
    return (Test-GcloudAvailable)
}

function Install-GcloudViaZip {
    param([string] $TargetDir)
    $downloads = Join-Path (Get-GestaoYahwehToolchainRoot) 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads, (Split-Path $TargetDir -Parent) | Out-Null
    $zipUrl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-windows-x86_64.zip'
    $zipPath = Join-Path $downloads 'google-cloud-cli-windows-x86_64.zip'
    if (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1MB) {
        if (-not $Quiet) { Write-Host "   [gcloud] Download SDK zip..." -ForegroundColor DarkGray }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fsSL -o $zipPath $zipUrl
            if ($LASTEXITCODE -ne 0) { return $false }
        } else {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        }
    }
    $extract = Join-Path $downloads 'gcloud-extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue }
    Expand-Archive -Path $zipPath -DestinationPath $extract -Force
    $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $inner) { return $false }
    if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue }
    Move-Item $inner.FullName $TargetDir -Force
    $installBat = Join-Path $TargetDir 'install.bat'
    if (-not (Test-Path $installBat)) { return $false }
    if (-not $Quiet) { Write-Host '   [gcloud] install.bat --quiet ...' -ForegroundColor DarkGray }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & cmd.exe /c "`"$installBat`" --quiet --usage-reporting=false --path-update=false --command-completion=false" 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $oldEap
    }
    Add-GcloudInstallPaths -InstallDir $TargetDir
    return (Test-GcloudAvailable)
}

function Install-GcloudViaInstaller {
    param([string] $TargetDir)
    $downloads = Join-Path (Get-GestaoYahwehToolchainRoot) 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $exeUrl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe'
    $exePath = Join-Path $downloads 'GoogleCloudSDKInstaller.exe'
    if (-not (Test-Path $exePath) -or (Get-Item $exePath).Length -lt 1MB) {
        if (-not $Quiet) { Write-Host '   [gcloud] Download installer...' -ForegroundColor DarkGray }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fsSL -o $exePath $exeUrl
            if ($LASTEXITCODE -ne 0) { return $false }
        } else {
            Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -UseBasicParsing
        }
    }
    if (-not $Quiet) { Write-Host "   [gcloud] Installer silencioso -> $TargetDir" -ForegroundColor DarkGray }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $proc = Start-Process -FilePath $exePath -ArgumentList @('/S', "/D=$TargetDir") -Wait -PassThru
        if ($proc.ExitCode -ne 0) { return $false }
    } finally {
        $ErrorActionPreference = $oldEap
    }
    Start-Sleep -Seconds 5
    Add-GcloudInstallPaths -InstallDir $TargetDir
    return (Test-GcloudAvailable)
}

function Find-GcloudServiceAccountKey {
    param([string] $RepoRoot)
    foreach ($dir in @(
        (Join-Path $RepoRoot 'ANDROID'),
        (Join-Path $RepoRoot 'secrets')
    )) {
        if (-not (Test-Path $dir)) { continue }
        $f = Get-ChildItem -Path $dir -Filter 'gestaoyahweh*-firebase-adminsdk*.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

function Set-GcloudProjectAndServiceAccount {
    param(
        [string] $RepoRoot,
        [string] $ProjectId = 'gestaoyahweh-21e23'
    )
    if (-not (Test-GcloudAvailable)) { return }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & gcloud config set project $ProjectId 2>$null | Out-Null
        $key = Find-GcloudServiceAccountKey -RepoRoot $RepoRoot
        if ($key) {
            & gcloud auth activate-service-account --key-file="$key" --project=$ProjectId 2>$null | Out-Null
            $env:GOOGLE_APPLICATION_CREDENTIALS = $key
        }
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Ensure-GcloudInstalled {
    param(
        [switch] $Quiet,
        [string] $RepoRoot = '',
        [switch] $SkipWinget
    )
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
    }
    $installDir = Get-GcloudInstallDir
    Add-GcloudInstallPaths -InstallDir $installDir
    if (Test-GcloudAvailable) {
        Set-GcloudProjectAndServiceAccount -RepoRoot $RepoRoot
        return $true
    }
    if ($script:GcloudInstallAttempted) { return (Test-GcloudAvailable) }
    $script:GcloudInstallAttempted = $true

    if (-not $Quiet) {
        Write-Host '=== Google Cloud SDK (gcloud) — instalacao automatica ===' -ForegroundColor Cyan
    }

    $ok = $false
    if (-not $ok) { $ok = Install-GcloudViaZip -TargetDir $installDir }
    if (-not $ok) { $ok = Install-GcloudViaWinget }
    if (-not $ok) { $ok = Install-GcloudViaInstaller -TargetDir $installDir }

    Add-GcloudInstallPaths -InstallDir $installDir
    if ($ok) {
        $bin = Join-Path $installDir 'bin'
        if (Test-Path $bin) {
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath -notlike "*$bin*") {
                [Environment]::SetEnvironmentVariable('Path', "$bin;$userPath", 'User')
            }
        }
        Set-GcloudProjectAndServiceAccount -RepoRoot $RepoRoot
        if (-not $Quiet) {
            $ver = (& gcloud --version 2>$null | Select-Object -First 1)
            Write-Host "   [gcloud] OK $ver" -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet) {
        Write-Host '   [gcloud] Instalacao automatica falhou; deploy usa Node + conta de servico.' -ForegroundColor DarkYellow
    }
    return $false
}

# Execucao directa do script
if ($MyInvocation.InvocationName -ne '.') {
    $repo = Split-Path -Parent $PSScriptRoot
    $ok = Ensure-GcloudInstalled -RepoRoot $repo -Quiet:$Quiet -SkipWinget:$SkipWinget
    if (-not $ok) { exit 1 }
    exit 0
}
