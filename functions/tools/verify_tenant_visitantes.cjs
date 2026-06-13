/**
 * Verifica docs canónicos BPC: visitantes + tenant fields
 */
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

function loadCredential() {
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

const CHURCH = "igreja_o_brasil_para_cristo_jardim_goiano";

(async () => {
  const churchRef = db.collection("igrejas").doc(CHURCH);
  const root = await churchRef.get();
  const mod = await churchRef.collection("_tenant_modules").doc("visitantes").get();
  const schema = await churchRef.collection("visitantes").doc("_schema").get();

  const checks = [];
  const rootData = root.data() || {};
  checks.push({
    path: `igrejas/${CHURCH}`,
    ok: root.exists && rootData.churchId === CHURCH && rootData.tenantId === CHURCH,
    churchId: rootData.churchId,
    tenantId: rootData.tenantId,
  });

  const modData = mod.data() || {};
  checks.push({
    path: `_tenant_modules/visitantes`,
    ok: mod.exists && modData.churchId === CHURCH && modData.tenantId === CHURCH && modData.enabled === true,
    firestorePath: modData.firestorePath,
  });

  const schemaData = schema.data() || {};
  checks.push({
    path: `visitantes/_schema`,
    ok: schema.exists && schemaData.churchId === CHURCH && schemaData.tenantId === CHURCH,
    firestorePath: schemaData.firestorePath,
  });

  const sampleCols = ["membros", "departamentos", "cargos", "finance", "visitantes"];
  for (const col of sampleCols) {
    const snap = await churchRef.collection(col).limit(3).get();
    let stamped = 0;
    let total = 0;
    for (const d of snap.docs) {
      if (d.id === "_schema") continue;
      total++;
      const data = d.data() || {};
      if (data.churchId === CHURCH && data.tenantId === CHURCH) stamped++;
    }
    checks.push({
      path: `${col} (amostra ${total})`,
      ok: total === 0 || stamped === total,
      stamped,
      total,
    });
  }

  const allOk = checks.every((c) => c.ok);
  console.log(JSON.stringify({ churchId: CHURCH, allOk, checks }, null, 2));
  process.exit(allOk ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
