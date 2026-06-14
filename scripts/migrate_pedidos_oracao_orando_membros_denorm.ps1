# Migração pedidos de oração — orandoMembros denormalizados a partir de orandoUids.
# Requer Admin SDK (conta de serviço ou gcloud application-default login).
#
# Simular (padrao — nao grava):
#   .\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1
#   .\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano
#
# Executar gravacao:
#   .\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Execute
#
# Reprocessar todos (mesmo com orandoMembros ja preenchido):
#   .\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Execute -Force

param(
  [string]$Igreja = "",
  [switch]$Execute,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot "ensure_gestao_yahweh_toolchain_path.ps1")
. (Join-Path $PSScriptRoot "ensure_google_cloud_auth.ps1")

Push-Location (Join-Path $repoRoot "functions")
try {
  if (-not (Test-Path "node_modules\firebase-admin")) {
    Write-Host "npm install em functions/ ..." -ForegroundColor Cyan
    npm install --no-audit --no-fund 2>&1 | Out-Host
  }

  $nodeArgs = @("scripts/migrate-pedidos-oracao-orando-membros-denorm.js")
  if ($Igreja.Trim()) {
    $nodeArgs += "--igreja=$($Igreja.Trim())"
  }
  if (-not $Execute) {
    $nodeArgs += "--dry-run"
    Write-Host "Modo simulacao (adicione -Execute para gravar)." -ForegroundColor Yellow
  } else {
    Write-Host "Modo GRAVACAO - merge Firestore." -ForegroundColor Magenta
  }
  if ($Force) { $nodeArgs += "--force" }

  node @nodeArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

Write-Host "Script concluido." -ForegroundColor Green
