/**
 * Exclusão TOTAL de uma igreja — Firestore (recursivo) + Storage + índices.
 *
 * A exclusão que existia corria no cliente, apagando coleção a coleção a partir
 * de uma lista fixa: qualquer coleção criada depois ficava para trás, e o
 * Storage nunca era tocado — a mídia da igreja continuava a ocupar (e a pagar)
 * espaço no bucket para sempre. Aqui o Admin SDK faz `recursiveDelete` na raiz
 * `igrejas/{id}` (apanha tudo, inclusive o que ainda não existe hoje) e apaga o
 * prefixo `igrejas/{id}/` do bucket.
 *
 * Não apaga contas do Firebase Auth: a mesma conta pode pertencer a outra
 * igreja, e apagá-la aqui deixaria o utilizador sem acesso ao resto.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { fs } from "./adminDb";
import { isMasterOperator } from "./tenantCallableResolve";

interface DeleteChurchResult {
  ok: boolean;
  tenantId: string;
  storageFilesDeleted: number;
  indexesCleaned: string[];
}

/** Apaga `igrejas/{id}/` do bucket. Devolve quantos objetos saíram. */
async function deleteChurchStorage(tenantId: string): Promise<number> {
  const bucket = admin.storage().bucket();
  const prefix = `igrejas/${tenantId}/`;
  let total = 0;
  try {
    // getFiles pagina sozinho quando `autoPaginate` fica no default.
    const [files] = await bucket.getFiles({ prefix });
    total = files.length;
    // deleteFiles com o mesmo prefixo é mais barato do que apagar um a um.
    await bucket.deleteFiles({ prefix, force: true });
  } catch (e) {
    functions.logger.error("deleteChurchCompletely: storage", { tenantId, e });
    throw new functions.https.HttpsError(
      "internal",
      "Falha ao apagar os ficheiros da igreja no Storage.",
    );
  }
  return total;
}

/** Tira a igreja dos índices globais que vivem fora de `igrejas/{id}`. */
async function cleanGlobalIndexes(tenantId: string): Promise<string[]> {
  const db = fs();
  const cleaned: string[] = [];

  // Índice do seletor/lista do master.
  try {
    const ref = db.collection("config").doc("master_churches_index");
    const snap = await ref.get();
    const raw = snap.data() ?? {};
    const churches = Array.isArray(raw.churches)
      ? (raw.churches as Record<string, unknown>[])
      : [];
    const kept = churches.filter((c) => String(c.id) !== tenantId);
    if (kept.length !== churches.length) {
      const total =
        typeof raw.total === "number" ? Math.max(0, raw.total - 1) : kept.length;
      await ref.set({ churches: kept, total }, { merge: true });
      cleaned.push("config/master_churches_index");
    }
  } catch (e) {
    functions.logger.warn("deleteChurchCompletely: index master", { e });
  }

  // Slug público — sem isto o site da igreja continuava a resolver.
  try {
    const slugs = await db
      .collection("public_church_slugs")
      .where("tenantId", "==", tenantId)
      .get();
    for (const d of slugs.docs) {
      await d.ref.delete();
      cleaned.push(d.ref.path);
    }
  } catch (e) {
    functions.logger.warn("deleteChurchCompletely: slugs", { e });
  }

  return cleaned;
}

export const deleteChurchCompletely = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context): Promise<DeleteChurchResult> => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const uid = context.auth.uid;
    const email = String(
      ((context.auth.token as Record<string, unknown>)?.email as string) || "",
    )
      .trim()
      .toLowerCase();

    // Só o operador global apaga uma igreja inteira.
    if (!(await isMasterOperator(uid, email))) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Apenas o operador master pode excluir uma igreja.",
      );
    }

    const body = (data || {}) as Record<string, unknown>;
    const tenantId = String(body.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "tenantId obrigatorio",
      );
    }
    // Confirmação explícita: o chamador tem de repetir o id. Evita apagar a
    // igreja errada por um clique num cartão que não era o que estava à frente.
    if (String(body.confirmTenantId || "").trim() !== tenantId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Confirmacao do id da igreja nao confere.",
      );
    }

    const db = fs();
    const churchRef = db.collection("igrejas").doc(tenantId);
    const churchSnap = await churchRef.get();
    if (!churchSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Igreja nao encontrada.",
      );
    }
    const nome = String(
      (churchSnap.data() || {}).nome || (churchSnap.data() || {}).name || tenantId,
    );

    functions.logger.info("deleteChurchCompletely: inicio", {
      tenantId,
      nome,
      by: uid,
    });

    // Storage primeiro: se falhar, o Firestore fica intacto e o operador pode
    // repetir. Ao contrário, um Firestore já apagado deixaria a mídia órfã sem
    // nada que a referenciasse — e sem forma de a encontrar pela UI.
    const storageFilesDeleted = await deleteChurchStorage(tenantId);

    await db.recursiveDelete(churchRef);

    const indexesCleaned = await cleanGlobalIndexes(tenantId);

    functions.logger.info("deleteChurchCompletely: concluido", {
      tenantId,
      storageFilesDeleted,
      indexesCleaned,
    });

    return { ok: true, tenantId, storageFilesDeleted, indexesCleaned };
  });
