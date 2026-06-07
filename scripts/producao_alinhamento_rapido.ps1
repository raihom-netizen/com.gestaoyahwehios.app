# Alinhamento rapido producao — Firebase + Google Cloud + web (Gestao YAHWEH).
# Igreja piloto: Brasil para Cristo (tenant brasilparacristo_sistema).
# Uso (raiz): .\scripts\producao_alinhamento_rapido.ps1
# Opcional: -SkipWeb | -SkipCors | -SkipFunctions

param(
    [switch] $SkipWeb,
    [switch] $SkipCors,
    [switch] $SkipFunctions,
    [switch] $SkipGate
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$script:ProducaoHadFailure = $false

function Note-StepFailure([string]$msg) {
    $script:ProducaoHadFailure = $true
    Write-Host $msg -ForegroundColor Yellow
}

Write-Host '=== Producao rapida — Gestao YAHWEH ===' -ForegroundColor Cyan
Write-Host 'Piloto: Brasil para Cristo (brasilparacristo_sistema)' -ForegroundColor DarkGray

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

if (-not $SkipGate) {
    Write-Host "`n[1] Gate producao (checklist)..." -ForegroundColor Yellow
    & (Join-Path $RepoRoot 'scripts\verify_production_checklist.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Gate falhou — corrija ou use -SkipGate (nao recomendado).' -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "`n[2] Regras GCP automatico (prompt mestre, forcado)..." -ForegroundColor Yellow
& (Join-Path $RepoRoot 'scripts\regras_gcp_automatico_forcado.ps1') -SkipCors
if ($LASTEXITCODE -ne 0) { Note-StepFailure 'Regras GCP: watchdog em background; web pode continuar.' }

if (-not $SkipCors) {
    Write-Host "`n[4] CORS Storage (fotos web)..." -ForegroundColor Yellow
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & (Join-Path $RepoRoot 'scripts\apply_firebase_storage_cors.ps1')
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -ne 0) { Note-StepFailure 'CORS: falhou (gcloud auth ou rede). Repita apply_firebase_storage_cors.ps1' }
}

if (-not $SkipFunctions) {
    Write-Host "`n[5] Cloud Functions (ensureBrasilParaCristo + painel)..." -ForegroundColor Yellow
    Push-Location (Join-Path $RepoRoot 'functions')
    if (-not (Test-Path 'node_modules')) {
        npm ci 2>&1 | ForEach-Object { Write-Host $_ }
    }
    npm run build 2>&1 | ForEach-Object { Write-Host $_ }
    Pop-Location
    firebase deploy --only functions:ensureBrasilParaCristoAccess,functions:syncChurchClusterDataFromRichest,functions:syncChurchMercadoPagoFromCluster,functions:syncGestorBrasilParaCristo,functions:seedGestorBrasilParaCristo,functions:getChurchPanelSnapshot,functions:getMasterDashboardSnapshot,functions:getMasterChurchesList,functions:scheduledRefreshMasterChurchesList,functions:scheduledRefreshMasterDashboard,functions:resolveStorageDisplayUrls --force 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { Note-StepFailure 'Functions parciais: verifique login firebase.' }
}

if (-not $SkipWeb) {
    Write-Host "`n[6] Web hosting (painel rapido)..." -ForegroundColor Yellow
    & (Join-Path $RepoRoot 'scripts\deploy_web_hosting.ps1')
    if ($LASTEXITCODE -ne 0) {
        Note-StepFailure 'Web hosting falhou.'
        exit $LASTEXITCODE
    }
}

Write-Host ''
if ($script:ProducaoHadFailure) {
    Write-Host '=== Producao com avisos (ver mensagens acima) ===' -ForegroundColor Yellow
} else {
    Write-Host '=== Producao alinhada ===' -ForegroundColor Green
}
Write-Host 'Web: https://gestaoyahweh-21e23.web.app (Ctrl+F5)' -ForegroundColor Cyan
Write-Host 'Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview' -ForegroundColor DarkGray
Write-Host 'Piloto: login gestor raihom@gmail.com > Garantir acesso Brasil para Cristo (se necessario)' -ForegroundColor DarkGray
Write-Host 'Manual: docs/PRODUCAO_PREMIUM_MISSAO.md + prompt_mestre_cursor.md' -ForegroundColor DarkGray
