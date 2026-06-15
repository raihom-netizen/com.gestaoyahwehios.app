# Pipeline permanente — regras Firebase no Google Cloud (NAO no "banco" Firestore).
# Referencia: prompt_mestre_cursor.md §6.2 | AGENTS.md
#
# O que publica:
#   - firebaserules.googleapis.com (Firestore rules + Storage rules releases)
#   - firestore.indexes.json via Firebase CLI quando necessario
# O que NAO e: gravar regras dentro de documentos Firestore.
#
# Uso (raiz, autorizado / forcar):
#   .\scripts\regras_gcp_automatico_forcado.ps1
# Opcional: -SkipSetup | -SkipCors

param(
    [switch] $SkipSetup,
    [switch] $SkipCors
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host '=== Regras GCP automatico (FORCADO / prompt mestre) ===' -ForegroundColor Cyan
Write-Host 'Destino: Google Cloud firebaserules.googleapis.com (releases), nao dados Firestore.' -ForegroundColor DarkGray
Write-Host 'Pipeline: preflight REST -> firebase_rules_gcp_publish.cjs -> deploy_firebase_rules -ForcePublish' -ForegroundColor DarkGray

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

$ensureFn = Join-Path $RepoRoot 'scripts\ensure_functions_node_for_gcp.ps1'
if (Test-Path $ensureFn) {
    & $ensureFn
}

$install = Join-Path $RepoRoot 'scripts\install_google_cloud_sdk.ps1'
if (Test-Path $install) {
    . $install
    Ensure-GcloudInstalled -RepoRoot $RepoRoot | Out-Null
}

$auth = Join-Path $RepoRoot 'scripts\ensure_google_cloud_auth.ps1'
if (Test-Path $auth) {
    . $auth
    Ensure-GoogleCloudAuth -RepoRoot $RepoRoot | Out-Null
}

if (-not $SkipSetup) {
    Write-Host "`n[setup] APIs + IAM (gcloud quando Owner; Node REST sempre)..." -ForegroundColor Yellow
    & (Join-Path $RepoRoot 'scripts\setup_gcp_firebase_rules_permanent.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host '   Setup com avisos (PERMISSION_DENIED em SA e normal) — continuando publish.' -ForegroundColor DarkYellow
    }
}

Write-Host "`n[deploy] Forcar publicacao (Owner + certificado raiz)..." -ForegroundColor Yellow
& (Join-Path $RepoRoot 'scripts\forcar_regras_gcp_owner.ps1')
$rulesExit = $LASTEXITCODE

if ($rulesExit -ne 0) {
    Write-Host 'Watchdog GCP em background (503 transitório)...' -ForegroundColor Yellow
    $wd = Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1'
    if (Test-Path $wd) { & $wd -StartBackground }
}

if (-not $SkipCors) {
    Write-Host "`n[CORS] Storage (gsutil / gcloud)..." -ForegroundColor Yellow
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & (Join-Path $RepoRoot 'scripts\apply_firebase_storage_cors.ps1')
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -ne 0) {
        Write-Host '   CORS: aviso (auth Owner ou rede) — repita apply_firebase_storage_cors.ps1' -ForegroundColor DarkYellow
    }
}

$state = Join-Path $RepoRoot '.deploy-state\firebase-sync.json'
if (Test-Path $state) {
    Write-Host "Estado: $state" -ForegroundColor DarkGray
}

Write-Host ''
if ($rulesExit -eq 0) {
    Write-Host '=== Regras GCP: OK ===' -ForegroundColor Green
} else {
    Write-Host '=== Regras GCP: pendente (watchdog activo) ===' -ForegroundColor Yellow
}
Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray

exit $rulesExit
