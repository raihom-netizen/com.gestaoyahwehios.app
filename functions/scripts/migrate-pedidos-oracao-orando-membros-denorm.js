/**
 * Migração em lote — preenche `orandoMembros` a partir de `orandoUids`
 * em `igrejas/{churchId}/pedidosOracao`.
 *
 * Resolve nome/foto via authUid em `membros` (Members Directory).
 *
 * Uso (pasta `functions/`):
 *   node scripts/migrate-pedidos-oracao-orando-membros-denorm.js --dry-run
 *   node scripts/migrate-pedidos-oracao-orando-membros-denorm.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
 *   node scripts/migrate-pedidos-oracao-orando-membros-denorm.js --force
 *
 * Credenciais: GOOGLE_APPLICATION_CREDENTIALS ou gcloud auth application-default login
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const args = process.argv.slice(2);
function arg(name) {
  const hit = args.find((a) => a.startsWith(`${name}=`));
  return hit ? hit.split("=").slice(1).join("=").trim() : "";
}

const onlyIgreja = arg("--igreja");
const dryRun = args.includes("--dry-run");
const force = args.includes("--force");

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

function memberDisplayName(data) {
  for (const k of ["NOME_COMPLETO", "nome", "name", "displayName"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "Membro";
}

function memberPhotoUrl(data) {
  for (const k of [
    "fotoThumbUrl",
    "fotoUrl",
    "photoUrl",
    "FOTO_URL",
    "foto",
    "imageUrl",
  ]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
}

function authUidFromMember(data) {
  for (const k of ["authUid", "firebaseUid", "uid", "UID"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
}

async function buildAuthUidIndex(churchId) {
  const snap = await db.collection("igrejas").doc(churchId).collection("membros").get();
  const index = {};
  for (const doc of snap.docs) {
    const data = doc.data();
    const uid = authUidFromMember(data);
    if (!uid) continue;
    index[uid] = {
      nome: memberDisplayName(data),
      fotoUrl: memberPhotoUrl(data),
    };
  }
  return index;
}

function parseOrandoMembros(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const uid = String(item.uid ?? "").trim();
    if (!uid) continue;
    out.push({
      uid,
      nome: String(item.nome ?? item.name ?? "Membro").trim() || "Membro",
      fotoUrl: String(item.fotoUrl ?? item.photoUrl ?? "").trim(),
    });
  }
  return out;
}

function uidsFromMembros(membros) {
  return membros.map((m) => m.uid).filter(Boolean);
}

function rebuildOrandoMembros(orandoUids, existingMembros, authIndex) {
  const uidSet = Array.isArray(orandoUids)
    ? [...new Set(orandoUids.map((u) => String(u ?? "").trim()).filter(Boolean))]
    : [];
  if (uidSet.length === 0) return [];

  const byUid = {};
  for (const m of existingMembros) {
    byUid[m.uid] = m;
  }

  return uidSet.map((uid) => {
    const prev = byUid[uid];
    const hit = authIndex[uid];
    const nome =
      (prev && prev.nome && prev.nome !== "Membro" ? prev.nome : "") ||
      (hit && hit.nome) ||
      "Membro";
    const fotoUrl = (prev && prev.fotoUrl) || (hit && hit.fotoUrl) || "";
    return { uid, nome, fotoUrl };
  });
}

function needsMigration(orandoUids, orandoMembros) {
  const uids = Array.isArray(orandoUids)
    ? orandoUids.map((u) => String(u ?? "").trim()).filter(Boolean)
    : [];
  if (uids.length === 0) return false;
  if (force) return true;
  const membros = parseOrandoMembros(orandoMembros);
  if (membros.length === 0) return true;
  const mUids = new Set(uidsFromMembros(membros));
  for (const u of uids) {
    if (!mUids.has(u)) return true;
  }
  if (membros.length !== uids.length) return true;
  return false;
}

async function migrateChurch(churchId) {
  console.log(`\n=== Igreja: ${churchId} ===`);
  const authIndex = await buildAuthUidIndex(churchId);
  console.log(`  Índice membros (authUid): ${Object.keys(authIndex).length}`);

  const pedidosSnap = await db
    .collection("igrejas")
    .doc(churchId)
    .collection("pedidosOracao")
    .get();

  let scanned = 0;
  let updated = 0;
  let skipped = 0;
  const batchSize = 400;
  let batch = db.batch();
  let batchCount = 0;

  async function flushBatch() {
    if (batchCount === 0) return;
    if (!dryRun) await batch.commit();
    batch = db.batch();
    batchCount = 0;
  }

  for (const doc of pedidosSnap.docs) {
    scanned++;
    const data = doc.data();
    const orandoUids = data.orandoUids;
    const orandoMembros = data.orandoMembros;
    if (!needsMigration(orandoUids, orandoMembros)) {
      skipped++;
      continue;
    }

    const rebuilt = rebuildOrandoMembros(
      orandoUids,
      parseOrandoMembros(orandoMembros),
      authIndex
    );
    const uids = rebuilt.map((m) => m.uid);

    console.log(
      `  [${dryRun ? "DRY" : "UPD"}] ${doc.id} — orandoUids=${uids.length} orandoMembros=${rebuilt.length}`
    );

    if (!dryRun) {
      batch.update(doc.ref, {
        orandoMembros: rebuilt,
        orandoUids: uids,
        orandoCount: rebuilt.length,
        orandoMembrosDenormMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      batchCount++;
      if (batchCount >= batchSize) {
        await flushBatch();
      }
    }
    updated++;
  }

  await flushBatch();
  console.log(
    `  Resumo: ${scanned} lidos, ${updated} ${dryRun ? "simulados" : "gravados"}, ${skipped} ok`
  );
  return { scanned, updated, skipped };
}

async function main() {
  console.log(`Projeto: ${projectId}`);
  console.log(`Modo: ${dryRun ? "DRY-RUN" : "GRAVAÇÃO"}${force ? " (force)" : ""}`);

  let churchIds = [];
  if (onlyIgreja) {
    churchIds = [onlyIgreja.trim()];
  } else {
    const igrejasSnap = await db.collection("igrejas").select().get();
    churchIds = igrejasSnap.docs.map((d) => d.id);
  }

  let totalUpdated = 0;
  for (const id of churchIds) {
    if (!id) continue;
    const r = await migrateChurch(id);
    totalUpdated += r.updated;
  }

  console.log(`\nTotal ${dryRun ? "a migrar" : "migrados"}: ${totalUpdated}`);
  if (dryRun) {
    console.log("Execute sem --dry-run para gravar.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
