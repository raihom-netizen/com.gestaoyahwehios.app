#!/usr/bin/env node
/**
 * Semeia church_aliases → canonicalId (multi-tenant).
 * Uso: node scripts/seed_church_aliases.mjs
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

const CANONICAL = 'igreja_o_brasil_para_cristo_jardim_goiano';

const ALIASES = [
  'brasilparacristo_sistema',
  'brasilparacristo',
  'bpc_jd',
  'igreja_jardim',
  'iobpc-jardim-goiano',
  'o-brasil-cristo-jardim-goiano',
];

function initAdmin() {
  if (getApps().length) return;
  const saPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
    || resolve(root, 'serviceAccountKey.json');
  if (!existsSync(saPath)) {
    console.error('Credencial não encontrada:', saPath);
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(saPath, 'utf8'));
  initializeApp({ credential: cert(sa) });
}

async function main() {
  initAdmin();
  const db = getFirestore();
  const batch = db.batch();
  for (const alias of ALIASES) {
    const ref = db.collection('church_aliases').doc(alias);
    batch.set(
      ref,
      {
        canonicalId: CANONICAL,
        alias,
        updatedAt: FieldValue.serverTimestamp(),
        source: 'seed_church_aliases.mjs',
      },
      { merge: true },
    );
  }
  await batch.commit();
  console.log(`OK: ${ALIASES.length} aliases → ${CANONICAL}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
