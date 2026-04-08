const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

function loadCredential() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return admin.credential.applicationDefault();
  }

  const secretsPath = path.resolve(__dirname, "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  if (fs.existsSync(secretsPath)) {
    const serviceAccount = require(secretsPath);
    return admin.credential.cert(serviceAccount);
  }

  return admin.credential.applicationDefault();
}

admin.initializeApp({
  credential: loadCredential(),
});

const db = admin.firestore();

function onlyDigits(v) {
  return String(v || "").replace(/[^0-9]/g, "").trim();
}

function normalizeRole(raw, fallback) {
  const r = String(raw || "").trim().toUpperCase();
  const allowed = ["MASTER", "GESTOR", "ADM", "ADMIN", "LIDER", "USER"];
  if (allowed.includes(r)) return r === "ADMIN" ? "ADM" : r;
  return fallback;
}

function resolveActive(member) {
  if (typeof member.active === "boolean") return member.active;
  if (typeof member.ATIVO === "boolean") return member.ATIVO;
  const status = String(member.STATUS || member.status || "").toLowerCase();
  if (status.includes("inativ")) return false;
  if (status.includes("ativo")) return true;
  return true;
}

async function backfillTenant(tenantId, tenantData) {
  const createdByCpf = onlyDigits(tenantData.createdByCpf || tenantData.ownerCpf || tenantData.gestorCpf || "");
  const membersSnap = await db
    .collection("tenants")
    .doc(tenantId)
    .collection("members")
    .get();

  let updated = 0;
  for (const doc of membersSnap.docs) {
    const m = doc.data() || {};
    const cpf = onlyDigits(m.CPF || m.cpf || doc.id);
    if (cpf.length !== 11) continue;

    const email = String(m.EMAIL || m.email || "").trim();
    if (!email) continue;

    const name = String(m.NOME_COMPLETO || m.nome || m.name || m.NOME || "").trim();
    const baseRole = cpf === createdByCpf ? "GESTOR" : "USER";
    const role = normalizeRole(m.role || m.ROLE || m.perfil || m.PERFIL || m.cargo || m.CARGO, baseRole);
    const active = resolveActive(m);

    await db
      .collection("tenants")
      .doc(tenantId)
      .collection("usersIndex")
      .doc(cpf)
      .set(
        {
          cpf,
          email,
          name,
          role,
          active,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    try {
      const user = await admin.auth().getUserByEmail(email);
      const claims = user.customClaims || {};
      await admin.auth().setCustomUserClaims(user.uid, {
        ...claims,
        role,
        igrejaId: tenantId,
      });

      await db.collection("users").doc(user.uid).set(
        {
          role,
          igrejaId: tenantId,
          cpf,
          ativo: active,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (e) {
      // user may not exist in Auth yet
    }

    updated += 1;
  }

  return updated;
}

(async () => {
  const tenantsSnap = await db.collection("tenants").get();
  let total = 0;

  for (const t of tenantsSnap.docs) {
    const count = await backfillTenant(t.id, t.data() || {});
    total += count;
    console.log(`Tenant ${t.id}: ${count} usuarios indexados.`);
  }

  console.log(`Concluido. Total atualizado: ${total}`);
  process.exit(0);
})().catch((e) => {
  console.error("ERRO:", e);
  process.exit(1);
});
