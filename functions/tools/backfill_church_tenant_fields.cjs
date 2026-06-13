/**
 * Backfill churchId + tenantId em todos os documentos de igrejas/{id}/**
 *
 * Uso:
 *   node functions/tools/backfill_church_tenant_fields.cjs
 *   node functions/tools/backfill_church_tenant_fields.cjs igreja_o_brasil_para_cristo_jardim_goiano
 */
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

function loadCredential() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return admin.credential.applicationDefault();
  }
  const secretsPath = path.resolve(
    __dirname,
    "..",
    "..",
    "secrets",
    "gestaoyahweh-21e23-7951f1817911.json",
  );
  if (fs.existsSync(secretsPath)) {
    return admin.credential.cert(require(secretsPath));
  }
  const androidGlob = path.resolve(__dirname, "..", "..", "ANDROID");
  if (fs.existsSync(androidGlob)) {
    const files = fs
      .readdirSync(androidGlob)
      .filter((f) => f.includes("firebase-adminsdk") && f.endsWith(".json"));
    if (files.length) {
      return admin.credential.cert(
        require(path.join(androidGlob, files[0])),
      );
    }
  }
  return admin.credential.applicationDefault();
}

admin.initializeApp({ credential: loadCredential() });

const { backfillChurchTenantFieldsForChurch } = require("../lib/churchTenantFieldsBackfill");

const db = admin.firestore();
const one = String(process.argv[2] || "").trim();

(async () => {
  if (one) {
    const stats = await backfillChurchTenantFieldsForChurch(db, one, {
      maxDocs: 25000,
    });
    console.log(JSON.stringify(stats, null, 2));
    process.exit(stats.errors > 0 ? 1 : 0);
  }

  const refs = await db.collection("igrejas").listDocuments();
  const allStats = [];
  for (const ref of refs) {
    console.log(`Backfill igrejas/${ref.id} …`);
    const stats = await backfillChurchTenantFieldsForChurch(db, ref.id, {
      maxDocs: 25000,
    });
    allStats.push(stats);
    console.log(
      `  stamped=${stats.docsStamped} skipped=${stats.docsSkipped} scanned=${stats.docsScanned}`,
    );
  }
  const totalStamped = allStats.reduce((n, s) => n + s.docsStamped, 0);
  console.log(`Concluído. Igrejas=${allStats.length} docsStamped=${totalStamped}`);
  process.exit(0);
})().catch((e) => {
  console.error("ERRO:", e);
  process.exit(1);
});
