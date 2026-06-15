# Publicacao urgente regras — SA Owner (firebase-adminsdk) + throttle quota API.
# Uso: .\scripts\publicar_regras_owner_urgente.ps1

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

$key = Join-Path $RepoRoot 'gestaoyahweh-gcp-deploy-key.json'
if (-not (Test-Path $key)) {
    $src = Get-ChildItem ANDROID, secrets, $RepoRoot -Filter 'gestaoyahweh*-firebase-adminsdk*.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($src) { Copy-Item $src.FullName $key -Force }
}
if (-not (Test-Path $key)) {
    Write-Host 'ERRO: gere chave em Firebase Console > Configuracoes > Contas de servico > Gerar nova chave privada' -ForegroundColor Red
    exit 1
}

$sa = (Get-Content $key -Raw | ConvertFrom-Json).client_email
Write-Host "SA Owner: $sa" -ForegroundColor Cyan

Remove-Item (Join-Path $RepoRoot '.deploy-state\*.lock') -Force -ErrorAction SilentlyContinue
$env:GOOGLE_APPLICATION_CREDENTIALS = $key
$env:YAHWEH_GCP_KEY_FILE = $key
$env:YAHWEH_GCP_PREFER_ADC = '0'
$env:YAHWEH_GCP_PREFER_OWNER = '0'

if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    & gcloud auth activate-service-account $sa --key-file=$key --project=gestaoyahweh-21e23 2>$null | Out-Null
}

Write-Host 'Cooldown 90s (quota firebaserules 1 req/min)...' -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host '[1/2] Firestore rules (REST)...' -ForegroundColor Yellow
& node (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs') gestaoyahweh-21e23 --force --max-attempts=15 --only=firestore
$fsOk = ($LASTEXITCODE -eq 0)

Write-Host 'Pausa 75s entre alvos...' -ForegroundColor DarkGray
Start-Sleep -Seconds 75

Write-Host '[2/2] Storage rules (REST)...' -ForegroundColor Yellow
& node (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs') gestaoyahweh-21e23 --force --max-attempts=10 --only=storage
$stOk = ($LASTEXITCODE -eq 0)

if ($fsOk -and $stOk) {
    Write-Host '=== REGRAS PUBLICADAS ===' -ForegroundColor Green
    exit 0
}

Write-Host 'REST falhou (503 API Google). Tentativa CLI...' -ForegroundColor Yellow
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
& firebase deploy --only firestore:rules,storage --project gestaoyahweh-21e23 --non-interactive
if ($LASTEXITCODE -eq 0) { exit 0 }

Write-Host @'

FALHA API Google (503). Publicacao manual (2 min):
1. https://console.firebase.google.com/project/gestaoyahweh-21e23/firestore/rules
2. Cole o conteudo de firestore.rules da raiz do repo > Publicar
3. https://console.firebase.google.com/project/gestaoyahweh-21e23/storage/rules
4. Cole storage.rules > Publicar

Conta com permissao: raihom@gmail.com (Proprietario) ou SA firebase-adminsdk-fbsvc (Owner).
'@ -ForegroundColor DarkYellow
exit 1
