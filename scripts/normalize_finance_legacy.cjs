// Normaliza lançamentos antigos de `igrejas/{id}/finance`.
//
// Doações do Mercado Pago e receitas recorrentes eram gravadas só em português
// (`tipo: "entrada"`, `descricao`, `categoria`) e, no caso das recorrentes, sem
// campo de data. O módulo Financeiro consulta o período por `date`/
// `effectiveDate`/`paidAt` e compara `type` com "income"/"expense" — por isso
// esses valores existiam no banco mas não apareciam na tela (ou eram somados
// como despesa). A gravação já foi corrigida na origem; este script conserta o
// que ficou para trás.
//
// Uso:
//   node scripts/normalize_finance_legacy.cjs --dry-run            (todas as igrejas)
//   node scripts/normalize_finance_legacy.cjs --tenant=<churchId>
//   node scripts/normalize_finance_legacy.cjs                      (aplica)
//
// Requer `functions/lib/financeLegacyNormalize.js` (rode `npm run build` em
// functions/) — a lógica do patch é a MESMA da Cloud Function, sem cópia.
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const KEY = process.env.YAHWEH_ADMIN_KEY
  || path.join(__dirname, '..', 'ANDROID', 'gestaoyahweh-21e23-firebase-adminsdk-fbsvc-089c87187f.json');

let buildFinanceNormalizationPatch;
try {
  ({ buildFinanceNormalizationPatch } = require(
    path.join(__dirname, '..', 'functions', 'lib', 'financeLegacyNormalize.js'),
  ));
} catch (e) {
  console.error('Falta functions/lib/financeLegacyNormalize.js — rode `npm run build` em functions/.');
  console.error(e.message);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(KEY)) });
const db = admin.firestore();

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const tenantArg = (args.find((a) => a.startsWith('--tenant=')) || '').split('=')[1] || '';

async function normalizeTenant(tenantId) {
  const col = db.collection('igrejas').doc(tenantId).collection('finance');
  let cursor = null;
  let scanned = 0;
  let updated = 0;
  for (;;) {
    let q = col.orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    scanned += snap.docs.length;
    let batch = db.batch();
    let pending = 0;
    for (const doc of snap.docs) {
      const patch = buildFinanceNormalizationPatch(doc.data() || {});
      if (Object.keys(patch).length === 0) continue;
      updated++;
      if (dryRun) continue;
      batch.set(doc.ref, patch, { merge: true });
      pending++;
      if (pending >= 400) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (!dryRun && pending > 0) await batch.commit();
    cursor = snap.docs[snap.docs.length - 1].id;
    if (snap.docs.length < 500) break;
  }
  return { scanned, updated };
}

(async () => {
  const tenants = [];
  if (tenantArg) {
    tenants.push(tenantArg);
  } else {
    const igrejas = await db.collection('igrejas').get();
    for (const d of igrejas.docs) tenants.push(d.id);
  }
  console.log(`${dryRun ? '[DRY-RUN] ' : ''}igrejas: ${tenants.length}`);
  let totalScanned = 0;
  let totalUpdated = 0;
  for (const tid of tenants) {
    try {
      const r = await normalizeTenant(tid);
      totalScanned += r.scanned;
      totalUpdated += r.updated;
      if (r.updated > 0 || r.scanned > 0) {
        console.log(`  ${tid}: ${r.updated}/${r.scanned} lançamentos ajustados`);
      }
    } catch (e) {
      console.warn(`  ${tid}: ERRO — ${e.message}`);
    }
  }
  console.log(`${dryRun ? '[DRY-RUN] ' : ''}TOTAL: ${totalUpdated}/${totalScanned} lançamentos ajustados`);
  process.exit(0);
})();
