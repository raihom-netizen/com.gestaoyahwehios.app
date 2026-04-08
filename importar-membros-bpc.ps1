# Importa membros BPC automaticamente (CSV -> Firestore + Auth)
# Uso: na raiz do projeto execute: .\importar-membros-bpc.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

$csvPath = Join-Path $root "membros_igrebrasilparacristo\PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv"
$keyPath = Join-Path $root "secrets\gestaoyahweh-21e23-7951f1817911.json"

if (-not (Test-Path $csvPath)) {
    Write-Host "CSV nao encontrado: $csvPath" -ForegroundColor Red
    exit 1
}

if (Test-Path $keyPath) {
    $env:GOOGLE_APPLICATION_CREDENTIALS = $keyPath
    Write-Host "Credenciais: $keyPath" -ForegroundColor Green
} else {
    Write-Host "Aviso: secrets\gestaoyahweh-21e23-7951f1817911.json nao encontrado. Defina GOOGLE_APPLICATION_CREDENTIALS ou use gcloud auth application-default login." -ForegroundColor Yellow
}

$scriptsDir = Join-Path $root "scripts"
if (-not (Test-Path (Join-Path $scriptsDir "node_modules"))) {
    Write-Host "Instalando dependencias em scripts..." -ForegroundColor Cyan
    Set-Location $scriptsDir
    npm install
    Set-Location $root
}

Write-Host "Importando: $csvPath" -ForegroundColor Cyan
Set-Location $scriptsDir
node import-members-bpc.js "$csvPath"
$exit = $LASTEXITCODE
Set-Location $root

if ($exit -eq 0) {
    Write-Host "Importacao concluida." -ForegroundColor Green
} else {
    Write-Host "Importacao falhou (codigo $exit)." -ForegroundColor Red
}
exit $exit
