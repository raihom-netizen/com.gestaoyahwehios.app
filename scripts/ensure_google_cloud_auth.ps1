# Google Cloud + Firebase — auth automatica para deploy (Gestao YAHWEH).
# Dot-source: . .\scripts\ensure_google_cloud_auth.ps1
# Ou chamado por ensure_gestao_yahweh_toolchain_path.ps1 / deploy_firebase_rules.ps1

$installGcloudScript = Join-Path $PSScriptRoot 'install_google_cloud_sdk.ps1'
if (Test-Path $installGcloudScript) {
    . $installGcloudScript
}

$script:GoogleCloudProjectId = 'gestaoyahweh-21e23'
$script:GoogleCloudAuthReady = $false
$script:GoogleCloudAuthSource = ''

function Add-GcloudToPath {
    $bins = @(
        "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin",
        "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin",
        "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin"
    )
    $tc = $env:GESTAO_YAHWEH_TOOLCHAIN_ROOT
    if ($tc -and (Test-Path $tc)) {
        $bins += Join-Path $tc 'google-cloud-sdk\bin'
    }
    foreach ($b in $bins) {
        if ((Test-Path $b) -and ($env:Path -notlike "*$b*")) {
            $env:Path = "$b;$env:Path"
        }
    }
}

function Find-ProjectServiceAccountKey {
    param([string] $RepoRoot)
    if ($env:GOOGLE_APPLICATION_CREDENTIALS -and (Test-Path $env:GOOGLE_APPLICATION_CREDENTIALS)) {
        return $env:GOOGLE_APPLICATION_CREDENTIALS
    }
    $adminsdk = @()
    $other = @()
    foreach ($dir in @(
        (Join-Path $RepoRoot 'ANDROID'),
        (Join-Path $RepoRoot 'secrets'),
        $RepoRoot
    )) {
        if (-not (Test-Path $dir)) { continue }
        $adminsdk += Get-ChildItem -Path $dir -Filter 'gestaoyahweh*-firebase-adminsdk*.json' -File -ErrorAction SilentlyContinue
        $other += Get-ChildItem -Path $dir -Filter 'gestaoyahweh*.json' -File -ErrorAction SilentlyContinue
    }
    $candidates = @($adminsdk) + @($other | Where-Object { $_.Name -notmatch 'firebase-adminsdk' })
    foreach ($f in $candidates) {
        try {
            $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($j.project_id -eq $script:GoogleCloudProjectId -and $j.private_key) {
                return $f.FullName
            }
        } catch {}
    }
    return $null
}

function Get-ServiceAccountAccessTokenViaNode {
    param(
        [string] $KeyPath,
        [string] $RepoRoot
    )
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
    $functionsDir = Join-Path $RepoRoot 'functions'
    $gal = Join-Path $functionsDir 'node_modules\google-auth-library'
    if (-not (Test-Path $gal)) { return $null }

    $helper = Join-Path $RepoRoot 'scripts\gcp_service_account_token.cjs'
    if (-not (Test-Path $helper)) { return $null }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $t = (& node $helper $KeyPath 2>$null | Select-Object -First 1)
        if ($t -and $t.ToString().Trim().Length -gt 20) {
            $script:GoogleCloudAuthSource = 'service_account_node'
            return $t.ToString().Trim()
        }
    } finally {
        $ErrorActionPreference = $oldEap
    }
    return $null
}

function Get-GoogleCloudAccessToken {
    param([string] $RepoRoot = '')
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
    }
    Add-GcloudToPath
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
        $key = Find-ProjectServiceAccountKey -RepoRoot $RepoRoot
        if ($key) {
            return Get-ServiceAccountAccessTokenViaNode -KeyPath $key -RepoRoot $RepoRoot
        }
        return $null
    }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & gcloud config set project $script:GoogleCloudProjectId 2>$null | Out-Null
        $t = (& gcloud auth print-access-token 2>$null | Select-Object -First 1)
        if ($t -and $t.ToString().Trim().Length -gt 20) {
            $script:GoogleCloudAuthSource = 'gcloud_user'
            return $t.ToString().Trim()
        }
        $t2 = (& gcloud auth application-default print-access-token 2>$null | Select-Object -First 1)
        if ($t2 -and $t2.ToString().Trim().Length -gt 20) {
            $script:GoogleCloudAuthSource = 'gcloud_adc'
            return $t2.ToString().Trim()
        }
    } finally {
        $ErrorActionPreference = $oldEap
    }
    $key = Find-ProjectServiceAccountKey -RepoRoot $RepoRoot
    if ($key) {
        $t3 = Get-ServiceAccountAccessTokenViaNode -KeyPath $key -RepoRoot $RepoRoot
        if ($t3) { return $t3 }
    }
    return $null
}

function Ensure-GoogleCloudServiceAccountSession {
    param([string] $RepoRoot)
    $key = Find-ProjectServiceAccountKey -RepoRoot $RepoRoot
    if (-not $key) { return $false }
    Add-GcloudToPath
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) { return $false }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & gcloud auth activate-service-account --key-file="$key" --project=$script:GoogleCloudProjectId 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        $env:GOOGLE_APPLICATION_CREDENTIALS = $key
        $script:GoogleCloudAuthSource = 'service_account'
        return $true
    } finally {
        $ErrorActionPreference = $oldEap
    }
}

function Ensure-GoogleCloudAuth {
    param(
        [string] $RepoRoot = '',
        [switch] $Quiet
    )
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
    }
    if ($script:GoogleCloudAuthReady -and (Get-GoogleCloudAccessToken -RepoRoot $RepoRoot)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        if (-not (Test-Path (Join-Path $RepoRoot 'firebase.json'))) {
            $RepoRoot = (Get-Location).Path
        }
    }
    if (Get-Command Ensure-GcloudInstalled -ErrorAction SilentlyContinue) {
        Ensure-GcloudInstalled -RepoRoot $RepoRoot -Quiet:$Quiet | Out-Null
    }
    Add-GcloudToPath
    $token = Get-GoogleCloudAccessToken -RepoRoot $RepoRoot
    if (-not $token) {
        if (Ensure-GoogleCloudServiceAccountSession -RepoRoot $RepoRoot) {
            $token = Get-GoogleCloudAccessToken -RepoRoot $RepoRoot
        }
    }
    if (-not $token) {
        $key = Find-ProjectServiceAccountKey -RepoRoot $RepoRoot
        if ($key) {
            $token = Get-ServiceAccountAccessTokenViaNode -KeyPath $key -RepoRoot $RepoRoot
        }
    }
    if ($token) {
        $script:GoogleCloudAuthReady = $true
        if (-not $Quiet) {
            Write-Host "   [GCP] Auth OK ($script:GoogleCloudAuthSource) projeto $($script:GoogleCloudProjectId)" -ForegroundColor DarkGreen
        }
        return $true
    }
    if (-not $Quiet) {
        Write-Host '   [GCP] Sem token Google Cloud - preflight/REST limitados.' -ForegroundColor DarkYellow
        Write-Host '   Execute uma vez: .\scripts\setup_google_cloud_automatico.ps1' -ForegroundColor DarkGray
        Write-Host '   (ou: gcloud auth login + gcloud config set project gestaoyahweh-21e23)' -ForegroundColor DarkGray
    }
    return $false
}

# Alias usado em firebase_rules_preflight.ps1
function Get-GcloudAccessTokenSafe {
    $repo = Split-Path -Parent $PSScriptRoot
    Ensure-GoogleCloudAuth -RepoRoot $repo -Quiet | Out-Null
    return Get-GoogleCloudAccessToken -RepoRoot $repo
}
