# Configuracao permanente Google Cloud — APIs + IAM para Firebase Rules (Gestao YAHWEH).
# Uso (raiz, PowerShell): .\scripts\setup_gcp_firebase_rules_permanent.ps1
# Autorizado: alinha projeto gestaoyahweh-21e23 para deploy REST sem CLI /test.

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')
. (Join-Path $RepoRoot 'scripts\ensure_google_cloud_auth.ps1')

$ProjectId = 'gestaoyahweh-21e23'

Write-Host '=== GCP permanente - Firebase Rules API ===' -ForegroundColor Cyan

. (Join-Path $RepoRoot 'scripts\install_google_cloud_sdk.ps1')
Ensure-GcloudInstalled -RepoRoot $RepoRoot | Out-Null
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    Write-Host 'Ativar APIs Google Cloud...' -ForegroundColor Yellow
    $apis = @(
        'firebaserules.googleapis.com',
        'firestore.googleapis.com',
        'firebasestorage.googleapis.com',
        'firebase.googleapis.com',
        'cloudresourcemanager.googleapis.com'
    )
    foreach ($api in $apis) {
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        & gcloud services enable $api --project=$ProjectId 2>$null | Out-Null
        $ErrorActionPreference = $oldEap
        Write-Host "   $api" -ForegroundColor DarkGray
    }
    & gcloud config set project $ProjectId 2>$null | Out-Null
} else {
    Write-Host 'gcloud: tentativa automatica falhou - deploy continua via Node (firebase_rules_gcp_publish.cjs).' -ForegroundColor DarkYellow
}

$ensureNode = Join-Path $RepoRoot 'scripts\ensure_functions_node_for_gcp.ps1'
if (Test-Path $ensureNode) {
    & $ensureNode
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'AVISO: npm functions/ falhou — IAM grant tenta auto-install no Node.' -ForegroundColor DarkYellow
    }
}

$key = Find-ProjectServiceAccountKey -RepoRoot $RepoRoot
if ($key) {
    Write-Host "Conta de servico: $key" -ForegroundColor DarkGray
    $grant = Join-Path $RepoRoot 'scripts\grant_gcp_firebase_rules_iam.cjs'
    if (Test-Path $grant) {
        Write-Host 'IAM via API googleapis (se ADC Owner)...' -ForegroundColor DarkGray
        & node $grant 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'AVISO: grant IAM API falhou — fallback gcloud abaixo.' -ForegroundColor DarkYellow
        }
    }
    if (Get-Command gcloud -ErrorAction SilentlyContinue) {
        $email = (Get-Content $key -Raw | ConvertFrom-Json).client_email
        $roles = @(
            'roles/firebaserules.system',
            'roles/firebase.admin',
            'roles/datastore.indexAdmin'
        )
        foreach ($role in $roles) {
            Write-Host "IAM: $role -> $email" -ForegroundColor DarkGray
            & gcloud projects add-iam-policy-binding $ProjectId `
                --member="serviceAccount:$email" `
                --role=$role `
                --condition=None 2>$null | Out-Null
        }
    }
}

Write-Host ''
Write-Host 'Publicar regras via Google Cloud (REST, sem /test)...' -ForegroundColor Yellow
$nodeArgs = @(
    (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'),
    $ProjectId,
    '--force',
    '--max-attempts=40',
    '--prefer-adc'
)
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& node @nodeArgs
$rulesExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap
if ($rulesExit -ne 0) {
    Write-Host ''
    Write-Host 'API ainda indisponivel (503). Watchdog em background:' -ForegroundColor Yellow
    & (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1') -StartBackground
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'Regras Firestore + Storage sincronizadas no Google Cloud.' -ForegroundColor Green
Write-Host 'Indices (se alterados): .\scripts\deploy_firebase_rules.ps1 -OnlyFirestoreIndexes' -ForegroundColor DarkGray
Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
