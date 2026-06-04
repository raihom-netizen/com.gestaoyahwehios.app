# Garante node_modules em functions/ (googleapis para IAM grant e REST).
# Uso: .\scripts\ensure_functions_node_for_gcp.ps1
# Chamado automaticamente por setup_gcp_firebase_rules_permanent.ps1 e regras_gcp_automatico_forcado.ps1

param(
    [switch] $ProductionOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FnDir = Join-Path $RepoRoot 'functions'

if (-not (Test-Path (Join-Path $FnDir 'package.json'))) {
    Write-Host 'AVISO: functions/package.json ausente - skip npm (grant IAM via gcloud).' -ForegroundColor Yellow
    exit 0
}

$googleapisPath = Join-Path $FnDir 'node_modules\googleapis'
if ((Test-Path $googleapisPath) -and $ProductionOnly) {
    Write-Host 'OK: googleapis ja instalado em functions/' -ForegroundColor DarkGray
    exit 0
}

if (Test-Path $googleapisPath) {
    exit 0
}

Write-Host 'Instalando dependencias functions/ (googleapis + google-auth-library)...' -ForegroundColor Yellow
Push-Location $FnDir
try {
    if (Test-Path 'package-lock.json') {
        npm ci --omit=dev 2>&1 | ForEach-Object { Write-Host $_ }
    } else {
        npm install --omit=dev 2>&1 | ForEach-Object { Write-Host $_ }
    }
    if (-not (Test-Path 'node_modules\googleapis')) {
        Write-Host 'ERRO: googleapis nao encontrado apos npm ci.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'OK: functions/node_modules pronto para grant IAM e REST.' -ForegroundColor Green
}
finally {
    Pop-Location
}
