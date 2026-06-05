/**
 * Migra documentos legados `pendingUploads/{tenantId}__{uploadId}` (raiz)
 * para `igrejas/{tenantId}/pending_uploads/{uploadId}` e apaga a raiz.
 *
 * PowerShell (raiz do repo, credencial Admin SDK):
 *   node scripts/migrate_root_pending_uploads_to_igrejas.mjs
 *   node scripts/migrate_root_pending_uploads_to_igrejas.mjs --delete-only
 */

import admin from 'firebase-admin';
import path from 'path';
import fs from 'fs';

const deleteOnly = process.argv.includes('--delete-only');
const BATCH = 200;

function initAdmin() {
  if (admin.apps.length) return;
  const baseDir = process.cwd();
  const keyPaths = [
    path.join(baseDir, 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
    path.join(baseDir, '..', 'secrets', 'gestaoyahweh-21e23-7951f1817911.json'),
  ];
  const keyPath = keyPaths.find((p) => fs.existsSync(p));
  if (!keyPath) {
    throw new Error(
      'Service account não encontrada em secrets/. Use GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }
  admin.initializeApp({
    credential: admin.credential.cert(JSON.parse(fs.readFileSync(keyPath, 'utf8'))),
  });
}

function parseLegacyDoc(id, data) {
  const tenantFromField = (data.tenantId ?? '').toString().trim();
  if (tenantFromField) {
    const uploadId =
      (data.tenantUploadId ?? '').toString().trim() ||
      id.replace(`${tenantFromField}__`, '');
    return { tenantId: tenantFromField, uploadId: uploadId || id };
  }
  const sep = id.indexOf('__');
  if (sep > 0) {
    return {
      tenantId: id.slice(0, sep),
      uploadId: id.slice(sep + 2),
    };
  }
  return null;
}

async function run() {
  initAdmin();
  const db = admin.firestore();
  let migrated = 0;
  let deleted = 0;
  let skipped = 0;

  let snap = await db.collection('pendingUploads').limit(BATCH).get();
  while (!snap.empty) {
    const batch = db.batch();
    let ops = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      const parsed = parseLegacyDoc(doc.id, data);
      if (!deleteOnly && parsed?.tenantId && parsed.uploadId) {
        const dest = db
          .collection('igrejas')
          .doc(parsed.tenantId)
          .collection('pending_uploads')
          .doc(parsed.uploadId);
        const existing = await dest.get();
        if (!existing.exists) {
          const payload = { ...data };
          delete payload.globalKey;
          payload.tenantId = parsed.tenantId;
          payload.id = parsed.uploadId;
          batch.set(dest, payload, { merge: true });
          migrated++;
          ops++;
        } else {
          skipped++;
        }
      }
      batch.delete(doc.ref);
      deleted++;
      ops++;
    }
    if (ops > 0) await batch.commit();
    snap = await db.collection('pendingUploads').limit(BATCH).get();
  }

  console.log(
    JSON.stringify(
      { migrated, deleted, skipped, deleteOnly },
      null,
      2,
    ),
  );
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
