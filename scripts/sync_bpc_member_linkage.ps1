# Alinha alias, slug e tenantId de todos os membros BPC ao doc canónico.
# Uso (na raiz):
#   .\scripts\sync_bpc_member_linkage.ps1 -DryRun
#   .\scripts\sync_bpc_member_linkage.ps1 -Execute
param(
  [switch]$DryRun,
  [switch]$Execute
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Set-Location (Join-Path $RepoRoot "functions")
Write-Host "=== npm run build (functions) ===" -ForegroundColor Cyan
npm run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $RepoRoot
$nodeArgs = @("scripts/sync_bpc_member_linkage.mjs")
if ($Execute) {
  $nodeArgs += "--execute"
} else {
  $nodeArgs += "--dry-run"
}

Write-Host "=== node $($nodeArgs -join ' ') ===" -ForegroundColor Cyan
node @nodeArgs
exit $LASTEXITCODE
