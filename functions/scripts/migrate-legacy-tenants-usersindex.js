/**
 * Migração única: copia tenants/{churchId}/usersIndex → igrejas/{churchId}/usersIndex
 * e remove os docs legados em tenants/ (não cria mais nada em tenants/).
 *
 * Uso (na pasta functions, com credencial SA):
 *   node scripts/migrate-legacy-tenants-usersindex.js
 */
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

function loadCredential() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return admin.credential.applicationDefault();
  }
  const secretsPath = path.resolve(__dirname, "..", "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  if (fs.existsSync(secretsPath)) {
    return admin.credential.cert(require(secretsPath));
  }
  return admin.credential.applicationDefault();
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: loadCredential() });
}
const db = admin.firestore();

async function migrateChurch(churchId) {
  const legacyCol = db.collection("tenants").doc(churchId).collection("usersIndex");
  const snap = await legacyCol.get();
  if (snap.empty) return 0;

  let copied = 0;
  const batchSize = 400;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snap.docs) {
    const target = db.collection("igrejas").doc(churchId).collection("usersIndex").doc(doc.id);
    batch.set(target, doc.data(), { merge: true });
    batch.delete(doc.ref);
    ops += 2;
    copied += 1;
    if (ops >= batchSize) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  return copied;
}

(async () => {
  const tenantsSnap = await db.collection("tenants").get();
  let total = 0;
  for (const t of tenantsSnap.docs) {
    const n = await migrateChurch(t.id);
    if (n > 0) console.log(`${t.id}: ${n} usersIndex migrados para igrejas/`);
    total += n;
  }
  console.log(`Concluído. Total migrado: ${total}`);
  process.exit(0);
})().catch((e) => {
  console.error("ERRO:", e);
  process.exit(1);
});
