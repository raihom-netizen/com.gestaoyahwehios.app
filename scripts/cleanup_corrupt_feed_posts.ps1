# Limpeza avisos/eventos corrompidos (sem titulo valido ou sem midia).
#
# Simular:
#   .\scripts\cleanup_corrupt_feed_posts.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano
#
# Executar DELETE:
#   .\scripts\cleanup_corrupt_feed_posts.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano -Execute

param(
  [string]$Igreja = "",
  [switch]$Execute
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

  $nodeArgs = @("scripts/cleanup-corrupt-feed-posts.js")
  if ($Igreja.Trim()) {
    $nodeArgs += "--igreja=$($Igreja.Trim())"
  }
  if (-not $Execute) {
    $nodeArgs += "--dry-run"
    Write-Host "Modo simulacao (adicione -Execute para apagar)." -ForegroundColor Yellow
  } else {
    $nodeArgs += "--execute"
    Write-Host "Modo DELETE — registros corrompidos serao apagados." -ForegroundColor Red
  }

  node @nodeArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

Write-Host "Script concluido." -ForegroundColor Green
