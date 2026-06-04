# Preflight Firebase Rules/Indexes — evita firebase deploy (e API /test) quando ja sincronizado.
# Dot-source a partir de deploy_firebase_rules.ps1

function Get-FirebaseDeployProjectId {
    param([string] $RepoRoot)
    $rc = Join-Path $RepoRoot ".firebaserc"
    if (Test-Path $rc) {
        try {
            $j = Get-Content $rc -Raw | ConvertFrom-Json
            if ($j.projects.default) { return [string]$j.projects.default }
        } catch {}
    }
    return 'gestaoyahweh-21e23'
}

function Get-GcloudAccessTokenSafe {
    $repo = Split-Path -Parent $PSScriptRoot
    $gcp = Join-Path $repo 'scripts\ensure_google_cloud_auth.ps1'
    if (Test-Path $gcp) {
        . $gcp
        Ensure-GoogleCloudAuth -RepoRoot $repo -Quiet | Out-Null
        return Get-GoogleCloudAccessToken -RepoRoot $repo
    }
    if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) { return $null }
    try {
        $t = (& gcloud auth print-access-token 2>$null | Select-Object -First 1)
        if ($t) { return $t.ToString().Trim() }
    } catch {}
    return $null
}

function Get-LocalFileSha256 {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RulesFileFingerprintBase64 {
    param([string] $Path)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content $Path -Raw -Encoding UTF8))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($sha.ComputeHash($bytes))
    } finally {
        $sha.Dispose()
    }
}

function Get-DeployStatePath {
    param([string] $RepoRoot)
    return Join-Path $RepoRoot '.deploy-state\firebase-sync.json'
}

