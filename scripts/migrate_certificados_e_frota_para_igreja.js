/**
 * Migração one-shot (Admin SDK): move dados soltos na raiz para igrejas/{tenantId}/...
 *
 * Uso (na pasta functions ou com GOOGLE_APPLICATION_CREDENTIALS):
 *   node scripts/migrate_certificados_e_frota_para_igreja.js <tenantId>
 *
 * Exemplo:
 *   node scripts/migrate_certificados_e_frota_para_igreja.js igreja_o_brasil_para_cristo_jardim_goiano
 *
 * O que faz:
 * 1) certificados_emitidos/{id} → igrejas/{tenant}/certificados_emitidos/{id}
 *    + cria certificados_protocol_index/{id} { tenantId } se tiver tenantId no doc ou usar arg
 * 2) abastecimentos, combustiveis, veiculos (raiz) → subcoleções na mesma igreja
 *
 * Não apaga a raiz automaticamente (revise no Console e apague manualmente depois).
 */

const admin = require("firebase-admin");
const path = require("path");

const tenantId = process.argv[2];
if (!tenantId) {
  console.error("Uso: node migrate_certificados_e_frota_para_igreja.js <tenantId>");
  process.exit(1);
}

function initAdmin() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    return;
  }
  const sa = path.join(__dirname, "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  try {
    // eslint-disable-next-line import/no-dynamic-require, global-require
    admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
  } catch {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
}
initAdmin();

const db = admin.firestore();

async function migrateCollection(rootName, destCol) {
  const snap = await db.collection(rootName).get();
  let n = 0;
  for (const doc of snap.docs) {
    if (doc.id.startsWith("_init_")) continue;
    const ref = db.collection("igrejas").doc(tenantId).collection(destCol).doc(doc.id);
    await ref.set(doc.data(), { merge: true });
    n++;
  }
  console.log(`  ${rootName} → igrejas/${tenantId}/${destCol}: ${n} docs`);
}

async function migrateCertificadosRaiz() {
  const snap = await db.collection("certificados_emitidos").get();
  let n = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const tid = (data.tenantId || tenantId).toString().trim() || tenantId;
    const dest = db.collection("igrejas").doc(tid).collection("certificados_emitidos").doc(doc.id);
    await dest.set({ ...data, tenantId: tid }, { merge: true });
    await db.collection("certificados_protocol_index").doc(doc.id).set(
      { tenantId: tid, migratedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    n++;
  }
  console.log(`  certificados_emitidos (raiz) → igrejas/{tid}/certificados_emitidos + índice: ${n} docs`);
}

async function main() {
  console.log("Tenant:", tenantId);
  await migrateCertificadosRaiz();
  await migrateCollection("abastecimentos", "abastecimentos");
  await migrateCollection("combustiveis", "combustiveis");
  await migrateCollection("veiculos", "veiculos");
  console.log("Feito. Confira no Console e remova cópias na raiz quando estiver satisfeito.");
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
