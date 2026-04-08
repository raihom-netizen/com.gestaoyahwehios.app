/**
 * Apaga todos os documentos em igrejas/{igrejaId}/departamentos e recria os presets padrão.
 *
 * Uso (na pasta functions):
 *   node scripts/reset-departamentos-igreja.js
 *   node scripts/reset-departamentos-igreja.js --igreja=OUTRO_ID
 *   node scripts/reset-departamentos-igreja.js --dry-run
 *
 * Credenciais: GOOGLE_APPLICATION_CREDENTIALS ou gcloud auth application-default login
 *
 * Padrão --igreja: brasilparacristo_sistema (Igreja Brasil para Cristo / BPC).
 */

const admin = require("firebase-admin");
const PRESETS = require("./church_department_presets.js");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const args = process.argv.slice(2);
const igArg = args.find((a) => a.startsWith("--igreja="));
const igrejaId = igArg ? igArg.split("=")[1].trim() : "brasilparacristo_sistema";
const dryRun = args.includes("--dry-run");

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldPath = admin.firestore.FieldPath;

function dedupePresetsByLabel(rows) {
  const legacy = new Set(["kids", "men", "women", "welcome", "youth", "worship", "prayer"]);
  const byLabel = new Map();
  for (const e of rows) {
    const label = String(e.label || "")
      .trim()
      .toLowerCase();
    const key = e.key;
    const cur = byLabel.get(label);
    if (!cur) {
      byLabel.set(label, e);
      continue;
    }
    const curKey = cur.key;
    const curL = legacy.has(curKey);
    const newL = legacy.has(key);
    if (curL && !newL) byLabel.set(label, e);
    else if (curL === newL && !newL && key < curKey) byLabel.set(label, e);
  }
  return Array.from(byLabel.values()).sort((a, b) =>
    String(a.label).toLowerCase().localeCompare(String(b.label).toLowerCase()),
  );
}

async function deleteAllDepartamentos(igrejaId) {
  const col = db.collection("igrejas").doc(igrejaId).collection("departamentos");
  let deleted = 0;
  let last = null;
  for (;;) {
    let q = col.orderBy(FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    if (!dryRun) {
      const batch = db.batch();
      for (const d of snap.docs) {
        batch.delete(d.ref);
      }
      await batch.commit();
    }
    deleted += snap.size;
    last = snap.docs[snap.docs.length - 1];
    console.log(`  … removidos ${deleted} doc(s) até agora`);
    if (snap.size < 400) break;
  }
  return deleted;
}

async function seedPresets(igrejaId) {
  const col = db.collection("igrejas").doc(igrejaId).collection("departamentos");
  const list = dedupePresetsByLabel(PRESETS);
  const now = admin.firestore.Timestamp.now();
  const maxBatch = 450;
  let written = 0;
  for (let i = 0; i < list.length; i += maxBatch) {
    const chunk = list.slice(i, i + maxBatch);
    if (!dryRun) {
      const batch = db.batch();
      for (const e of chunk) {
        const visualKey = e.iconKey || e.key || "pastoral";
        const ref = col.doc(e.key);
        batch.set(ref, {
          name: e.label,
          description: e.description || "",
          iconKey: visualKey,
          themeKey: visualKey,
          bgColor1: e.c1,
          bgColor2: e.c2,
          bgImageUrl: "",
          leaderCpf: "",
          leaderUid: "",
          permissions: [],
          createdAt: now,
          updatedAt: now,
          active: true,
          isDefaultPreset: true,
        });
      }
      await batch.commit();
    }
    written += chunk.length;
    console.log(`  … gravados ${written} / ${list.length} preset(s)`);
  }
  return written;
}

async function resolveIgrejaId(preferred) {
  const tryIds = [preferred, "brasilparacristo_sistema", "brasilparacristo", "iobpc-jardim-goiano"];
  const seen = new Set();
  for (const id of tryIds) {
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const d = await db.collection("igrejas").doc(id).get();
    if (d.exists) return { id, snap: d };
  }
  const all = await db.collection("igrejas").get();
  const re = /brasil.*cristo|o\s+brasil\s+para\s+cristo/i;
  for (const d of all.docs) {
    const data = d.data() || {};
    const nome = `${data.nome || data.name || ""} ${data.slug || data.alias || ""}`;
    if (re.test(nome)) return { id: d.id, snap: d };
  }
  return null;
}

async function main() {
  console.log(`Projeto: ${projectId}`);
  console.log(`Igreja preferida: ${igrejaId}`);
  if (dryRun) console.log("(dry-run: não altera o Firestore)");

  const resolved = await resolveIgrejaId(igrejaId);
  if (!resolved) {
    console.error(
      "Nenhuma igreja encontrada (tentei ids comuns e nome contendo Brasil/Cristo). Passe --igreja=ID exato do Firestore.",
    );
    process.exit(1);
  }
  const effectiveId = resolved.id;
  const ig = resolved.snap;
  if (effectiveId !== igrejaId) {
    console.log(`Resolvido para igrejas/${effectiveId} (doc preferido não existia).`);
  }
  const nome = (ig.data() && (ig.data().nome || ig.data().name)) || "";
  console.log(`Nome cadastro: ${nome || "(sem nome)"}`);

  console.log("\n1) Apagando departamentos existentes…");
  const del = await deleteAllDepartamentos(effectiveId);
  console.log(`   Total removido: ${del}`);

  console.log("\n2) Inserindo lista padrão (dedupe por nome)…");
  const n = await seedPresets(effectiveId);
  console.log(`   Total inserido: ${n}`);

  console.log(
    "\nNota: vínculos antigos em membros.DEPARTAMENTOS podem apontar para IDs que não existem mais — revise no painel se necessário.",
  );
  console.log("\nConcluído.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
