/**
 * Migração one-shot (Admin SDK): pontes Mercado Pago e índice de protocolo de certificados
 * da raiz para `igrejas/{tenantId}/...`.
 *
 * Uso (na pasta functions, onde firebase-admin está instalado):
 *   node tools/migrate_mp_bridges_para_igrejas.cjs
 *
 * Credenciais: GOOGLE_APPLICATION_CREDENTIALS ou secrets/gestaoyahweh-21e23-*.json na raiz do repo.
 *
 * O que faz:
 * 1) church_mp_payments/{id} → igrejas/{tenantId}/mp_payment_bridge/{id}
 * 2) church_mp_preferences/{id} → igrejas/{tenantId}/mp_preference_bridge/{id}
 * 3) certificados_protocol_index/{id} (raiz) → igrejas/{tenantId}/certificados_protocol_index/{id}
 *
 * Não apaga documentos na raiz (apague manualmente no Console após validar webhooks e QR).
 */

const admin = require("firebase-admin");
const path = require("path");

function initAdmin() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    return;
  }
  const sa = path.join(__dirname, "..", "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  try {
    admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
  } catch {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
}
initAdmin();

const db = admin.firestore();

async function migrateChurchMpPayments() {
  const snap = await db.collection("church_mp_payments").get();
  let n = 0;
  let skipped = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const tid = String(data.tenantId || "").trim();
    if (!tid) {
      skipped++;
      console.warn("  [church_mp_payments] sem tenantId:", doc.id);
      continue;
    }
    const dest = db.collection("igrejas").doc(tid).collection("mp_payment_bridge").doc(doc.id);
    const payload = {
      createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    };
    if (data.amount != null) payload.amount = data.amount;
    await dest.set(payload, { merge: true });
    n++;
  }
  console.log(`church_mp_payments → igrejas/.../mp_payment_bridge: ${n} docs (ignorados: ${skipped})`);
}

async function migrateChurchMpPreferences() {
  const snap = await db.collection("church_mp_preferences").get();
  let n = 0;
  let skipped = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const tid = String(data.tenantId || "").trim();
    if (!tid) {
      skipped++;
      console.warn("  [church_mp_preferences] sem tenantId:", doc.id);
      continue;
    }
    const dest = db.collection("igrejas").doc(tid).collection("mp_preference_bridge").doc(doc.id);
    const { tenantId: _t, ...rest } = data;
    await dest.set(
      {
        ...rest,
        createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    n++;
  }
  console.log(`church_mp_preferences → igrejas/.../mp_preference_bridge: ${n} docs (ignorados: ${skipped})`);
}

async function migrateCertificadosProtocolIndexRoot() {
  const snap = await db.collection("certificados_protocol_index").get();
  let n = 0;
  let skipped = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const tid = String(data.tenantId || "").trim();
    if (!tid) {
      skipped++;
      console.warn("  [certificados_protocol_index] sem tenantId:", doc.id);
      continue;
    }
    const dest = db
      .collection("igrejas")
      .doc(tid)
      .collection("certificados_protocol_index")
      .doc(doc.id);
    await dest.set(
      {
        createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    n++;
  }
  console.log(
    `certificados_protocol_index (raiz) → igrejas/.../certificados_protocol_index: ${n} docs (ignorados: ${skipped})`
  );
}

async function main() {
  console.log("Migrando pontes MP e índice de certificados para igrejas/{tenantId}/...");
  await migrateChurchMpPayments();
  await migrateChurchMpPreferences();
  await migrateCertificadosProtocolIndexRoot();
  console.log("Feito. Teste webhooks/QR antes de apagar cópias na raiz.");
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
