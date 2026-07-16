/**
 * Apaga igrejas de teste por completo (raiz + subcoleções + Storage + slugs + subscriptions).
 *
 * Uso (raiz):
 *   node scripts/purge_forbidden_test_churches.cjs
 *   node scripts/purge_forbidden_test_churches.cjs --dry-run
 *   node scripts/purge_forbidden_test_churches.cjs --ids=igreja_de_teste,teste_apple
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const idsArg = args.find((a) => a.startsWith('--ids='));

const DEFAULT_IDS = [
  'igreja_de_teste',
  'igreja_de_teste_1',
  'igreja_de_teste_2',
  'igreja_de_teste_3',
  'teste_apple',
];

function findSa() {
  const env = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (env && fs.existsSync(env)) return env;
  for (const dir of [
    path.join(root, 'ANDROID'),
    path.join(root, 'secrets'),
    root,
  ]) {
    if (!fs.existsSync(dir)) continue;
    const hit = fs
      .readdirSync(dir)
      .find((f) => /firebase-adminsdk.*\.json$/i.test(f));
    if (hit) return path.join(dir, hit);
  }
  return null;
}

async function deleteQueryBatch(db, query, batchSize = 400) {
  const snap = await query.limit(batchSize).get();
  if (snap.empty) return 0;
  if (dryRun) return snap.size;
  const batch = db.batch();
  for (const doc of snap.docs) batch.delete(doc.ref);
  await batch.commit();
  return snap.size;
}

async function deleteCollectionRecursive(db, colRef, depth = 0) {
  let total = 0;
  // Subcoleções de cada doc
  while (true) {
    const snap = await colRef.limit(100).get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const subcols = await doc.ref.listCollections();
      for (const sub of subcols) {
        total += await deleteCollectionRecursive(db, sub, depth + 1);
      }
      if (!dryRun) await doc.ref.delete();
      total += 1;
    }
    if (dryRun) break; // dry: conta 1 página
  }
  return total;
}

async function deleteStoragePrefix(bucket, prefix) {
  let deleted = 0;
  let pageToken;
  do {
    const [files, , apiResp] = await bucket.getFiles({
      prefix,
      maxResults: 200,
      pageToken,
    });
    pageToken = apiResp && apiResp.nextPageToken;
    if (!files.length) break;
    if (dryRun) {
      deleted += files.length;
      break;
    }
    await Promise.all(
      files.map((f) =>
        f.delete().catch((e) => {
          console.warn('  storage skip', f.name, e.message);
        }),
      ),
    );
    deleted += files.length;
  } while (pageToken);
  return deleted;
}

async function purgeOne(db, bucket, churchId) {
  console.log(`\n=== purge ${churchId} ===`);
  const ref = db.collection('igrejas').doc(churchId);
  const snap = await ref.get();
  const listed = await db.collection('igrejas').listDocuments();
  const ghost = listed.some((r) => r.id === churchId);
  if (!snap.exists && !ghost) {
    console.log('  (não existe)');
    return { churchId, docs: 0, storage: 0, skipped: true };
  }

  let docs = 0;
  const cols = await ref.listCollections();
  for (const col of cols) {
    const n = await deleteCollectionRecursive(db, col);
    docs += n;
    console.log(`  sub ${col.id}: ${n}`);
  }
  if (snap.exists || ghost) {
    if (!dryRun) {
      try {
        await ref.delete();
      } catch (_) {}
    }
    docs += 1;
    console.log('  root: deleted');
  }

  // slugs públicos
  try {
    const slugSnap = await db
      .collection('public_church_slugs')
      .where('churchId', '==', churchId)
      .get();
    if (!dryRun) {
      const batch = db.batch();
      for (const d of slugSnap.docs) batch.delete(d.ref);
      if (!slugSnap.empty) await batch.commit();
    }
    // também doc id = churchId
    const byId = await db.collection('public_church_slugs').doc(churchId).get();
    if (byId.exists && !dryRun) await byId.ref.delete();
    console.log(`  public_church_slugs: ${slugSnap.size + (byId.exists ? 1 : 0)}`);
  } catch (e) {
    console.warn('  slugs:', e.message);
  }

  // subscriptions
  try {
    let n = 0;
    for (const field of ['igrejaId', 'tenantId', 'churchId']) {
      n += await deleteQueryBatch(
        db,
        db.collection('subscriptions').where(field, '==', churchId),
      );
    }
    console.log(`  subscriptions: ${n}`);
  } catch (e) {
    console.warn('  subscriptions:', e.message);
  }

  // Storage
  let storage = 0;
  try {
    storage += await deleteStoragePrefix(bucket, `igrejas/${churchId}/`);
    storage += await deleteStoragePrefix(bucket, `tenants/${churchId}/`);
    console.log(`  storage files: ${storage}`);
  } catch (e) {
    console.warn('  storage:', e.message);
  }

  return { churchId, docs, storage, skipped: false };
}

async function main() {
  const sa = findSa();
  if (!sa) {
    console.error('Service account não encontrada (ANDROID/*-firebase-adminsdk*.json).');
    process.exit(1);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = sa;
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'gestaoyahweh-21e23',
    storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
  });
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const ids = idsArg
    ? idsArg
        .split('=')[1]
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
    : DEFAULT_IDS;

  console.log(
    `Purge igrejas teste (${ids.length})${dryRun ? ' [DRY-RUN]' : ''} SA=${path.basename(sa)}`,
  );

  const results = [];
  for (const id of ids) {
    results.push(await purgeOne(db, bucket, id));
  }

  console.log('\n=== RESUMO ===');
  for (const r of results) {
    console.log(
      `  ${r.churchId}: docs~${r.docs} storage~${r.storage}${r.skipped ? ' (skip)' : ''}`,
    );
  }
  console.log(dryRun ? 'DRY-RUN — nada apagado.' : 'OK — purge concluído.');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
