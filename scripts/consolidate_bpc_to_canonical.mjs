#!/usr/bin/env node
/**
 * Consolida BPC → igreja_o_brasil_para_cristo_jardim_goiano (Firestore).
 *
 * Uso (na raiz):
 *   node scripts/consolidate_bpc_to_canonical.mjs --dry-run
 *   node scripts/consolidate_bpc_to_canonical.mjs --execute
 *   node scripts/consolidate_bpc_to_canonical.mjs --execute --keep-legacy-docs
 *
 * Credencial: GOOGLE_APPLICATION_CREDENTIALS ou serviceAccountKey.json na raiz.
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const args = process.argv.slice(2);
const dryRun = !args.includes('--execute');
const skipDelete = args.includes('--keep-legacy-docs');

function initAdmin() {
  if (getApps().length) return;
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    resolve(root, 'serviceAccountKey.json');
  if (!existsSync(saPath)) {
    console.error('Credencial não encontrada:', saPath);
    console.error(
      'Defina GOOGLE_APPLICATION_CREDENTIALS apontando para a service account do projeto gestaoyahweh-21e23.',
    );
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(saPath, 'utf8'));
  initializeApp({
    credential: cert(sa),
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
  const run = mod.runConsolidateBpcToCanonical;
  if (typeof run !== 'function') {
    console.error('runConsolidateBpcToCanonical não encontrado em', libPath);
    process.exit(1);
  }

  console.log(
    dryRun
      ? '=== DRY-RUN (nada será gravado). Use --execute para aplicar. ==='
      : '=== EXECUTANDO consolidação BPC (produção) ===',
  );
  if (skipDelete) console.log('Modo: manter docs legados (--keep-legacy-docs)');

  const result = await run({
    dryRun,
    skipDelete,
    skipPanelRecompute: dryRun,
  });

  console.log(JSON.stringify(result, null, 2));
  if (dryRun) {
    console.log('\nRevise o relatório acima. Depois: node scripts/consolidate_bpc_to_canonical.mjs --execute');
  } else {
    console.log('\nConsolidação concluída. Valide o painel e execute deploy web se necessário.');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
