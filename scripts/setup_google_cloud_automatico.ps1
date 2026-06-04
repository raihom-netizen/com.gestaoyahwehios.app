# Configuracao unica: Google Cloud alinhado ao projeto gestaoyahweh-21e23 (deploy Firebase).
# Uso (PowerShell, na raiz): .\scripts\setup_google_cloud_automatico.ps1
#
# Faz: PATH gcloud, projeto GCP, login utilizador (browser), ADC, teste token Rules API.

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')
. (Join-Path $RepoRoot 'scripts\ensure_google_cloud_auth.ps1')

Write-Host '=== Gestao YAHWEH — Google Cloud automatico ===' -ForegroundColor Cyan
Write-Host "Projeto: $($script:GoogleCloudProjectId)" -ForegroundColor DarkGray

$script:GoogleCloudAuthReady = $false
if (Ensure-GoogleCloudAuth -RepoRoot $RepoRoot) {
    Write-Host ''
    Write-Host 'Token GCP OK via conta de servico (Node) — pode saltar gcloud login.' -ForegroundColor Green
    Write-Host 'Para preflight completo no browser, instale opcionalmente: winget install Google.CloudSDK' -ForegroundColor DarkGray
    . (Join-Path $RepoRoot 'scripts\firebase_rules_preflight.ps1')
    $pf = Invoke-FirebaseRulesPreflight -RepoRoot $RepoRoot -VerbosePreflight
    if ($pf.AllOk) {
        Write-Host 'Preflight OK — regras sincronizadas.' -ForegroundColor Green
        exit 0
    }
    Write-Host 'Preflight: ainda precisa deploy de regras quando API estavel.' -ForegroundColor DarkYellow
    Write-Host '  .\scripts\deploy_firebase_rules.ps1 -ForcePublish' -ForegroundColor Cyan
    exit 0
}

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host 'Google Cloud SDK nao encontrado e sem token SA. Instale:' -ForegroundColor Yellow
    Write-Host '  winget install Google.CloudSDK' -ForegroundColor Cyan
    Write-Host 'Ou coloque ANDROID/*-firebase-adminsdk*.json e npm install em functions/' -ForegroundColor Yellow
    exit 2
}

Write-Host ''
Write-Host '1/4 Conta utilizador (browser) — necessario para Firebase CLI + Rules API...' -ForegroundColor Yellow
& gcloud auth login --project=$script:GoogleCloudProjectId
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host '2/4 Application Default Credentials (ADC)...' -ForegroundColor Yellow
& gcloud auth application-default login --project=$script:GoogleCloudProjectId
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host '3/4 Projeto activo...' -ForegroundColor Yellow
& gcloud config set project $script:GoogleCloudProjectId
& firebase use $script:GoogleCloudProjectId 2>$null

Write-Host ''
Write-Host '4/4 Teste token + preflight regras...' -ForegroundColor Yellow
$script:GoogleCloudAuthReady = $false
if (-not (Ensure-GoogleCloudAuth -RepoRoot $RepoRoot)) {
    Write-Host 'Falha ao obter token. Verifique login.' -ForegroundColor Red
    exit 3
}

. (Join-Path $RepoRoot 'scripts\firebase_rules_preflight.ps1')
$pf = Invoke-FirebaseRulesPreflight -RepoRoot $RepoRoot -VerbosePreflight
if ($pf.AllOk) {
    Write-Host ''
    Write-Host 'Preflight OK — regras ja sincronizadas (deploy pode saltar API /test).' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host 'Preflight: deploy de regras ainda necessario quando API estiver estavel.' -ForegroundColor DarkYellow
    Write-Host '  .\scripts\deploy_firebase_rules.ps1 -ForcePublish' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Concluido. Deploy completo:' -ForegroundColor Green
Write-Host '  .\scripts\deploy_completo.ps1 -CopyTo D:\Temporarios' -ForegroundColor Cyan
Write-Host 'Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview' -ForegroundColor DarkGray
