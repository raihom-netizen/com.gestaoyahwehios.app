/**
 * Limpeza administrativa — remove avisos/eventos corrompidos
 * (sem título válido ou sem mídia) em `igrejas/{churchId}/avisos` e `eventos`.
 *
 * Uso (pasta `functions/`):
 *   node scripts/cleanup-corrupt-feed-posts.js --dry-run
 *   node scripts/cleanup-corrupt-feed-posts.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
 *   node scripts/cleanup-corrupt-feed-posts.js --execute
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
const dryRun = args.includes("--dry-run") || !args.includes("--execute");

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

const JUNK_TITLES = new Set([
  "sem título",
  "sem titulo",
  "sem titulo.",
  "sem título.",
]);

function resolveTitle(data) {
  for (const k of ["title", "titulo", "name", "nome"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
}

function resolveText(data) {
  for (const k of ["text", "texto", "description", "descricao", "body"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
}

function hasSubstantialText(data, minLen = 12) {
  return resolveText(data).length >= minLen;
}

function hasValidTitle(data) {
  const t = resolveTitle(data);
  if (!t) return false;
  if (JUNK_TITLES.has(t.toLowerCase())) return false;
  return true;
}

function listHasMedia(raw) {
  if (!Array.isArray(raw)) return false;
  return raw.some((e) => String(e ?? "").trim().length > 0);
}

function hasValidMedia(data) {
  for (const k of [
    "imageUrl",
    "coverPhotoUrl",
    "coverPhoto",
    "photoUrl",
    "bannerUrl",
    "fotoUrl",
    "videoUrl",
    "thumbUrl",
    "thumbnailUrl",
    "videoThumbUrl",
  ]) {
    if (String(data[k] ?? "").trim()) return true;
  }
  for (const k of ["imageUrls", "galeria", "photos", "photoUrls", "videos"]) {
    if (listHasMedia(data[k])) return true;
  }
  for (const k of [
    "storagePath",
    "imageStoragePath",
    "bannerStoragePath",
    "fotoPath",
    "thumbStoragePath",
    "videoPath",
  ]) {
    if (String(data[k] ?? "").trim()) return true;
  }
  for (const k of ["imageStoragePaths", "fotoStoragePaths", "thumbStoragePaths"]) {
    if (listHasMedia(data[k])) return true;
  }
  return false;
}

async function cleanupCollection(churchId, sub) {
  const snap = await db
    .collection("igrejas")
    .doc(churchId)
    .collection(sub)
    .get();

  let removed = 0;
  let kept = 0;
  const batchSize = 400;
  let batch = db.batch();
  let batchCount = 0;

  async function flush() {
    if (batchCount === 0) return;
    if (!dryRun) await batch.commit();
    batch = db.batch();
    batchCount = 0;
  }

  function isCorruptDoc(data, docId) {
    if (!hasValidTitle(data)) return true;
    if (hasValidMedia(data)) return false;
    if (hasSubstantialText(data)) return false;
    // Instâncias de agenda expandida — manter mesmo sem foto.
    if (sub === "eventos" && docId.startsWith("evt_") && data.startAt) {
      return false;
    }
    return true;
  }

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!isCorruptDoc(data, doc.id)) {
      kept++;
      continue;
    }
    const title = resolveTitle(data) || "(vazio)";
    console.log(
      `  [${dryRun ? "DEL?" : "DEL"}] ${sub}/${doc.id} — titulo="${title}"`
    );
    if (!dryRun) {
      batch.delete(doc.ref);
      batchCount++;
      if (batchCount >= batchSize) await flush();
    }
    removed++;
  }

  await flush();
  return { scanned: snap.size, removed, kept };
}

async function cleanupChurch(churchId) {
  console.log(`\n=== Igreja: ${churchId} ===`);
  const avisos = await cleanupCollection(churchId, "avisos");
  const eventos = await cleanupCollection(churchId, "eventos");
  console.log(
    `  Avisos: ${avisos.scanned} lidos, ${avisos.removed} ${dryRun ? "a remover" : "removidos"}, ${avisos.kept} ok`
  );
  console.log(
    `  Eventos: ${eventos.scanned} lidos, ${eventos.removed} ${dryRun ? "a remover" : "removidos"}, ${eventos.kept} ok`
  );
  return avisos.removed + eventos.removed;
}

async function main() {
  console.log(`Projeto: ${projectId}`);
  console.log(`Modo: ${dryRun ? "DRY-RUN (use --execute para apagar)" : "EXECUÇÃO — DELETE"}`);

  let churchIds = [];
  if (onlyIgreja) {
    churchIds = [onlyIgreja.trim()];
  } else {
    const igrejasSnap = await db.collection("igrejas").select().get();
    churchIds = igrejasSnap.docs.map((d) => d.id);
  }

  let total = 0;
  for (const id of churchIds) {
    if (!id) continue;
    total += await cleanupChurch(id);
  }

  console.log(`\nTotal ${dryRun ? "a remover" : "removido"}: ${total}`);
  if (dryRun) {
    console.log("Execute com --execute para apagar definitivamente.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
