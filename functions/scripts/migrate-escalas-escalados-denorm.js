/**
 * Migração em lote — popula `escalados[]` (+ `memberUids`) em documentos legados
 * de `igrejas/{churchId}/escalas` e `escala_templates`.
 *
 * Leitura legada continua válida (memberCpfs + memberNames + confirmations por CPF).
 * Esta migração só denormaliza para leitura rápida; chaves CPF em `confirmations`
 * são preservadas e espelhadas por UID quando a ficha membro tem authUid.
 *
 * Uso (pasta `functions/`, credenciais Admin SDK):
 *   node scripts/migrate-escalas-escalados-denorm.js --dry-run
 *   node scripts/migrate-escalas-escalados-denorm.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
 *   node scripts/migrate-escalas-escalados-denorm.js --force
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
const skipConfirmMirror = args.includes("--no-confirm-mirror");
const collectionsArg = arg("--collections");
const collections = (collectionsArg || "escalas,escala_templates")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldPath = admin.firestore.FieldPath;

function normCpf(raw) {
  return String(raw ?? "").replace(/\D/g, "");
}

function mapValueForMemberKey(cpfKey, cpfDigits, map) {
  if (!map || typeof map !== "object") return "";
  const direct = map[cpfKey];
  if (direct != null && String(direct).trim() !== "") {
    return String(direct);
  }
  if (cpfDigits.length === 11) {
    const byDigits = map[cpfDigits];
    if (byDigits != null && String(byDigits).trim() !== "") {
      return String(byDigits);
    }
  }
  for (const [k, v] of Object.entries(map)) {
    if (normCpf(k) === cpfDigits && cpfDigits.length === 11) {
      return String(v ?? "");
    }
  }
  return "";
}

function mapReasonForMemberKey(cpfKey, cpfDigits, uid, map) {
  if (!map || typeof map !== "object") return null;
  const uidKey = String(uid ?? "").trim();
  if (uidKey && map[uidKey] && typeof map[uidKey] === "object") {
    return map[uidKey];
  }
  const direct = map[cpfKey];
  if (direct && typeof direct === "object") return direct;
  if (cpfDigits.length === 11) {
    const byDigits = map[cpfDigits];
    if (byDigits && typeof byDigits === "object") return byDigits;
  }
  for (const [k, v] of Object.entries(map)) {
    if (
      normCpf(k) === cpfDigits &&
      cpfDigits.length === 11 &&
      v &&
      typeof v === "object"
    ) {
      return v;
    }
  }
  return null;
}

function hasLegacyMembers(data) {
  const cpfs = data.memberCpfs;
  return Array.isArray(cpfs) && cpfs.length > 0;
}

function needsMigration(data) {
  if (!hasLegacyMembers(data)) return false;
  if (force) return true;
  const escalados = data.escalados;
  const cpfs = data.memberCpfs || [];
  if (Array.isArray(escalados) && escalados.length > 0) {
    if (cpfs.length === 0) return false;
    return escalados.length < cpfs.length;
  }
  return true;
}

function buildEscaladosFromLegacy(data, memberDocByCpf) {
  const cpfs = (data.memberCpfs || []).map((e) => String(e));
  const names = (data.memberNames || []).map((e) => String(e));
  const confirmations = data.confirmations || {};
  const escalados = [];
  const memberUids = [];

  for (let i = 0; i < cpfs.length; i++) {
    const cpf = cpfs[i];
    const digits = normCpf(cpf);
    const name = i < names.length ? String(names[i]).trim() : "";
    const doc =
      digits.length === 11 && memberDocByCpf ? memberDocByCpf[digits] : null;
    const uid = doc
      ? String(doc.authUid ?? doc.firebaseUid ?? "").trim()
      : "";
    const role = doc
      ? String(doc.FUNCAO ?? doc.funcao ?? doc.role ?? "").trim()
      : "";
    const photoUrl = doc
      ? String(
          doc.fotoUrl ?? doc.FOTO_URL_OU_ID ?? doc.photoUrl ?? ""
        ).trim()
      : "";
    const confirmation = mapValueForMemberKey(cpf, digits, confirmations);

    const row = {
      cpf,
      name,
    };
    if (digits.length === 11) row.cpfDigits = digits;
    if (uid) row.uid = uid;
    if (role) row.role = role;
    if (photoUrl) row.photoUrl = photoUrl;
    if (confirmation) row.confirmation = confirmation;
    escalados.push(row);
    if (uid) memberUids.push(uid);
  }

  return {
    escalados,
    memberUids: [...new Set(memberUids)],
    memberCpfs: cpfs,
    memberNames: names,
  };
}

function mirrorConfirmationMaps(escalados, data) {
  if (skipConfirmMirror) {
    return { confirmations: null, unavailabilityReasons: null };
  }
  const confirmations = { ...(data.confirmations || {}) };
  const reasons = { ...(data.unavailabilityReasons || {}) };
  let confChanged = false;
  let reasonChanged = false;

  for (const row of escalados) {
    const uid = String(row.uid ?? "").trim();
    if (!uid) continue;
    const cpf = row.cpf;
    const digits = row.cpfDigits || normCpf(cpf);
    const status =
      row.confirmation || mapValueForMemberKey(cpf, digits, confirmations);
    if (status && confirmations[uid] !== status) {
      confirmations[uid] = status;
      confChanged = true;
    }
    const reason = mapReasonForMemberKey(cpf, digits, uid, reasons);
    if (reason) {
      const prev = reasons[uid];
      if (JSON.stringify(prev) !== JSON.stringify(reason)) {
        reasons[uid] = reason;
        reasonChanged = true;
      }
    }
  }

  return {
    confirmations: confChanged ? confirmations : null,
    unavailabilityReasons: reasonChanged ? reasons : null,
  };
}

async function buildMemberIndex(churchId) {
  const map = {};
  const col = db.collection("igrejas").doc(churchId).collection("membros");
  let last = null;
  for (;;) {
    let q = col.orderBy(FieldPath.documentId()).limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const d of snap.docs) {
      const data = d.data() || {};
      const cpf = normCpf(data.CPF ?? data.cpf ?? d.id);
      if (cpf.length === 11) map[cpf] = data;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  return map;
}

async function migrateCollection(churchId, collectionName, memberIndex, stats) {
  const col = db.collection("igrejas").doc(churchId).collection(collectionName);
  let last = null;
  for (;;) {
    let q = col.orderBy(FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    let batch = db.batch();
    let batchCount = 0;

    async function flushBatch() {
      if (batchCount === 0) return;
      if (!dryRun) await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }

    for (const doc of snap.docs) {
      stats.scanned++;
      const data = doc.data() || {};
      if (!needsMigration(data)) {
        stats.skipped++;
        continue;
      }

      const built = buildEscaladosFromLegacy(data, memberIndex);
      if (built.escalados.length === 0) {
        stats.skippedEmpty++;
        continue;
      }

      const mirrored = mirrorConfirmationMaps(built.escalados, data);
      const patch = {
        escalados: built.escalados,
        memberUids: built.memberUids,
        memberCpfs: built.memberCpfs,
        memberNames: built.memberNames,
        escaladosDenormMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
        escaladosDenormMigratedBy: "migrate-escalas-escalados-denorm.js",
      };
      if (mirrored.confirmations) patch.confirmations = mirrored.confirmations;
      if (mirrored.unavailabilityReasons) {
        patch.unavailabilityReasons = mirrored.unavailabilityReasons;
      }

      stats.toMigrate++;
      if (dryRun) {
        console.log(
          `  [dry-run] ${churchId}/${collectionName}/${doc.id} → ${built.escalados.length} escalado(s), ${built.memberUids.length} uid(s)`
        );
        continue;
      }

      batch.set(doc.ref, patch, { merge: true });
      batchCount++;
      stats.migrated++;
      if (batchCount >= 400) await flushBatch();
    }

    await flushBatch();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 300) break;
  }
}

async function main() {
  console.log("Projeto:", projectId);
  console.log(
    "Modo:",
    dryRun ? "DRY-RUN (sem gravar)" : "GRAVAÇÃO",
    force ? "| --force" : "",
    skipConfirmMirror ? "| sem espelho UID em confirmations" : ""
  );
  console.log("Coleções:", collections.join(", "));

  let churchIds = [];
  if (onlyIgreja) {
    const probe = await db.collection("igrejas").doc(onlyIgreja).get();
    if (!probe.exists) {
      console.error("Igreja não encontrada:", onlyIgreja);
      process.exit(1);
    }
    churchIds = [onlyIgreja];
  } else {
    const snap = await db.collection("igrejas").get();
    churchIds = snap.docs.map((d) => d.id);
  }

  const totals = {
    churches: 0,
    scanned: 0,
    skipped: 0,
    skippedEmpty: 0,
    toMigrate: 0,
    migrated: 0,
  };

  for (const churchId of churchIds) {
    totals.churches++;
    console.log(`\n→ ${churchId}`);
    let memberIndex = {};
    try {
      memberIndex = await buildMemberIndex(churchId);
      console.log(`  membros indexados por CPF: ${Object.keys(memberIndex).length}`);
    } catch (e) {
      console.warn("  Aviso: índice membros falhou — escalados sem UID:", e.message);
    }

    const stats = {
      scanned: 0,
      skipped: 0,
      skippedEmpty: 0,
      toMigrate: 0,
      migrated: 0,
    };

    for (const collectionName of collections) {
      try {
        await migrateCollection(churchId, collectionName, memberIndex, stats);
      } catch (e) {
        console.warn(`  Erro em ${collectionName}:`, e.message || e);
      }
    }

    console.log(
      `  scanned=${stats.scanned} skip=${stats.skipped} migrate=${stats.toMigrate} written=${stats.migrated}`
    );
    totals.scanned += stats.scanned;
    totals.skipped += stats.skipped;
    totals.skippedEmpty += stats.skippedEmpty;
    totals.toMigrate += stats.toMigrate;
    totals.migrated += stats.migrated;
  }

  console.log("\n=== Resumo ===");
  console.log("Igrejas:", totals.churches);
  console.log("Docs lidos:", totals.scanned);
  console.log("Já OK / skip:", totals.skipped);
  console.log("Sem membros legado:", totals.skippedEmpty);
  console.log("A migrar:", totals.toMigrate);
  console.log(
    dryRun ? "Gravados (dry-run): 0" : `Gravados: ${totals.migrated}`
  );
  console.log("\nConcluído.");
}

main().catch((e) => {
  console.error(e);
  console.error(
    "\nPERMISSION_DENIED? Use GOOGLE_APPLICATION_CREDENTIALS ou:\n  gcloud auth application-default login"
  );
  process.exit(1);
});
