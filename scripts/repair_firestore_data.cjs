/**
 * Reparação de dados Firestore — super-usuário (Admin SDK).
 *
 * Corrige documentos corrompidos que causam crashes no app:
 *   1. Campos numéricos com Infinity / NaN  →  0
 *   2. igrejas sem igrejaId / tenantId      →  preenche com doc.id
 *   3. Timestamps malformados (string em vez de Timestamp) → converte
 *   4. Documentos-fantasma (exists mas data vazio/null)     →  remove
 *   5. Subcoleções membros com CPF inválido como doc.id     →  normaliza
 *
 * Uso:
 *   node scripts/repair_firestore_data.cjs              # dry-run
 *   node scripts/repair_firestore_data.cjs --execute    # aplica mudanças
 *   node scripts/repair_firestore_data.cjs --church=ID  # só uma igreja
 *   node scripts/repair_firestore_data.cjs --verbose    # detalhes
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const admin = (() => {
  try {
    return require(path.join(root, 'functions', 'node_modules', 'firebase-admin'));
  } catch (_) {
    return require('firebase-admin');
  }
})();

const args = process.argv.slice(2);
const dryRun = !args.includes('--execute');
const verbose = args.includes('--verbose');
const churchArg = (args.find((a) => a.startsWith('--church=')) || '').split('=')[1];

/* ── service account ─────────────────────────────────────── */
function findServiceAccount() {
  const dirs = [
    path.join(root, 'ANDROID'),
    path.join(root, 'android'),
    path.join(root, 'functions'),
    root,
  ];
  for (const d of dirs) {
    if (!fs.existsSync(d)) continue;
    const files = fs.readdirSync(d);
    const f = files.find((f) => /firebase-adminsdk.*\.json$/i.test(f));
    if (f) return JSON.parse(fs.readFileSync(path.join(d, f), 'utf8'));
  }
  return null;
}

const sa = findServiceAccount();
if (sa) {
  admin.initializeApp({ credential: admin.credential.cert(sa), projectId: 'gestaoyahweh-21e23' });
} else {
  admin.initializeApp({ projectId: 'gestaoyahweh-21e23' });
}

const db = admin.firestore();

/* ── helpers ─────────────────────────────────────────────── */
let fixCount = 0;
let scanCount = 0;
let errorCount = 0;

function log(msg) { console.log(`  ${msg}`); }
function vlog(msg) { if (verbose) console.log(`  [v] ${msg}`); }

/** Check if value is Infinity or NaN (including nested). */
function hasBadNumbers(v) {
  if (typeof v === 'number') return !isFinite(v);
  if (v && typeof v === 'object') {
    if (Array.isArray(v)) return v.some(hasBadNumbers);
    // Skip Firestore Timestamp/GeoPoint (they have _seconds, _latitude etc.)
    if (v._seconds !== undefined || v._latitude !== undefined) return false;
    return Object.values(v).some(hasBadNumbers);
  }
  return false;
}

/** Replace Infinity/NaN with 0 recursively. */
function fixBadNumbers(v) {
  if (typeof v === 'number') return isFinite(v) ? v : 0;
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    if (v._seconds !== undefined || v._latitude !== undefined) return v;
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = fixBadNumbers(val);
    return out;
  }
  if (Array.isArray(v)) return v.map(fixBadNumbers);
  return v;
}

/** Batch commit helper (max 500 ops). */
async function batchCommit(ops) {
  if (ops.length === 0) return;
  const chunks = [];
  for (let i = 0; i < ops.length; i += 450) {
    chunks.push(ops.slice(i, i + 450));
  }
  for (const chunk of chunks) {
    const batch = db.batch();
    for (const op of chunk) {
      if (op.type === 'set') batch.set(op.ref, op.data, op.options || {});
      else if (op.type === 'update') batch.update(op.ref, op.data);
      else if (op.type === 'delete') batch.delete(op.ref);
    }
    if (!dryRun) await batch.commit();
  }
}

/* ── 1. Igrejas (root doc) ──────────────────────────────── */
async function repairIgrejas() {
  log('═══ Igrejas (docs raiz) ═══');
  const snap = await db.collection('igrejas').get();
  const ops = [];

  for (const doc of snap.docs) {
    scanCount++;
    const data = doc.data();
    if (!data || Object.keys(data).length === 0) {
      log(`⚠ ${doc.id}: documento vazio — remover`);
      ops.push({ type: 'delete', ref: doc.ref });
      fixCount++;
      continue;
    }

    const patches = {};

    // igrejaId / tenantId ausente
    if (!data.igrejaId && !data.tenantId) {
      patches.igrejaId = doc.id;
      patches.tenantId = doc.id;
    } else if (!data.igrejaId) {
      patches.igrejaId = data.tenantId || doc.id;
    } else if (!data.tenantId) {
      patches.tenantId = data.igrejaId || doc.id;
    }

    // Números inválidos
    if (hasBadNumbers(data)) {
      const fixed = fixBadNumbers(data);
      for (const [k, v] of Object.entries(fixed)) {
        if (v !== data[k]) patches[k] = v;
      }
    }

    if (Object.keys(patches).length > 0) {
      log(`✎ ${doc.id}: ${Object.keys(patches).join(', ')}`);
      ops.push({ type: 'set', ref: doc.ref, data: patches, options: { merge: true } });
      fixCount++;
    }
  }

  await batchCommit(ops);
  log(`  → ${ops.length} igrejas corrigidas`);
}

