# Publicacao FORCADA regras Firebase — Owner/ADC + certificado na raiz (Gestao YAHWEH).
# Uso (raiz, autorizado): .\scripts\forcar_regras_gcp_owner.ps1
#
# 1) Copia chave SA para raiz (gestaoyahweh-gcp-deploy-key.json) se ainda nao existir
# 2) Preferencia ADC Owner (permissoes totais IAM + Rules API)
# 3) Publica Firestore + Storage via REST (sem CLI /test)
# 4) Publica indices via firestore.googleapis.com

param(
    [switch] $SkipIamGrant,
    [switch] $SkipIndexes
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$ProjectId = 'gestaoyahweh-21e23'

Write-Host '=== Forcar regras GCP (Owner + certificado raiz) ===' -ForegroundColor Cyan

function Initialize-FirebaseTokenFromFile {
    param([string] $RepoRoot)
    if ($env:FIREBASE_TOKEN -and $env:FIREBASE_TOKEN.Trim().Length -gt 20) {
        return $true
    }
    $tokenFile = Join-Path $RepoRoot '.firebase-ci-token'
    if (-not (Test-Path $tokenFile)) { return $false }
    try {
        $token = (Get-Content $tokenFile -Raw).Trim()
        if ($token.Length -gt 20) {
            $env:FIREBASE_TOKEN = $token
            Write-Host 'FIREBASE_TOKEN carregado de .firebase-ci-token (fallback CLI).' -ForegroundColor DarkGray
            return $true
        }
    } catch {}
    return $false
}

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')
. (Join-Path $RepoRoot 'scripts\ensure_google_cloud_auth.ps1')

$rootKey = Join-Path $RepoRoot 'gestaoyahweh-gcp-deploy-key.json'
if (-not (Test-Path $rootKey)) {
    $src = Get-ChildItem -Path (Join-Path $RepoRoot 'ANDROID'), (Join-Path $RepoRoot 'secrets') `
        -Filter 'gestaoyahweh*-firebase-adminsdk*.json' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($src) {
        Copy-Item -Path $src.FullName -Destination $rootKey -Force
        Write-Host "Certificado copiado para raiz: $rootKey" -ForegroundColor Green
    } else {
        Write-Host 'AVISO: chave SA nao encontrada em ANDROID/secrets — usa ADC Owner se disponivel.' -ForegroundColor DarkYellow
    }
}

if (Test-Path $rootKey) {
    $env:GOOGLE_APPLICATION_CREDENTIALS = $rootKey
    $env:YAHWEH_GCP_KEY_FILE = $rootKey
}
$env:YAHWEH_GCP_PREFER_ADC = '1'
$env:YAHWEH_GCP_PREFER_OWNER = '1'

$lock = Join-Path $RepoRoot '.deploy-state\firebase-gcp-watchdog.lock'
$pubLock = Join-Path $RepoRoot '.deploy-state\firebase-rules-publish.lock'
foreach ($p in @($lock, $pubLock)) {
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        Write-Host "Lock removido: $p" -ForegroundColor DarkGray
    }
}

# Evita 429: aguarda quota firebaserules.googleapis.com repor (deploys paralelos anteriores).
Write-Host 'Aguardar 120s (quota API firebaserules repor)...' -ForegroundColor DarkYellow
Start-Sleep -Seconds 120

& (Join-Path $RepoRoot 'scripts\ensure_functions_node_for_gcp.ps1') | Out-Null

Write-Host "`n[1/4] Auth GCP (Owner ADC + certificado raiz)..." -ForegroundColor Yellow
Ensure-GoogleCloudAuth -RepoRoot $RepoRoot -PreferOwner | Out-Null
$acct = (& gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>$null | Select-Object -First 1)
if ($acct) { Write-Host "   gcloud activo: $acct" -ForegroundColor DarkGray }

if (-not $SkipIamGrant) {
    Write-Host "`n[2/4] IAM conta de servico (requer Owner ADC)..." -ForegroundColor Yellow
    & node (Join-Path $RepoRoot 'scripts\grant_gcp_firebase_rules_iam.cjs') --prefer-adc 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host '   IAM: aviso (Owner ADC ausente) — deploy continua com chave SA.' -ForegroundColor DarkYellow
    }
} else {
    Write-Host "`n[2/4] IAM skip (-SkipIamGrant)" -ForegroundColor DarkGray
}

Write-Host "`n[3/4] Regras Firestore + Storage (REST, max 40 tentativas)..." -ForegroundColor Yellow
$nodeArgs = @(
    (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'),
    $ProjectId,
    '--force',
    '--max-attempts=40',
    '--prefer-adc'
)
$rulesOut = & node @nodeArgs 2>&1
$rulesOut | ForEach-Object { Write-Host $_ }
$rulesOk = ($LASTEXITCODE -eq 0) -or ($rulesOut -match 'YAHWEH_GCP_OK=.*"ok":true')

if (-not $rulesOk) {
    Write-Host '   REST com ADC falhou — retry com chave SA raiz...' -ForegroundColor DarkYellow
    $env:YAHWEH_GCP_PREFER_ADC = '0'
    $env:YAHWEH_GCP_PREFER_OWNER = '0'
    if (Test-Path $rootKey) {
        $env:GOOGLE_APPLICATION_CREDENTIALS = $rootKey
        $env:YAHWEH_GCP_KEY_FILE = $rootKey
    }
    $rulesOut2 = & node @nodeArgs 2>&1
    $rulesOut2 | ForEach-Object { Write-Host $_ }
    $rulesOk = ($LASTEXITCODE -eq 0) -or ($rulesOut2 -match 'YAHWEH_GCP_OK=.*"ok":true')
}

if (-not $SkipIndexes) {
    Write-Host "`n[4/4] Indices Firestore (REST)..." -ForegroundColor Yellow
    $env:YAHWEH_GCP_PREFER_ADC = '1'
    $idxOut = & node (Join-Path $RepoRoot 'scripts\firebase_indexes_gcp_publish.cjs') --force --max-attempts=25 2>&1
    $idxOut | ForEach-Object { Write-Host $_ }
    $idxOk = ($LASTEXITCODE -eq 0) -or ($idxOut -match 'YAHWEH_INDEXES_OK=.*"ok":true')
} else {
    $idxOk = $true
    Write-Host "`n[4/4] Indices skip (-SkipIndexes)" -ForegroundColor DarkGray
}

Write-Host ''
if ($rulesOk -and $idxOk) {
    Write-Host '=== REGRAS + INDICES PUBLICADOS (Google Cloud) ===' -ForegroundColor Green
    Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
    exit 0
}

if (-not $rulesOk) {
    Write-Host 'Firestore rules ainda pendentes (503 API Google). Watchdog em background...' -ForegroundColor Yellow
    Write-Host 'Tentando fallback via Firebase CLI (estilo Controle Total)...' -ForegroundColor Yellow
    $hasCiToken = Initialize-FirebaseTokenFromFile -RepoRoot $RepoRoot
    & (Join-Path $RepoRoot 'scripts\deploy_firebase_rules.ps1') -UseCliRules -ForcePublish -MaxAttempts 6
    $cliExit = $LASTEXITCODE
    if ($cliExit -eq 0) {
        Write-Host 'Fallback CLI concluiu regras com sucesso.' -ForegroundColor Green
        if ($idxOk) {
            Write-Host '=== REGRAS + INDICES PUBLICADOS (fallback CLI rules) ===' -ForegroundColor Green
        } else {
            Write-Host '=== REGRAS PUBLICADAS (indices pendentes) ===' -ForegroundColor Yellow
        }
        Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
        exit 0
    }
    if (-not $hasCiToken) {
        Write-Host 'Dica: crie .firebase-ci-token na raiz (firebase login:ci) para fallback CLI sem login interativo.' -ForegroundColor DarkYellow
    }
    & (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1') -StartBackground
}
Write-Host 'Parcial — repita quando API estavel ou execute setup_google_cloud_automatico.ps1 (Owner login).' -ForegroundColor DarkYellow
exit 1
