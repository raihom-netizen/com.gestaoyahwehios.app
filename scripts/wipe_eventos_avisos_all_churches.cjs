/**
 * ZERAR eventos e avisos de TODAS as igrejas (Firestore).
 *
 * Apaga, em cada `igrejas/{churchId}`, TODOS os documentos das subcoleções:
 *   - eventos    (canónica de eventos → módulo Eventos + painel inicial + site público)
 *   - noticias   (legado de eventos)
 *   - events     (legado en de eventos)
 *   - avisos     (módulo Avisos + painel inicial + site público)
 * Recursivo: também apaga subcoleções dos docs (reações/comentários/anexos meta).
 *
 * NÃO toca em: membros, finance, patrimonio, escalas, agenda, config, etc.
 * Storage (mídias) NÃO é apagado aqui — só os documentos Firestore.
 *
 * Uso (raiz do repo):
 *   node scripts/wipe_eventos_avisos_all_churches.cjs            # DRY-RUN (só conta)
 *   node scripts/wipe_eventos_avisos_all_churches.cjs --execute  # APAGA de verdade
 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const admin = (() => {
  try {
    return require(path.join(root, 'scripts', 'node_modules', 'firebase-admin'));
  } catch (_) {
    try {
      return require(path.join(root, 'functions', 'node_modules', 'firebase-admin'));
    } catch (_) {
      return require('firebase-admin');
    }
  }
})();

const args = process.argv.slice(2);
const dryRun = !args.includes('--execute');

/** Subcoleções de eventos/avisos a zerar (por igreja). */
const WIPE_COLLECTIONS = ['eventos', 'noticias', 'events', 'avisos'];

function findSa() {
  const env = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (env && fs.existsSync(env)) return env;
  for (const dir of [path.join(root, 'ANDROID'), path.join(root, 'secrets'), root]) {
    if (!fs.existsSync(dir)) continue;
    const hit = fs.readdirSync(dir).find((f) => /firebase-adminsdk.*\.json$/i.test(f));
    if (hit) return path.join(dir, hit);
  }
  return null;
}

async function deleteCollectionRecursive(colRef) {
  let total = 0;
  while (true) {
    const snap = await colRef.limit(100).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const subcols = await doc.ref.listCollections();
      for (const sub of subcols) {
        total += await deleteCollectionRecursive(sub);
      }
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break; // dry-run: só amostra o 1.º lote (não percorre tudo)
  }
  return total;
}

async function main() {
  const sa = findSa();
  if (!sa) {
    console.error('Service account não encontrada (ANDROID/*-firebase-adminsdk*.json).');
    process.exit(1);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = sa;
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
    });
  }
  const db = admin.firestore();

  console.log('=== ZERAR eventos + avisos — TODAS as igrejas ===');
  console.log(`Modo: ${dryRun ? 'DRY-RUN (use --execute para apagar)' : 'EXECUTE (apaga de verdade)'}`);
  console.log(`Coleções: ${WIPE_COLLECTIONS.join(', ')}`);
  console.log(`SA: ${sa}\n`);

  const churches = await db.collection('igrejas').listDocuments();
  console.log(`Igrejas encontradas: ${churches.length}\n`);

  let grandTotal = 0;
  const perChurch = [];
  for (const churchRef of churches) {
    let churchTotal = 0;
    const detail = [];
    for (const name of WIPE_COLLECTIONS) {
      const n = await deleteCollectionRecursive(churchRef.collection(name));
      if (n > 0) detail.push(`${name}=${n}`);
      churchTotal += n;
    }
    grandTotal += churchTotal;
    if (churchTotal > 0) {
      console.log(`  [${dryRun ? 'dry' : 'del'}] igrejas/${churchRef.id}: ${detail.join(', ')} (total ${churchTotal})`);
      perChurch.push({ id: churchRef.id, total: churchTotal });
    }
  }

  console.log(`\n${dryRun ? 'DRY-RUN' : 'APAGADO'} — docs ${dryRun ? 'amostrados' : 'removidos'}: ${grandTotal}`);
  console.log(`Igrejas afetadas: ${perChurch.length}/${churches.length}`);
  if (dryRun) {
    console.log('\n(No dry-run só o 1.º lote de cada coleção é contado. Reexecute com --execute para apagar TUDO.)');
  } else {
    console.log('\nConcluído. Painel inicial, site público, Eventos e Avisos zerados em todas as igrejas.');
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
