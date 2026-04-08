# Aplica CORS permissivo GET no bucket do Firebase Storage (gestaoyahweh.com.br / painel web).
# Arquivo canónico: cors.json na RAIZ do repositório (mesmo conteúdo que o Gemini/CORS docs).
# Requer: Google Cloud SDK (gsutil) e permissão no projeto gestaoyahweh-21e23.
# O Firebase CLI (`firebase login`) NÃO substitui o login do gcloud para gsutil — execute uma vez:
#   gcloud auth login
#   gcloud config set project gestaoyahweh-21e23
# Comando equivalente manual:
#   gsutil cors set cors.json gs://gestaoyahweh-21e23.firebasestorage.app
# Uso (na raiz do repo): .\scripts\apply_firebase_storage_cors.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$bucket = 'gs://gestaoyahweh-21e23.firebasestorage.app'
$corsFile = Join-Path $RepoRoot 'cors.json'
if (-not (Test-Path $corsFile)) {
    $corsFile = Join-Path $PSScriptRoot 'firebase_storage_cors_open_get.json'
}
if (-not (Test-Path $corsFile)) {
    Write-Error "cors.json nao encontrado na raiz do repo nem em scripts/."
}

# Garantir PATH nesta sessão (instalação recente do Cloud SDK sem reiniciar o terminal)
$gcloudBins = @(
    "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin",
    "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin",
    "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin"
)
foreach ($b in $gcloudBins) {
    if (Test-Path $b) {
        $env:Path = "$b;$env:Path"
    }
}

if (-not (Get-Command gsutil -ErrorAction SilentlyContinue)) {
    Write-Error 'gsutil nao encontrado. Instale Google Cloud SDK (winget install Google.CloudSDK) e reabra o terminal.'
}

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error 'gcloud nao encontrado. Instale Google Cloud SDK.'
}

$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
$authOut = (& gcloud auth list 2>&1 | ForEach-Object { "$_" }) -join "`n"
$ErrorActionPreference = $oldEap
$activeAcct = $null
if ($authOut -match '\*\s+(\S+@\S+)') {
    $activeAcct = $Matches[1]
} elseif ($authOut -match '(\S+@\S+)') {
    $activeAcct = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($activeAcct)) {
    Write-Host ""
    Write-Host "ERRO: gcloud nao tem conta (gsutil precisa disto, diferente do 'firebase login')." -ForegroundColor Yellow
    Write-Host "Execute no PowerShell e volte a correr este script:" -ForegroundColor Yellow
    Write-Host "  gcloud auth login" -ForegroundColor Cyan
    Write-Host "  gcloud config set project gestaoyahweh-21e23" -ForegroundColor Cyan
    Write-Host ""
    exit 2
}
Write-Host "Conta gcloud ativa: $activeAcct" -ForegroundColor DarkGray

Write-Host "Aplicando CORS em $bucket ..."
& gsutil cors set $corsFile $bucket
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'CORS atual:'
& gsutil cors get $bucket
