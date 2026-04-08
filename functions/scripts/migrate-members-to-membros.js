/**
 * Migração local (Admin SDK) — não depende das Cloud Functions.
 *
 * 1) igrejas/{id}/members  →  igrejas/{id}/membros (merge)
 * 2) users  →  igrejas/{id}/membros (quem tem tenantId/igrejaId)
 *
 * Uso (na pasta functions):
 *   node scripts/migrate-members-to-membros.js
 *   node scripts/migrate-members-to-membros.js --igreja=ID_DA_IGREJA
 *   node scripts/migrate-members-to-membros.js --no-users
 *
 * Credenciais: variável GOOGLE_APPLICATION_CREDENTIALS (JSON da conta de serviço)
 * ou:  gcloud auth application-default login
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const args = process.argv.slice(2);
const igrejaArg = args.find((a) => a.startsWith("--igreja="));
const onlyIgreja = igrejaArg ? igrejaArg.split("=")[1].trim() : "";
const skipUsers = args.includes("--no-users");

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const FieldPath = admin.firestore.FieldPath;

function stripUndef(o) {
  const out = {};
  for (const [k, v] of Object.entries(o)) {
    if (v !== undefined) out[k] = v;
  }
  return out;
}

async function copyMembersToMembros(igrejaId) {
  const base = db.collection("igrejas").doc(igrejaId);
  const probe = await base.collection("members").limit(1).get();
  if (probe.empty) return 0;
  let total = 0;
  let last = null;
  for (;;) {
    let q = base.collection("members").orderBy(FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const d of snap.docs) {
      batch.set(base.collection("membros").doc(d.id), d.data() || {}, { merge: true });
      total++;
    }
    await batch.commit();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }
  return total;
}

async function syncUsersToMembros() {
  const [usersSnap, igSnap] = await Promise.all([
    db.collection("users").get(),
    db.collection("igrejas").get(),
  ]);
  const igSet = new Set(igSnap.docs.map((d) => d.id));
  let written = 0;
  let batch = db.batch();
  let n = 0;

  async function flush() {
    if (n === 0) return;
    await batch.commit();
    batch = db.batch();
    n = 0;
  }

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const u = userDoc.data() || {};
    let tenantId = String(u.tenantId ?? u.tenant_id ?? "").trim();
    let igrejaId = String(u.igrejaId ?? u.igreja_id ?? "").trim();
    if (!tenantId && !igrejaId) continue;

    const nome =
      String(u.nome ?? u.name ?? u.displayName ?? u.NOME_COMPLETO ?? "").trim() ||
      "Membro";
    const email = String(u.email ?? u.Email ?? u.EMAIL ?? "").trim();
    const cpf = String(u.cpf ?? u.CPF ?? "")
      .replace(/\D/g, "")
      .trim();
    const photoUrl = String(
      u.photoUrl ?? u.fotoUrl ?? u.photoURL ?? u.avatarUrl ?? u.imageUrl ?? u.FOTO_URL_OU_ID ?? ""
    ).trim();
    const status = u.ativo === false || u.active === false ? "inativo" : "ativo";
    const sexo = String(u.SEXO ?? u.sexo ?? u.genero ?? "").trim();
    const dataNasc = u.DATA_NASCIMENTO ?? u.dataNascimento ?? u.birthDate ?? null;

    const memberPayload = {
      authUid: uid,
      NOME_COMPLETO: nome,
      nome,
      name: nome,
      EMAIL: email,
      email,
      CPF: cpf,
      cpf,
      STATUS: status,
      status,
      tenantId: tenantId || igrejaId,
      igrejaId: igrejaId || tenantId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedFromUsersScriptAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (sexo) {
      memberPayload.SEXO = sexo;
      memberPayload.sexo = sexo;
    }
    if (dataNasc != null) {
      memberPayload.DATA_NASCIMENTO = dataNasc;
      memberPayload.dataNascimento = dataNasc;
    }
    if (photoUrl && (photoUrl.startsWith("http://") || photoUrl.startsWith("https://"))) {
      memberPayload.FOTO_URL_OU_ID = photoUrl;
      memberPayload.fotoUrl = photoUrl;
      memberPayload.photoUrl = photoUrl;
    }

    const ids = new Set();
    if (tenantId) ids.add(tenantId);
    if (igrejaId) ids.add(igrejaId);

    const clean = stripUndef(memberPayload);
    for (const churchId of ids) {
      if (!churchId || !igSet.has(churchId)) continue;
      batch.set(
        db.collection("igrejas").doc(churchId).collection("membros").doc(uid),
        clean,
        { merge: true }
      );
      n++;
      written++;
      if (n >= 400) await flush();
    }
  }
  await flush();
  return written;
}

async function main() {
  console.log("Projeto:", projectId);
  let igrejaIds = [];
  if (onlyIgreja) {
    const doc = await db.collection("igrejas").doc(onlyIgreja).get();
    if (!doc.exists) {
      console.error("Igreja não encontrada:", onlyIgreja);
      process.exit(1);
    }
    igrejaIds = [onlyIgreja];
  } else {
    const snap = await db.collection("igrejas").get();
    igrejaIds = snap.docs.map((d) => d.id);
  }

  let copied = 0;
  for (const id of igrejaIds) {
    try {
      const n = await copyMembersToMembros(id);
      if (n > 0) console.log("  members→membros", id, ":", n, "doc(s)");
      copied += n;
    } catch (e) {
      console.warn("  Erro em", id, e.message);
    }
  }
  console.log("Total members→membros:", copied);

  if (!skipUsers) {
    console.log("Sincronizando users → igrejas/.../membros ...");
    const w = await syncUsersToMembros();
    console.log("Escritos (merge) em membros a partir de users:", w);
  }

  console.log("Concluído.");
}

main().catch((e) => {
  console.error(e);
  console.error(
    "\nSe deu PERMISSION_DENIED: use conta de serviço com permissão Firestore ou:\n  gcloud auth application-default login"
  );
  process.exit(1);
});
