# Migração Storage → arquitetura consolidada (membros, avisos, eventos, património)
# Uso:
#   .\scripts\run_migrate_storage_consolidado.ps1                    # dry-run todas igrejas
#   .\scripts\run_migrate_storage_consolidado.ps1 -Execute         # aplicar
#   .\scripts\run_migrate_storage_consolidado.ps1 -IgrejaId "slug" -Execute

param(
  [switch]$Execute,
  [string]$IgrejaId = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $root "functions")

Write-Host "=== Gestao YAHWEH — Migracao Storage consolidada ===" -ForegroundColor Cyan
Write-Host "Modo: $(if ($Execute) { 'EXECUTE (grava)' } else { 'DRY-RUN (simulacao)' })"

npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

$env:STORAGE_MIGRATION_EXECUTE = if ($Execute) { "true" } else { "false" }
$env:STORAGE_MIGRATION_TENANT = $IgrejaId

node -e @"
const admin = require('firebase-admin');
const { runStorageConsolidationMigration } = require('./lib/migrateStorageConsolidated');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'gestaoyahweh-21e23';
const bucket = process.env.FIREBASE_STORAGE_BUCKET || 'gestaoyahweh-21e23.firebasestorage.app';

if (!admin.apps.length) {
  admin.initializeApp({ projectId, storageBucket: bucket });
}

const execute = process.env.STORAGE_MIGRATION_EXECUTE === 'true';
const tenant = (process.env.STORAGE_MIGRATION_TENANT || '').trim();

(async () => {
  const out = await runStorageConsolidationMigration({
    tenantId: tenant || undefined,
    allTenants: !tenant,
    modules: ['all'],
    dryRun: !execute,
  });
  console.log(JSON.stringify(out, null, 2));
  process.exit(out.ok ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
"@

$code = $LASTEXITCODE
Pop-Location
exit $code