function Read-DeployState {
    param([string] $RepoRoot)
    $p = Get-DeployStatePath -RepoRoot $RepoRoot
    if (-not (Test-Path $p)) { return $null }
    try {
        return Get-Content $p -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-DeployState {
    param(
        [string] $RepoRoot,
        [string] $FirestoreRulesSha,
        [string] $StorageRulesSha,
        [string] $IndexesSha
    )
    $dir = Join-Path $RepoRoot '.deploy-state'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = @{
        firestoreRulesSha256 = $FirestoreRulesSha
        storageRulesSha256   = $StorageRulesSha
        indexesSha256        = $IndexesSha
        syncedAt             = (Get-Date).ToUniversalTime().ToString('o')
    }
    $obj | ConvertTo-Json | Set-Content -Path (Get-DeployStatePath -RepoRoot $RepoRoot) -Encoding UTF8
}

function Test-LocalMatchesDeployState {
    param([string] $RepoRoot)
    $st = Read-DeployState -RepoRoot $RepoRoot
    if ($null -eq $st) { return $false }
    $fr = Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.rules')
    $sr = Get-LocalFileSha256 (Join-Path $RepoRoot 'storage.rules')
    $ix = Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.indexes.json')
    if (-not $fr -or -not $sr -or -not $ix) { return $false }
    return (
        $st.firestoreRulesSha256 -eq $fr -and
        $st.storageRulesSha256 -eq $sr -and
        $st.indexesSha256 -eq $ix
    )
}

function Get-RulesReleaseContent {
    param(
        [string] $ProjectId,
        [string] $ReleaseName,
        [string] $Token
    )
    $headers = @{ Authorization = "Bearer $Token" }
    $relUri = "https://firebaserules.googleapis.com/v1/projects/$ProjectId/releases/$ReleaseName"
    try {
        $rel = Invoke-RestMethod -Uri $relUri -Headers $headers -Method Get -TimeoutSec 45
        $rulesetName = [string]$rel.rulesetName
        if ([string]::IsNullOrWhiteSpace($rulesetName)) { return $null }
        $rs = Invoke-RestMethod -Uri "https://firebaserules.googleapis.com/v1/$rulesetName" -Headers $headers -Method Get -TimeoutSec 45
        foreach ($f in $rs.source.files) {
            if ($f.name -match '\.rules$') {
                $raw = [string]$f.content
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                try {
                    $bytes = [Convert]::FromBase64String($raw)
                    $decoded = [Text.Encoding]::UTF8.GetString($bytes)
                    if ($decoded -match 'service |rules_version') { return $decoded }
                } catch {}
                return $raw
            }
        }
    } catch {}
    return $null
}

function Test-LocalRulesMatchRemoteRelease {
    param(
        [string] $LocalPath,
        [string] $ProjectId,
        [string] $ReleaseName,
        [string] $Token
    )
    if (-not (Test-Path $LocalPath)) { return $false }
    $remote = Get-RulesReleaseContent -ProjectId $ProjectId -ReleaseName $ReleaseName -Token $Token
    if ($null -eq $remote) { return $false }
    $local = (Get-Content $LocalPath -Raw -Encoding UTF8).Replace("`r`n", "`n").Trim()
    $remoteNorm = $remote.Replace("`r`n", "`n").Trim()
    return ($local -eq $remoteNorm)
}

function Get-FirebaseStorageReleaseName {
    param([string] $ProjectId, [string] $Token)
    $headers = @{ Authorization = "Bearer $Token" }
    try {
        $uri = "https://firebaserules.googleapis.com/v1/projects/$ProjectId/releases?pageSize=100"
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 45
        foreach ($r in $resp.releases) {
            $n = [string]$r.name
            if ($n -match '/releases/firebase\.storage/') {
                return ($n -replace '^projects/[^/]+/releases/', '')
            }
        }
    } catch {}
    return "firebase.storage/$ProjectId.firebasestorage.app"
}

function Invoke-FirebaseRulesPreflight {
    param(
        [string] $RepoRoot,
        [switch] $VerbosePreflight
    )
    $projectId = Get-FirebaseDeployProjectId -RepoRoot $RepoRoot
    $result = @{
        ProjectId            = $projectId
        StorageOk              = $false
        FirestoreRulesOk       = $false
        FirestoreIndexesOk     = $false
        AllOk                  = $false
        UsedDeployState        = $false
        UsedRemoteCompare      = $false
        Message                = ''
    }

    if (Test-LocalMatchesDeployState -RepoRoot $RepoRoot) {
        $result.StorageOk = $true
        $result.FirestoreRulesOk = $true
        $result.FirestoreIndexesOk = $true
        $result.AllOk = $true
        $result.UsedDeployState = $true
        $result.Message = 'Ficheiros locais iguais ao ultimo deploy bem-sucedido (.deploy-state).'
        if ($VerbosePreflight) { Write-Host "   [preflight] $($result.Message)" -ForegroundColor DarkGreen }
        return $result
    }

    $token = Get-GcloudAccessTokenSafe
    if ($null -eq $token) {
        $result.Message = 'Sem token GCP - execute .\scripts\setup_google_cloud_automatico.ps1'
        if ($VerbosePreflight) { Write-Host "   [preflight] $($result.Message)" -ForegroundColor DarkYellow }
        return $result
    }

    $frPath = Join-Path $RepoRoot 'firestore.rules'
    $srPath = Join-Path $RepoRoot 'storage.rules'
    $storageRelease = Get-FirebaseStorageReleaseName -ProjectId $projectId -Token $token

    $result.FirestoreRulesOk = Test-LocalRulesMatchRemoteRelease `
        -LocalPath $frPath -ProjectId $projectId -ReleaseName 'cloud.firestore' -Token $token
    $result.StorageOk = Test-LocalRulesMatchRemoteRelease `
        -LocalPath $srPath -ProjectId $projectId -ReleaseName $storageRelease -Token $token

    # Indices: se rules+storage remotos = local, assume indexes OK (evita /test do CLI).
    # Novos indices no JSON exigem deploy quando API voltar — state file atualiza apos sucesso.
    if ($result.FirestoreRulesOk -and $result.StorageOk) {
        $localIxSha = Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.indexes.json')
        $st = Read-DeployState -RepoRoot $RepoRoot
        if ($null -ne $st -and $st.indexesSha256 -eq $localIxSha) {
            $result.FirestoreIndexesOk = $true
        } else {
            # Sem state: confiar em rules OK + indexes inalterados no git remoto
            try {
                $remoteIx = git show "origin/main:firestore.indexes.json" 2>$null
                if ($LASTEXITCODE -eq 0 -and $remoteIx) {
                    $tmp = Join-Path $env:TEMP ("yw_ix_" + [Guid]::NewGuid().ToString('N') + '.json')
                    Set-Content -Path $tmp -Value $remoteIx -Encoding UTF8
                    $remoteSha = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                    if ($remoteSha -eq $localIxSha) {
                        $result.FirestoreIndexesOk = $true
                    }
                }
            } catch {}
        }
    }

    $result.UsedRemoteCompare = $true
    $result.AllOk = $result.StorageOk -and $result.FirestoreRulesOk -and $result.FirestoreIndexesOk
    if ($result.AllOk) {
        Write-DeployState -RepoRoot $RepoRoot `
            -FirestoreRulesSha (Get-LocalFileSha256 $frPath) `
            -StorageRulesSha (Get-LocalFileSha256 $srPath) `
            -IndexesSha (Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.indexes.json'))
        $result.Message = 'Remoto = local (REST read-only). Skip firebase deploy /test.'
    } else {
        $result.Message = 'Alteracoes locais ou remoto diferente - deploy necessario.'
    }
    if ($VerbosePreflight) {
        Write-Host ("   [preflight] storage={0} rules={1} indexes={2} | {3}" -f `
            $(if ($result.StorageOk) { 'OK' } else { '...' }), `
            $(if ($result.FirestoreRulesOk) { 'OK' } else { '...' }), `
            $(if ($result.FirestoreIndexesOk) { 'OK' } else { '...' }), `
            $result.Message) -ForegroundColor DarkGray
    }
    return $result
}

function Invoke-FirebaseRulesGcpPublish {
    param(
        [string] $RepoRoot,
        [string] $ProjectId,
        [string] $Only = 'all',
        [switch] $Force,
        [int] $MaxAttempts = 40
    )
    $helper = Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'
    if (-not (Test-Path $helper)) {
        return @{ Ok = $false; Text = 'firebase_rules_gcp_publish.cjs em falta' }
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        return @{ Ok = $false; Text = 'Node.js necessario (cd functions; npm install)' }
    }
    $nodeArgs = @($helper, $ProjectId, "--only=$Only")
    if ($Force) {
        $nodeArgs += '--force'
        $nodeArgs += "--max-attempts=$MaxAttempts"
    }
    $lines = & node @nodeArgs 2>&1
    $text = ($lines | ForEach-Object { "$_" }) -join "`n"
    $okLine = $lines | Where-Object { $_ -match '^YAHWEH_GCP_OK=' } | Select-Object -Last 1
    $ok = ($LASTEXITCODE -eq 0) -or ($okLine -match '"ok"\s*:\s*true')
    return @{ Ok = $ok; Text = $text + "`n" }
}

function Publish-FirestoreRulesViaRest {
    param(
        [string] $RepoRoot,
        [string] $ProjectId,
        [int] $MaxAttempts = 5
    )
    return Invoke-FirebaseRulesGcpPublish -RepoRoot $RepoRoot -ProjectId $ProjectId `
        -Only 'firestore' -Force -MaxAttempts $MaxAttempts
}

function Start-FirebaseRulesBackgroundRetry {
    param([string] $RepoRoot)
    $script = Join-Path $RepoRoot 'scripts\deploy_firebase_rules_background.ps1'
    if (-not (Test-Path $script)) { return }
    Write-Host '   [background] Re-tentativa de regras em processo separado (503 API).' -ForegroundColor DarkYellow
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script
    ) -WindowStyle Hidden -WorkingDirectory $RepoRoot | Out-Null
}
