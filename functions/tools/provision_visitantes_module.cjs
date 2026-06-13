/**
 * Provisiona módulo Visitantes: _tenant_modules/visitantes + visitantes/_schema
 *
 * Uso:
 *   node functions/tools/provision_visitantes_module.cjs
 *   node functions/tools/provision_visitantes_module.cjs igreja_o_brasil_para_cristo_jardim_goiano
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
  const androidDir = path.resolve(__dirname, "..", "..", "ANDROID");
  if (fs.existsSync(androidDir)) {
    const sa = fs
      .readdirSync(androidDir)
      .find((f) => f.includes("firebase-adminsdk") && f.endsWith(".json"));
    if (sa) {
      return admin.credential.cert(require(path.join(androidDir, sa)));
    }
  }
  return admin.credential.applicationDefault();
}

admin.initializeApp({ credential: loadCredential() });

const db = admin.firestore();
const one = String(process.argv[2] || "").trim();

function stamp(churchId, data) {
  const id = String(churchId || "").trim();
  return { ...data, churchId: id, tenantId: id };
}

async function provisionVisitantesForChurch(churchId) {
  const id = String(churchId || "").trim();
  if (!id) return { churchId: "", module: false, schema: false, skipped: true };

  const churchRef = db.collection("igrejas").doc(id);
  const churchSnap = await churchRef.get();
  if (!churchSnap.exists) {
    console.warn(`  SKIP igrejas/${id} — doc raiz inexistente`);
    return { churchId: id, module: false, schema: false, skipped: true };
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  let moduleCreated = false;
  let schemaCreated = false;

  const modRef = churchRef.collection("_tenant_modules").doc("visitantes");
  const modSnap = await modRef.get();
  await modRef.set(
    stamp(id, {
      enabled: true,
      module: "visitantes",
      collection: "visitantes",
      firestorePath: `igrejas/${id}/visitantes`,
      storagePath: "",
      followupsSubcollection: "followups",
      schemaVersion: 1,
      isWelcomeKit: true,
      provisionedAt: now,
      tenantFieldsStampedAt: now,
    }),
    { merge: true },
  );
  moduleCreated = !modSnap.exists;

  const schemaRef = churchRef.collection("visitantes").doc("_schema");
  const schemaSnap = await schemaRef.get();
  await schemaRef.set(
    stamp(id, {
      schemaVersion: 1,
      firestorePath: `igrejas/${id}/visitantes`,
      followupsSubcollection: "followups",
      isWelcomeKit: true,
      provisionedAt: now,
      tenantFieldsStampedAt: now,
    }),
    { merge: true },
  );
  schemaCreated = !schemaSnap.exists;

  return { churchId: id, module: moduleCreated, schema: schemaCreated, skipped: false };
}

(async () => {
  const targets = one
    ? [one]
    : (await db.collection("igrejas").listDocuments()).map((r) => r.id);

  const results = [];
  for (const id of targets) {
    console.log(`Provisionando visitantes em igrejas/${id} …`);
    const r = await provisionVisitantesForChurch(id);
    results.push(r);
    console.log(
      `  module=${r.module ? "criado" : "merge"} schema=${r.schema ? "criado" : "merge"} skipped=${r.skipped}`,
    );
  }

  const created = results.filter((r) => r.module || r.schema).length;
  console.log(
    JSON.stringify(
      { ok: true, churches: results.length, withNewDocs: created, results },
      null,
      2,
    ),
  );
  process.exit(0);
})().catch((e) => {
  console.error("ERRO:", e);
  process.exit(1);
});
