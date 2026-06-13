# Backfill churchId + tenantId em igrejas/{churchId}/** (Firestore produção)
param(
  [string]$ChurchId = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $root "functions")

Write-Host "Compilando Cloud Functions..."
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

$nodeArgs = @("tools/backfill_church_tenant_fields.cjs")
if ($ChurchId.Trim()) { $nodeArgs += $ChurchId.Trim() }

Write-Host "Executando backfill tenant fields..."
node @nodeArgs
$code = $LASTEXITCODE
Pop-Location
exit $code
