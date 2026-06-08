#!/usr/bin/env node
/**
 * Alinha alias/slug/tenantId de todos os membros BPC ao doc canónico.
 *
 * Uso (na raiz):
 *   node scripts/sync_bpc_member_linkage.mjs --dry-run
 *   node scripts/sync_bpc_member_linkage.mjs --execute
 *
 * Credencial: GOOGLE_APPLICATION_CREDENTIALS ou serviceAccountKey.json na raiz.
 */
import { createRequire } from 'module';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const args = process.argv.slice(2);
const dryRun = !args.includes('--execute');

function initAdmin() {
  const require = createRequire(resolve(root, 'functions/package.json'));
  const admin = require('firebase-admin');
  if (admin.apps.length) return;
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    resolve(root, 'serviceAccountKey.json');
  if (!existsSync(saPath)) {
    console.error('Credencial não encontrada:', saPath);
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(saPath, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id || 'gestaoyahweh-21e23',
  });
}

async function main() {
  initAdmin();
  const libPath = resolve(root, 'functions/lib/consolidateBpcCluster.js');
  if (!existsSync(libPath)) {
    console.error('Compile as functions primeiro: cd functions && npm run build');
    process.exit(1);
  }
  const mod = await import(pathToFileURL(libPath).href);
  const run = mod.runSyncBpcMemberTenantLinkage;
  if (typeof run !== 'function') {
    console.error('runSyncBpcMemberTenantLinkage não encontrado em', libPath);
    process.exit(1);
  }

  console.log(
    dryRun
      ? '=== DRY-RUN — alias/slug/tenantId membros BPC ==='
      : '=== EXECUTANDO sync membros BPC (produção) ===',
  );

  const result = await run({ dryRun, recomputeDirectory: !dryRun });
  console.log(JSON.stringify(result, null, 2));

  if (dryRun) {
    console.log('\nRevise acima. Depois: node scripts/sync_bpc_member_linkage.mjs --execute');
  } else {
    console.log('\nSync concluído. Valide um doc em igrejas/.../membros no Console.');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
