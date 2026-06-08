# Consolida Igreja O Brasil Para Cristo num unico doc Firestore.
# Uso (na raiz):
#   .\scripts\consolidate_bpc_to_canonical.ps1 -DryRun
#   .\scripts\consolidate_bpc_to_canonical.ps1 -Execute
param(
  [switch]$DryRun,
  [switch]$Execute,
  [switch]$KeepLegacyDocs
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Set-Location (Join-Path $RepoRoot "functions")
Write-Host "=== npm run build (functions) ===" -ForegroundColor Cyan
npm run build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $RepoRoot
$nodeArgs = @("scripts/consolidate_bpc_to_canonical.mjs")
if ($Execute) {
  $nodeArgs += "--execute"
} else {
  $nodeArgs += "--dry-run"
}
if ($KeepLegacyDocs) {
  $nodeArgs += "--keep-legacy-docs"
}

Write-Host "=== node $($nodeArgs -join ' ') ===" -ForegroundColor Cyan
node @nodeArgs
exit $LASTEXITCODE
