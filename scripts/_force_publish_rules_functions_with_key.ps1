param(
  [string] $Project = 'gestaoyahweh-21e23',
  [string] $KeyPath = 'c:\gestao_yahweh_premium_final\gestaoyahweh-gcp-deploy-key.json'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $KeyPath)) {
  throw "Chave de serviço não encontrada: $KeyPath"
}

$env:GOOGLE_APPLICATION_CREDENTIALS = $KeyPath

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

$gcloudCmd = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
$npmCmd = Join-Path ${env:ProgramFiles} 'nodejs\npm.cmd'

if (-not (Test-Path $gcloudCmd)) {
  throw "gcloud.cmd não encontrado em: $gcloudCmd"
}
if (-not (Test-Path $npmCmd)) {
  throw "npm.cmd não encontrado em: $npmCmd"
}

Write-Host "[1/4] Autenticando gcloud com service account..." -ForegroundColor Cyan
& $gcloudCmd auth activate-service-account --key-file="$KeyPath"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao autenticar service account no gcloud.' }
& $gcloudCmd config set project $Project
if ($LASTEXITCODE -ne 0) { throw 'Falha ao definir projeto no gcloud.' }

Write-Host "[2/4] Publicando regras Firestore via GCP (forçado)..." -ForegroundColor Cyan
$rulesScript = Join-Path $RepoRoot 'scripts\regras_gcp_automatico_forcado.ps1'
& $rulesScript -SkipCors
if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar regras Firestore.' }

Write-Host "[3/4] Build das Cloud Functions..." -ForegroundColor Cyan
& $npmCmd --prefix (Join-Path $RepoRoot 'functions') ci
if ($LASTEXITCODE -ne 0) { throw 'npm ci falhou em functions/.' }
& $npmCmd --prefix (Join-Path $RepoRoot 'functions') run build
if ($LASTEXITCODE -ne 0) { throw 'npm run build falhou em functions/.' }

$functionsSource = Join-Path $RepoRoot 'functions'
$region = 'us-central1'

Write-Host "[4/4] Deploy forçado das funções de push (Firestore triggers)..." -ForegroundColor Cyan

# onCreate avisos
& $gcloudCmd functions deploy onNovoAvisoMuralPush `
  --project=$Project `
  --region=$region `
  --runtime=nodejs22 `
  --source="$functionsSource" `
  --entry-point=onNovoAvisoMuralPush `
  --trigger-event=providers/cloud.firestore/eventTypes/document.create `
  --trigger-resource="projects/$Project/databases/(default)/documents/igrejas/{tenantId}/avisos/{id}" `
  --quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha deploy onNovoAvisoMuralPush.' }

# onUpdate avisos
& $gcloudCmd functions deploy onNovoAvisoMuralPublishedPush `
  --project=$Project `
  --region=$region `
  --runtime=nodejs22 `
  --source="$functionsSource" `
  --entry-point=onNovoAvisoMuralPublishedPush `
  --trigger-event=providers/cloud.firestore/eventTypes/document.update `
  --trigger-resource="projects/$Project/databases/(default)/documents/igrejas/{tenantId}/avisos/{id}" `
  --quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha deploy onNovoAvisoMuralPublishedPush.' }

# onCreate eventos
& $gcloudCmd functions deploy onNovoEventoNoticiaPush `
  --project=$Project `
  --region=$region `
  --runtime=nodejs22 `
  --source="$functionsSource" `
  --entry-point=onNovoEventoNoticiaPush `
  --trigger-event=providers/cloud.firestore/eventTypes/document.create `
  --trigger-resource="projects/$Project/databases/(default)/documents/igrejas/{tenantId}/eventos/{id}" `
  --quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha deploy onNovoEventoNoticiaPush.' }

# onUpdate eventos
& $gcloudCmd functions deploy onNovoEventoNoticiaPublishedPush `
  --project=$Project `
  --region=$region `
  --runtime=nodejs22 `
  --source="$functionsSource" `
  --entry-point=onNovoEventoNoticiaPublishedPush `
  --trigger-event=providers/cloud.firestore/eventTypes/document.update `
  --trigger-resource="projects/$Project/databases/(default)/documents/igrejas/{tenantId}/eventos/{id}" `
  --quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha deploy onNovoEventoNoticiaPublishedPush.' }

Write-Host 'FORÇADO OK: regras + funções publicadas.' -ForegroundColor Green
