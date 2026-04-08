# Aplica CORS no bucket do Firebase Storage (Google Cloud Storage).
# Isto NÃO é "regra de segurança" do Firebase: é configuração do bucket GCS
# para o navegador permitir GET/PUT de mídia quando o painel roda em Web (origem diferente do storage.googleapis.com).
#
# Pré-requisitos:
#   - Google Cloud SDK instalado (gsutil no PATH)
#   - Conta com permissão no projeto: Storage Admin ou equivalente
#   - gcloud auth login  (ou Application Default Credentials)
#
# Bucket padrão do projeto Gestão YAHWEH (Firebase Storage):
#   gs://gestaoyahweh-21e23.firebasestorage.app
# (Se o console mostrar outro nome, use: Firebase Console > Storage > Files > copiar gs://...)
#
# Uso (na raiz do repo, PowerShell):
#   .\scripts\apply_storage_cors.ps1
#   .\scripts\apply_storage_cors.ps1 -Apply   # tenta executar gsutil cors set
#
# Cloud Shell: enviar gcs_storage_cors_example.json, depois:
#   gsutil cors set gcs_storage_cors_example.json gs://gestaoyahweh-21e23.firebasestorage.app
#   gsutil cors get gs://gestaoyahweh-21e23.firebasestorage.app
#
param(
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path $ScriptDir -Parent
$Bucket = "gs://gestaoyahweh-21e23.firebasestorage.app"
$Scoped = Join-Path $ScriptDir "gcs_storage_cors_example.json"
$Wide = Join-Path $ScriptDir "cors_storage_wide_open.json"
$CorsNaRaiz = Join-Path $RepoRoot "cors.json"

if (-not (Test-Path $Scoped)) {
    Write-Host "Erro: nao encontrado: $Scoped" -ForegroundColor Red
    exit 1
}

Write-Host "=== CORS do Firebase Storage (GCS) ===" -ForegroundColor Cyan
Write-Host "Bucket: $Bucket"
Write-Host "Config recomendada (origens fixas): $Scoped"
Write-Host "Config ampla (apenas debug): $Wide"
if (Test-Path $CorsNaRaiz) {
    Write-Host "CORS na raiz do repo: $CorsNaRaiz" -ForegroundColor DarkCyan
    Write-Host "Comando (GET * para testes):" -ForegroundColor Green
    Write-Host "  gsutil cors set `"$CorsNaRaiz`" $Bucket"
    Write-Host ""
}
Write-Host "Se usar dominio proprio no Hosting, edite 'origin' em gcs_storage_cors_example.json" -ForegroundColor Yellow
Write-Host "(ex.: https://seudominio.com.br) antes de aplicar."
Write-Host ""
Write-Host "Comando manual (config escopada):" -ForegroundColor Green
Write-Host "  gsutil cors set `"$Scoped`" $Bucket"
Write-Host ""

if (-not $Apply) {
    Write-Host "Para aplicar automaticamente, execute:" -ForegroundColor DarkGray
    Write-Host "  .\scripts\apply_storage_cors.ps1 -Apply"
    exit 0
}

$gsutil = Get-Command gsutil -ErrorAction SilentlyContinue
if (-not $gsutil) {
    Write-Host "gsutil nao encontrado no PATH. Instale Google Cloud SDK ou use Cloud Shell." -ForegroundColor Red
    exit 1
}

$CorsToApply = $Scoped
if (Test-Path $CorsNaRaiz) {
    $CorsToApply = $CorsNaRaiz
    Write-Host "Aplicando CORS da raiz do repo: $CorsToApply" -ForegroundColor Cyan
} else {
    Write-Host "Aplicando CORS escopado: $CorsToApply" -ForegroundColor Cyan
}
& gsutil cors set $CorsToApply $Bucket
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nVerificar:" -ForegroundColor Cyan
& gsutil cors get $Bucket
Write-Host "`nConcluido." -ForegroundColor Green
