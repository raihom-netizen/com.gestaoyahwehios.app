import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { resolveTenantIdForCallable } from "./tenantCallableResolve";

const DIRECTORY_MAX = 800;

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function pickPhotoUrl(data: Record<string, unknown>): string {
  const keys = [
    "fotoUrl",
    "fotoURL",
    "FOTO_URL",
    "imageUrl",
    "photoUrl",
    "foto",
    "FOTO",
    "avatarUrl",
    "profilePhotoUrl",
  ];
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim().startsWith("http")) {
      return v.trim();
    }
  }
  return "";
}

function normCpf(raw: unknown): string {
  const d = String(raw ?? "").replace(/\D/g, "");
  if (!d) return "";
  if (d.length > 11) return d.substring(d.length - 11);
  if (d.length < 11) return d.padStart(11, "0");
  return d;
}

function directoryEntry(
  doc: admin.firestore.QueryDocumentSnapshot,
): Record<string, unknown> {
  const d = doc.data();
  const revRaw = d.fotoUrlCacheRevision ?? d.photoCacheRevision;
  const fotoUrlCacheRevision =
    typeof revRaw === "number" && Number.isFinite(revRaw)
      ? Math.floor(revRaw)
      : 0;
  const cpf = normCpf(pickString(d, ["CPF", "cpf"]) || normCpf(doc.id));
  const funcoesRaw = d.FUNCOES ?? d.funcoes;
  const funcoes: string[] = [];
  if (Array.isArray(funcoesRaw)) {
    for (const x of funcoesRaw) {
      const s = String(x ?? "").trim();
      if (s) funcoes.push(s);
    }
  }
  const deptRaw = d.DEPARTAMENTOS ?? d.departamentos ?? d.departamentosIds;
  const departamentos: string[] = [];
  if (Array.isArray(deptRaw)) {
    for (const x of deptRaw) {
      const s = String(x ?? "").trim();
      if (s) departamentos.push(s);
    }
  }
  const status = pickString(d, ["STATUS", "status"]).toLowerCase() || "ativo";
  return {
    memberDocId: doc.id,
    displayName:
      pickString(d, ["NOME_COMPLETO", "nome", "name"]) || "Membro",
    photoUrl: pickPhotoUrl(d) || null,
    fotoUrlCacheRevision,
    authUid:
      pickString(d, ["authUid", "firebaseUid", "uid", "userId"]) || null,
    cpfDigits: cpf.length === 11 ? cpf : null,
    email: pickString(d, ["EMAIL", "email"]) || null,
    telefone: pickString(d, ["TELEFONES", "TELEFONE", "telefone", "phone"]) || null,
    status,
    STATUS: status,
    funcao: pickString(d, ["FUNCAO", "funcao", "CARGO", "role"]) || null,
    funcoes,
    departamentos,
    genero: pickString(d, ["SEXO", "sexo", "genero", "gender"]) || null,
    createdAt: d.createdAt ?? d.criadoEm ?? null,
    updatedAt: d.updatedAt ?? null,
    dataNascimento:
      d.DATA_NASCIMENTO ?? d.dataNascimento ?? d.birthDate ?? null,
  };
}

/**
 * Grava `igrejas/{tenantId}/_panel_cache/members_directory` (1 read na lista).
 * Chamado após scan de `membros` no painel (sem segunda query).
 */
export async function recomputeMembersDirectoryFromDocs(
  tenantId: string,
  memberDocs: admin.firestore.QueryDocumentSnapshot[],
  totalCount?: number,
): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const entries = memberDocs
    .map((doc) => directoryEntry(doc))
    .sort((a, b) =>
      String(a.displayName ?? "")
        .toLowerCase()
        .localeCompare(String(b.displayName ?? "").toLowerCase()),
    )
    .slice(0, DIRECTORY_MAX);

  const ref = admin
    .firestore()
    .collection("igrejas")
    .doc(tid)
    .collection("_panel_cache")
    .doc("members_directory");

  await ref.set(
    {
      schemaVersion: 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      totalCount: typeof totalCount === "number" ? totalCount : entries.length,
      entries,
    },
    { merge: false },
  );

  functions.logger.info("membersDirectoryCache: atualizado", {
    tenantId: tid,
    entries: entries.length,
  });
}

/** Callable: 1 round-trip para lista leve de membros (módulo Membros). */
export const getChurchMembersDirectory = functions
  .region("us-central1")
  .https.onCall(async (request, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {}) as Record<string, unknown>;
    const tenantId = await resolveTenantIdForCallable(
      { uid: context.auth.uid, token: context.auth.token as Record<string, unknown> },
      String(body.tenantId || ""),
    );
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "igrejaId ausente",
      );
    }

    const db = admin.firestore();
    const ref = db
      .collection("igrejas")
      .doc(tenantId)
      .collection("_panel_cache")
      .doc("members_directory");

    const snap = await ref.get();
    const staleMs = 8 * 60 * 1000;
    let directory = snap.data();
    const updated = directory?.updatedAt as admin.firestore.Timestamp | undefined;
    const isStale =
      !snap.exists ||
      !updated ||
      Date.now() - updated.toMillis() > staleMs;

    if (isStale) {
      const membrosSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .orderBy("updatedAt", "desc")
        .limit(800)
        .get();
      let total = membrosSnap.size;
      try {
        const agg = await db
          .collection("igrejas")
          .doc(tenantId)
          .collection("membros")
          .count()
          .get();
        total = agg.data().count;
      } catch (_) {
        /* count opcional */
      }
      await recomputeMembersDirectoryFromDocs(tenantId, membrosSnap.docs, total);
      directory = (await ref.get()).data();
    }

    return { ok: true, tenantId, directory: directory ?? {} };
  });
