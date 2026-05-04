/**
 * Reassocia a ficha em `igrejas/{tenantId}/membros` a outro Firebase Auth UID:
 * copia o documento para `membros/{novoUid}` (id = UID), copia pastas no Storage,
 * sincroniza `users/{uid}`, usersIndex por CPF e, se existir, `igrejas/{tid}/users/{uid}`.
 *
 * Uso (pasta `functions/`, com credenciais Admin — ex.: gcloud auth application-default login):
 *
 *   node scripts/migrate-membro-auth-uid.js ^
 *     --tenant=igreja_o_brasil_para_cristo_jardim_goiano ^
 *     --from=cJjqfn9bAffkF5k48vdDiVVYzrv2 ^
 *     --to=O0qRLmLER2hwBFqvlzqSdtAUC3D3
 *
 * Simular sem gravar:
 *   node scripts/migrate-membro-auth-uid.js --tenant=... --from=... --to=... --dry-run
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const args = process.argv.slice(2);
function arg(name) {
  const p = args.find((a) => a.startsWith(`${name}=`));
  return p ? p.split("=").slice(1).join("=").trim() : "";
}

const tenantId = arg("--tenant");
const fromUid = arg("--from");
const toUid = arg("--to");
const dryRun = args.includes("--dry-run");

if (!tenantId || !fromUid || !toUid) {
  console.error(
    "Uso: node scripts/migrate-membro-auth-uid.js --tenant=TID --from=UID_ANTIGO --to=UID_NOVO [--dry-run]"
  );
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

async function copyIgrejaMembroStorageFolder(tenantId, fromFolderId, toFolderId) {
  if (!fromFolderId || !toFolderId || fromFolderId === toFolderId) return;
  try {
    const bucket = admin.storage().bucket();
    const prefix = `igrejas/${tenantId}/membros/${fromFolderId}/`;
    const [files] = await bucket.getFiles({ prefix });
    for (const f of files) {
      const rel = f.name.startsWith(prefix) ? f.name.slice(prefix.length) : "";
      if (!rel) continue;
      const dest = `igrejas/${tenantId}/membros/${toFolderId}/${rel}`;
      await bucket.file(f.name).copy(bucket.file(dest));
    }
    console.log(`Storage: copiados objetos de membros/${fromFolderId}/ → membros/${toFolderId}/`);
  } catch (e) {
    console.warn("copyIgrejaMembroStorageFolder:", e.message || e);
  }
}

async function applyMemberAuthSideEffects(tenantId, authUid, memberData, authUser) {
  const status = String(memberData.STATUS || memberData.status || "").toLowerCase();
  const reallyAtivo = status === "ativo" || (status !== "pendente" && status !== "reprovado");
  const cpf = String(memberData.CPF || memberData.cpf || "").replace(/\D/g, "");
  const nome = String(memberData.NOME_COMPLETO || memberData.nome || memberData.name || "").trim();
  await admin.auth().setCustomUserClaims(authUid, {
    role: "membro",
    igrejaId: tenantId,
    tenantId,
    active: reallyAtivo,
    isUser: true,
    isDriver: false,
    pendingApproval: status === "pendente",
    ...(cpf.length === 11 ? { cpf } : {}),
  });
  await db
    .collection("users")
    .doc(authUid)
    .set(
      {
        email: String(authUser.email || "")
          .trim()
          .toLowerCase(),
        cpf: cpf.length === 11 ? cpf : "",
        igrejaId: tenantId,
        tenantId,
        role: "membro",
        nome,
        displayName: nome,
        nomeCompleto: nome,
        ativo: reallyAtivo,
      },
      { merge: true }
    );
  const indexPayload = {
    uid: authUid,
    cpf: cpf.length === 11 ? cpf : "",
    email: String(authUser.email || "")
      .trim()
      .toLowerCase(),
    name: nome,
    nome,
    tenantId,
    role: "membro",
    active: reallyAtivo,
    pendingApproval: status === "pendente",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (cpf.length === 11) {
    await db
      .collection("tenants")
      .doc(tenantId)
      .collection("usersIndex")
      .doc(cpf)
      .set(indexPayload, { merge: true });
    await db
      .collection("igrejas")
      .doc(tenantId)
      .collection("usersIndex")
      .doc(cpf)
      .set(indexPayload, { merge: true });
  }
}

async function findMemberRef(tenantId, uidOrId) {
  const membrosCol = db.collection("igrejas").doc(tenantId).collection("membros");
  const direct = await membrosCol.doc(uidOrId).get();
  if (direct.exists) return direct;
  const byAuth = await membrosCol.where("authUid", "==", uidOrId).limit(1).get();
  if (!byAuth.empty) return byAuth.docs[0];
  return null;
}

async function main() {
  console.log({ tenantId, fromUid, toUid, dryRun, projectId });

  const authUser = await admin.auth().getUser(toUid);
  console.log("Destino Auth OK:", authUser.email, authUser.uid);

  const memberSnap = await findMemberRef(tenantId, fromUid);
  if (!memberSnap) {
    throw new Error(
      `Nenhum documento em membros com id ou authUid = "${fromUid}".`
    );
  }

  const memberRef = memberSnap.ref;
  const memberData = memberSnap.data() || {};
  const oldDocId = memberRef.id;

  const emailMembro = String(memberData.EMAIL || memberData.email || "")
    .trim()
    .toLowerCase();
  const emailAuth = String(authUser.email || "")
    .trim()
    .toLowerCase();
  if (emailMembro && emailAuth && emailMembro !== emailAuth) {
    console.warn(
      `AVISO: e-mail na ficha (${emailMembro}) ≠ e-mail da conta destino (${emailAuth}). Confirme se é intencional.`
    );
  }

  if (oldDocId === toUid) {
    console.log("Doc já está em membros/{novoUid}; só atualizando campos e claims.");
    if (!dryRun) {
      await memberRef.set(
        {
          authUid: toUid,
          MEMBER_ID: toUid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      await applyMemberAuthSideEffects(tenantId, toUid, memberData, authUser);
    }
    console.log(dryRun ? "[dry-run] ok" : "Concluído (mesmo id).");
    return;
  }

  const newRefProbe = db.collection("igrejas").doc(tenantId).collection("membros").doc(toUid);
  const clash = await newRefProbe.get();
  if (clash.exists && clash.id !== memberRef.id) {
    throw new Error(
      `Já existe membros/${toUid} (outro cadastro). Resolva duplicidade antes de migrar.`
    );
  }

  await copyIgrejaMembroStorageFolder(tenantId, oldDocId, toUid);

  const newRef = db.collection("igrejas").doc(tenantId).collection("membros").doc(toUid);
  const payload = {
    ...memberData,
    authUid: toUid,
    MEMBER_ID: toUid,
    legacyMemberDocId: oldDocId,
    photoStoragePath: `igrejas/${tenantId}/membros/${toUid}/foto_perfil.jpg`,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (dryRun) {
    console.log("[dry-run] Criaria membros/" + toUid + ", apagaria membros/" + oldDocId);
    return;
  }

  await newRef.set(payload, { merge: true });
  await memberRef.delete();
  console.log(`Firestore: membros/${oldDocId} → membros/${toUid}`);

  const igUsersOld = db
    .collection("igrejas")
    .doc(tenantId)
    .collection("users")
    .doc(oldDocId);
  const igUsersNew = db
    .collection("igrejas")
    .doc(tenantId)
    .collection("users")
    .doc(toUid);
  const igSnap = await igUsersOld.get();
  if (igSnap.exists) {
    await igUsersNew.set(igSnap.data() || {}, { merge: true });
    await igUsersOld.delete();
    console.log(`igrejas/.../users: ${oldDocId} → ${toUid}`);
  }

  await applyMemberAuthSideEffects(tenantId, toUid, payload, authUser);
  console.log("Claims + users/ + usersIndex atualizados.");
  console.log("Feito. Use o login da conta destino (UID novo).");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