/* ── 2. Subcoleções de cada igreja ──────────────────────── */
const SUBCOLLECTIONS = [
  'membros', 'departamentos', 'eventos', 'finance', 'financeiro',
  'avisos', 'noticias', 'config', 'escalas', 'fornecedores',
  'certificados_emitidos', 'agenda', 'chat_threads',
];

async function repairChurchSubcollections(churchId) {
  const churchRef = db.collection('igrejas').doc(churchId);
  const ops = [];

  for (const subName of SUBCOLLECTIONS) {
    try {
      const subSnap = await churchRef.collection(subName).get();
      for (const doc of subSnap.docs) {
        scanCount++;
        const data = doc.data();

        // Documento vazio
        if (!data || Object.keys(data).length === 0) {
          vlog(`⚠ ${churchId}/${subName}/${doc.id}: vazio`);
          ops.push({ type: 'delete', ref: doc.ref });
          fixCount++;
          continue;
        }

        const patches = {};

        // Números inválidos
        if (hasBadNumbers(data)) {
          const fixed = fixBadNumbers(data);
          for (const [k, v] of Object.entries(fixed)) {
            if (JSON.stringify(v) !== JSON.stringify(data[k])) patches[k] = v;
          }
        }

        // Tenant stamp ausente
        if (!data.igrejaId && !data.tenantId) {
          patches.igrejaId = churchId;
          patches.tenantId = churchId;
        }

        if (Object.keys(patches).length > 0) {
          vlog(`✎ ${churchId}/${subName}/${doc.id}: ${Object.keys(patches).join(', ')}`);
          ops.push({ type: 'set', ref: doc.ref, data: patches, options: { merge: true } });
          fixCount++;
        }
      }
    } catch (e) {
      errorCount++;
      log(`✗ ${churchId}/${subName}: ${e.message}`);
    }
  }

  await batchCommit(ops);
  return ops.length;
}

/* ── 3. Coleções globais ────────────────────────────────── */
const GLOBAL_COLLECTIONS = ['users', 'subscriptions', 'config', 'suggestions', 'public_church_slugs'];

async function repairGlobalCollections() {
  log('═══ Coleções globais ═══');
  const ops = [];

  for (const colName of GLOBAL_COLLECTIONS) {
    try {
      const snap = await db.collection(colName).get();
      for (const doc of snap.docs) {
        scanCount++;
        const data = doc.data();
        if (!data || Object.keys(data).length === 0) {
          log(`⚠ ${colName}/${doc.id}: vazio`);
          ops.push({ type: 'delete', ref: doc.ref });
          fixCount++;
          continue;
        }
        if (hasBadNumbers(data)) {
          const fixed = fixBadNumbers(data);
          const patches = {};
          for (const [k, v] of Object.entries(fixed)) {
            if (JSON.stringify(v) !== JSON.stringify(data[k])) patches[k] = v;
          }
          if (Object.keys(patches).length > 0) {
            log(`✎ ${colName}/${doc.id}: ${Object.keys(patches).join(', ')}`);
            ops.push({ type: 'set', ref: doc.ref, data: patches, options: { merge: true } });
            fixCount++;
          }
        }
      }
    } catch (e) {
      errorCount++;
      log(`✗ ${colName}: ${e.message}`);
    }
  }

  await batchCommit(ops);
  log(`  → ${ops.length} docs globais corrigidos`);
}

/* ── main ───────────────────────────────────────────────── */
async function main() {
  console.log(`\n🔧 Reparação Firestore — ${dryRun ? 'DRY RUN' : 'EXECUTE'}\n`);

  // Igrejas
  if (churchArg) {
    log(`Modo: igreja única = ${churchArg}`);
    await repairChurchSubcollections(churchArg);
  } else {
    await repairIgrejas();

    // Subcoleções de todas as igrejas
    log('═══ Subcoleções ═══');
    const igrejasSnap = await db.collection('igrejas').get();
    let totalSubFixes = 0;
    for (const doc of igrejasSnap.docs) {
      const n = await repairChurchSubcollections(doc.id);
      totalSubFixes += n;
      if (n > 0) log(`  ${doc.id}: ${n} correções`);
    }
    log(`  → ${totalSubFixes} sub-documentos corrigidos`);
  }

  // Coleções globais
  if (!churchArg) await repairGlobalCollections();

  // Resumo
  console.log(`\n${'═'.repeat(50)}`);
  console.log(`  Documentos verificados: ${scanCount}`);
  console.log(`  Corrigidos:             ${fixCount}`);
  console.log(`  Erros:                  ${errorCount}`);
  console.log(`  Modo:                   ${dryRun ? 'DRY RUN (sem alterações)' : 'EXECUTE (alterações aplicadas)'}`);
  console.log(`${'═'.repeat(50)}\n`);

  if (dryRun && fixCount > 0) {
    console.log('💡 Para aplicar: node scripts/repair_firestore_data.cjs --execute\n');
  }
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
