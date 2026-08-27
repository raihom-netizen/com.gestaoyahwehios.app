import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const CONFIG_DOC = "codigo_membro";
const SEQ_PAD = 5;

/** Marca do formato novo (sequencial puro) no doc de configuração. */
const SCHEMA_SEQUENCIAL = "seq";

function membersCol(tenantId: string) {
  return admin.firestore().collection("igrejas").doc(tenantId).collection("membros");
}

function configRef(tenantId: string) {
  return admin
    .firestore()
    .collection("igrejas")
    .doc(tenantId)
    .collection("config")
    .doc(CONFIG_DOC);
}

function readCodigoFromMember(data: Record<string, unknown>): string {
  for (const k of ["codigoMembro", "COD_MEMBRO", "codigo_membro", "numeroMembro"]) {
    const v = String(data[k] ?? "").trim();
    if (v) return v;
  }
  return "";
}

async function isCodeTaken(tenantId: string, code: string): Promise<boolean> {
  const col = membersCol(tenantId);
  for (const field of ["codigoMembro", "COD_MEMBRO", "codigo_membro"]) {
    const snap = await col.where(field, "==", code).limit(1).get();
    if (!snap.empty) return true;
  }
  return false;
}

/**
 * Próximo código sequencial da igreja — `NNNNN`, a partir de `00001`.
 *
 * Espelha `MemberCodigoService.allocateNext` no app: sequencial simples, sem o
 * ano à frente e sem reiniciar em janeiro. O contador do formato antigo
 * (`2026000NN`) é ignorado; colisão com código já usado é resolvida pela
 * verificação abaixo.
 */
export async function allocateCodigoMembro(tenantId: string): Promise<string> {
  const tid = tenantId.trim();
  const db = admin.firestore();
  const cfgRef = configRef(tid);

  for (let attempt = 0; attempt < 8; attempt++) {
    const code = await db.runTransaction(async (tx) => {
      const snap = await tx.get(cfgRef);
      const data = snap.data() ?? {};
      const novoEsquema = data.schema === SCHEMA_SEQUENCIAL;
      let next =
        novoEsquema && typeof data.nextSequence === "number"
          ? data.nextSequence
          : 1;
      if (next < 1) next = 1;
      const candidate = String(next).padStart(SEQ_PAD, "0");
      tx.set(
        cfgRef,
        {
          schema: SCHEMA_SEQUENCIAL,
          nextSequence: next + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return candidate;
    });

    if (!(await isCodeTaken(tid, code))) return code;
  }
  throw new Error("Não foi possível gerar código de membro único.");
}

/** Garante `codigoMembro` no documento (mantém existente salvo [forceNew]). */
export async function ensureCodigoMembroOnMember(
  tenantId: string,
  memberId: string,
  memberData?: Record<string, unknown>,
  forceNew = false
): Promise<string> {
  const tid = tenantId.trim();
  const mid = memberId.trim();
  const ref = membersCol(tid).doc(mid);
  let data = memberData ?? {};
  if (!Object.keys(data).length) {
    const snap = await ref.get();
    data = (snap.data() ?? {}) as Record<string, unknown>;
  }

  if (!forceNew) {
    const existing = readCodigoFromMember(data);
    if (existing) return existing;
  }

  const code = await allocateCodigoMembro(tid);
  await ref.set(
    {
      codigoMembro: code,
      COD_MEMBRO: code,
      codigo_membro: code,
      codigoMembroAtribuidoEm: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return code;
}

function isGestorCaller(
  role: string,
  tenantId: string,
  igrejaId: string
): boolean {
  const r = role.toUpperCase();
  return (
    ["ADMIN", "ADM", "GESTOR", "MASTER"].includes(r) &&
    (String(igrejaId) === tenantId || r === "MASTER")
  );
}

/** Atribui códigos a membros sem `codigoMembro` (lote, por igreja). */
export const backfillMemberCodigos = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "tenantId é obrigatório."
      );
    }
    const role = String((context.auth.token?.role as string) || "");
    const igrejaId = String(
      context.auth.token?.igrejaId || context.auth.token?.tenantId || ""
    );
    if (!isGestorCaller(role, tenantId, igrejaId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Apenas gestor pode gerar códigos."
      );
    }
    const limit = Math.min(
      200,
      Math.max(10, Number(data?.limit) || 80)
    );
    const snap = await membersCol(tenantId).limit(limit).get();
    let assigned = 0;
    let skipped = 0;
    let errors = 0;
    for (const doc of snap.docs) {
      if (readCodigoFromMember(doc.data() as Record<string, unknown>)) {
        skipped++;
        continue;
      }
      try {
        await ensureCodigoMembroOnMember(
          tenantId,
          doc.id,
          doc.data() as Record<string, unknown>
        );
        assigned++;
      } catch {
        errors++;
      }
    }
    return { ok: true, assigned, skipped, errors };
  });
