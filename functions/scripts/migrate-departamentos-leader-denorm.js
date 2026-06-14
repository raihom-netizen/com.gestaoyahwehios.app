/**
 * Migração em lote — preenche leaderName + leaderFotoUrl (e normaliza leaderCpfs)
 * em `igrejas/{churchId}/departamentos`.
 *
 * Resolve o 1.º líder via CPF em `membros` — mesma lógica de ChurchDepartmentLeaders (app).
 *
 * Uso (pasta `functions/`):
 *   node scripts/migrate-departamentos-leader-denorm.js --dry-run
 *   node scripts/migrate-departamentos-leader-denorm.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
 *   node scripts/migrate-departamentos-leader-denorm.js --force
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
const clearOrphans = args.includes("--clear-orphans");

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldPath = admin.firestore.FieldPath;

function normCpf(raw) {
  return String(raw ?? "").replace(/\D/g, "");
}

function canonicalCpfDigits(raw) {
  const d = normCpf(raw);
  if (!d) return "";
  if (d.length > 11) return d.substring(d.length - 11);
  if (d.length < 11) return d.padStart(11, "0");
  return d;
}

function cpfsFromDepartmentData(data) {
  const out = [];
  function add(v) {
    const x = normCpf(v);
    if (!x) return;
    if (x.length >= 9 && x.length <= 11) {
      const c = canonicalCpfDigits(x);
      if (!out.includes(c)) out.push(c);
    }
  }
  const raw =
    data.leaderCpfs ??
    data.leader_cpfs ??
    data.liderCpfs ??
    data.lider_cpfs;
  if (Array.isArray(raw)) {
    for (const e of raw) add(e);
  }
  add(data.leaderCpf);
  add(data.leader_cpf);
  add(data.LIDER_CPF);
  add(data.liderCpf);
  add(data.lider_cpf);
  add(data.viceLeaderCpf);
  add(data.vice_leader_cpf);
  add(data.viceLiderCpf);
  return out;
}

function memberDisplayName(data) {
  for (const k of ["NOME_COMPLETO", "nome", "name", "displayName"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
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

function resolveLeaderDenorm(cpfs, memberIndex) {
  let name = "";
  let foto = "";
  for (const cpf of cpfs) {
    const doc =
      memberIndex[cpf] ||
      memberIndex[cpf.replace(/^0+/, "")] ||
      memberIndex[canonicalCpfDigits(cpf)];
    if (!doc) continue;
    const n = memberDisplayName(doc);
    const f = memberPhotoUrl(doc);
    if (n) name = n;
    if (f) foto = f;
    if (name || foto) break;
  }
  return { leaderName: name, leaderFotoUrl: foto };
}

function leaderFieldsFromCpfs(cpfs) {
  return {
    leaderCpfs: cpfs,
    leaderCpf: cpfs.length > 0 ? cpfs[0] : "",
    viceLeaderCpf: cpfs.length > 1 ? cpfs[1] : "",
  };
}

function needsMigration(data, resolved, cpfs) {
  if (force) return true;

  const curName = String(data.leaderName ?? "").trim();
  const curFoto = String(data.leaderFotoUrl ?? "").trim();

  if (cpfs.length === 0) {
    if (clearOrphans && (curName || curFoto)) return true;
    return false;
  }

  if (resolved.leaderName && curName !== resolved.leaderName) return true;
  if (resolved.leaderFotoUrl && curFoto !== resolved.leaderFotoUrl) return true;
  if (cpfs.length > 0 && resolved.leaderName && !curName) return true;
  if (cpfs.length > 0 && resolved.leaderFotoUrl && !curFoto) return true;

  const curList = data.leaderCpfs;
  if (!Array.isArray(curList)) return true;
  if (curList.length !== cpfs.length) return true;
  for (let i = 0; i < cpfs.length; i++) {
    if (canonicalCpfDigits(curList[i]) !== cpfs[i]) return true;
  }
  return false;
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
      const raw = normCpf(data.CPF ?? data.cpf ?? d.id);
      if (raw.length < 9) continue;
      const c = canonicalCpfDigits(raw);
      map[c] = data;
      if (raw !== c) map[raw] = data;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  return map;
}

async function migrateDepartamentos(churchId, memberIndex, stats) {
  const col = db.collection("igrejas").doc(churchId).collection("departamentos");
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
      const cpfs = cpfsFromDepartmentData(data);
      const resolved = resolveLeaderDenorm(cpfs, memberIndex);

      if (!needsMigration(data, resolved, cpfs)) {
        stats.skipped++;
        continue;
      }

      const patch = {
        ...leaderFieldsFromCpfs(cpfs),
        leaderName: resolved.leaderName,
        leaderFotoUrl: resolved.leaderFotoUrl,
        leaderDenormMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
        leaderDenormMigratedBy: "migrate-departamentos-leader-denorm.js",
      };

      if (cpfs.length === 0 && clearOrphans) {
        patch.leaderName = "";
        patch.leaderFotoUrl = "";
      }

      stats.toMigrate++;
      if (dryRun) {
        console.log(
          `  [dry-run] ${churchId}/departamentos/${doc.id} cpfs=${cpfs.join(",") || "-"} → name="${resolved.leaderName}" foto=${resolved.leaderFotoUrl ? "sim" : "nao"}`
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
    dryRun ? "DRY-RUN (sem gravar)" : "GRAVACAO",
    force ? "| --force" : "",
    clearOrphans ? "| --clear-orphans" : ""
  );

  let churchIds = [];
  if (onlyIgreja) {
    const probe = await db.collection("igrejas").doc(onlyIgreja).get();
    if (!probe.exists) {
      console.error("Igreja nao encontrada:", onlyIgreja);
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
    toMigrate: 0,
    migrated: 0,
  };

  for (const churchId of churchIds) {
    totals.churches++;
    console.log(`\n→ ${churchId}`);
    let memberIndex = {};
    try {
      memberIndex = await buildMemberIndex(churchId);
      console.log(
        `  membros indexados por CPF: ${Object.keys(memberIndex).length}`
      );
    } catch (e) {
      console.warn("  Aviso: indice membros falhou:", e.message);
    }

    const stats = {
      scanned: 0,
      skipped: 0,
      toMigrate: 0,
      migrated: 0,
    };

    try {
      await migrateDepartamentos(churchId, memberIndex, stats);
    } catch (e) {
      console.warn("  Erro departamentos:", e.message || e);
    }

    console.log(
      `  scanned=${stats.scanned} skip=${stats.skipped} migrate=${stats.toMigrate} written=${stats.migrated}`
    );
    totals.scanned += stats.scanned;
    totals.skipped += stats.skipped;
    totals.toMigrate += stats.toMigrate;
    totals.migrated += stats.migrated;
  }

  console.log("\n=== Resumo ===");
  console.log("Igrejas:", totals.churches);
  console.log("Departamentos lidos:", totals.scanned);
  console.log("Ja OK / skip:", totals.skipped);
  console.log("A migrar:", totals.toMigrate);
  console.log(
    dryRun ? "Gravados (dry-run): 0" : `Gravados: ${totals.migrated}`
  );
  console.log("\nConcluido.");
}

main().catch((e) => {
  console.error(e);
  console.error(
    "\nPERMISSION_DENIED? Use GOOGLE_APPLICATION_CREDENTIALS ou:\n  gcloud auth application-default login"
  );
  process.exit(1);
});
