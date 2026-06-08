#!/usr/bin/env node
/**
 * Audita se tudo BPC está no doc canónico igreja_o_brasil_para_cristo_jardim_goiano.
 */
import { createRequire } from 'module';
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const CANONICAL = 'igreja_o_brasil_para_cristo_jardim_goiano';
const PUBLIC_SLUG = 'o-brasil-cristo-jardim-goiano';
const LEGACY = [
  'brasilparacristo',
  'brasilparacristo_sistema',
  'iobpc-jardim-goiano',
  'o-brasil-cristo-jardim-goiano',
];

const KEY_COLLECTIONS = [
  'membros',
  'avisos',
  'eventos',
  'noticias',
  'agenda',
  'cargos',
  'escalas',
  'departamentos',
  'patrimonio',
  'contas',
  'event_templates',
];

function initAdmin() {
  const require = createRequire(resolve(root, 'functions/package.json'));
  const admin = require('firebase-admin');
  if (admin.apps.length) return admin;
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    resolve(root, 'ANDROID/gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json') ||
    resolve(root, 'serviceAccountKey.json');
  if (!existsSync(saPath)) {
    console.error('Credencial não encontrada');
    process.exit(1);
  }
  const sa = JSON.parse(readFileSync(saPath, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    projectId: sa.project_id || 'gestaoyahweh-21e23',
  });
  return admin;
}

async function countCol(db, churchId, col) {
  try {
    const snap = await db.collection('igrejas').doc(churchId).collection(col).count().get();
    return snap.data().count;
  } catch {
    const snap = await db.collection('igrejas').doc(churchId).collection(col).limit(500).get();
    return snap.size;
  }
}

async function sampleWrongTenant(db, churchId, col, limit = 5) {
  const snap = await db
    .collection('igrejas')
    .doc(churchId)
    .collection(col)
    .limit(200)
    .get();
  const wrong = [];
  for (const d of snap.docs) {
    const data = d.data();
    const tid = String(data.tenantId ?? data.igrejaId ?? data.churchId ?? '').trim();
    if (tid && tid !== CANONICAL && LEGACY.includes(tid)) {
      wrong.push({ id: d.id, tenantId: tid });
      if (wrong.length >= limit) break;
    }
  }
  return { scanned: snap.size, wrong };
}

async function main() {
  const admin = initAdmin();
  const db = admin.firestore();

  console.log('=== AUDIT BPC — caminho único ===\n');

  // Legacy church docs
  for (const leg of LEGACY) {
    const snap = await db.collection('igrejas').doc(leg).get();
    console.log(`igrejas/${leg}: ${snap.exists ? 'EXISTE (problema!)' : 'ok (ausente)'}`);
  }

  // Church root fields
  const church = await db.collection('igrejas').doc(CANONICAL).get();
  if (!church.exists) {
    console.error('Doc canónico ausente!');
    process.exit(1);
  }
  const c = church.data();
  console.log('\nDoc canónico:');
  console.log('  tenantId:', c.tenantId);
  console.log('  slug:', c.slug);
  console.log('  slugId:', c.slugId);
  console.log('  alias:', c.alias);

  const churchOk =
    String(c.tenantId).trim() === CANONICAL &&
    String(c.slug).trim() === PUBLIC_SLUG &&
    String(c.slugId).trim() === PUBLIC_SLUG &&
    String(c.alias).trim() === PUBLIC_SLUG;
  console.log('  campos raiz OK:', churchOk ? 'SIM' : 'NÃO');

  // Subcollections
  console.log('\nSubcoleções no canónico:');
  for (const col of KEY_COLLECTIONS) {
    const n = await countCol(db, CANONICAL, col);
    const legCounts = [];
    for (const leg of LEGACY) {
      const ln = await countCol(db, leg, col);
      if (ln > 0) legCounts.push(`${leg}:${ln}`);
    }
    let wrongInfo = '';
    if (n > 0) {
      const { scanned, wrong } = await sampleWrongTenant(db, CANONICAL, col);
      if (wrong.length) {
        wrongInfo = ` | tenant legado em ${wrong.length}/${scanned} amostra`;
      }
    }
    console.log(
      `  ${col}: ${n}${legCounts.length ? ' | legado: ' + legCounts.join(', ') : ''}${wrongInfo}`,
    );
  }

  // Users with legacy tenant
  let usersLegacy = 0;
  for (const leg of [...LEGACY, CANONICAL]) {
    const snap = await db.collection('users').where('tenantId', '==', leg).limit(100).get();
    if (leg !== CANONICAL && snap.size) usersLegacy += snap.size;
  }
  console.log('\nusers com tenantId legado:', usersLegacy);

  // church_aliases sample
  for (const alias of ['o-brasil-cristo-jardim-goiano', 'brasilparacristo']) {
    const a = await db.collection('church_aliases').doc(alias).get();
    console.log(
      `church_aliases/${alias}:`,
      a.exists ? `→ ${a.data()?.canonicalId}` : 'ausente',
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
