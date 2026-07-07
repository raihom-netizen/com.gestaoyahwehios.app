param(
    [string] $Project = 'gestaoyahweh-21e23',
    [string] $KeyPath = 'c:\gestao_yahweh_premium_final\gestaoyahweh-gcp-deploy-key.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $KeyPath)) {
    Write-Error "Chave de deploy não encontrada em: $KeyPath"
    exit 1
}

$env:GOOGLE_APPLICATION_CREDENTIALS = $KeyPath

$scriptPath = Join-Path $PSScriptRoot 'publish_force_update_online.ps1'
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script base não encontrado: $scriptPath"
    exit 1
}

& $scriptPath -Project $Project
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Publicação com chave concluída." -ForegroundColor Green
