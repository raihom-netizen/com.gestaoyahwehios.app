import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { isForbiddenTestChurchId } from "./forbiddenTestChurchIds";
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
    "FOTO_URL_OU_ID",
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

function pickPhotoThumbUrl(data: Record<string, unknown>): string {
  const keys = [
    "fotoThumbUrl",
    "photoThumbUrl",
    "photoThumb",
    "thumbUrl",
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
  const fullPhoto = pickPhotoUrl(d);
  const thumbPhoto = pickPhotoThumbUrl(d) || fullPhoto || null;
  return {
    memberDocId: doc.id,
    displayName:
      pickString(d, ["NOME_COMPLETO", "nome", "name"]) || "Membro",
    photoUrl: fullPhoto || null,
    photoThumbUrl: thumbPhoto,
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
    // Assinatura da carteirinha — faltava aqui, por isso o painel mostrava
    // "Pendente assinatura" para sempre: este cache (lido por
    // getChurchMembersDirectory) nunca carregava esses campos do doc real,
    // mesmo depois do membro assinar.
    carteirinhaAssinadaEm: d.carteirinhaAssinadaEm ?? null,
    carteirinhaAssinadaPor: pickString(d, ["carteirinhaAssinadaPor"]) || null,
    carteirinhaAssinadaPorNome:
      pickString(d, ["carteirinhaAssinadaPorNome"]) || null,
    carteirinhaAssinadaPorCargo:
      pickString(d, ["carteirinhaAssinadaPorCargo"]) || null,
    carteirinhaAssinaturaUrl:
      pickString(d, ["carteirinhaAssinaturaUrl"]) || null,
    carteirinhaAssinadaPorUsuarioUid:
      pickString(d, ["carteirinhaAssinadaPorUsuarioUid"]) || null,
    carteirinhaAssinadaPorUsuarioNome:
      pickString(d, ["carteirinhaAssinadaPorUsuarioNome"]) || null,
    carteirinhaAssinadaPorUsuarioRole:
      pickString(d, ["carteirinhaAssinadaPorUsuarioRole"]) || null,
  };
}

function computeMembersSummary(
  memberDocs: admin.firestore.QueryDocumentSnapshot[],
): Record<string, number> {
  let ativos = 0;
  let inativos = 0;
  let pendentes = 0;
  let homens = 0;
  let mulheres = 0;
  let sexoNi = 0;
  for (const doc of memberDocs) {
    const e = directoryEntry(doc);
    const status = String(e.status ?? "ativo").toLowerCase();
    if (status.includes("pendente")) pendentes += 1;
    else if (status.includes("inativ")) inativos += 1;
    else ativos += 1;
    const g = String(e.genero ?? "").toLowerCase().trim();
    if (g.startsWith("m") || g === "masculino" || g === "m") homens += 1;
    else if (g.startsWith("f") || g === "feminino" || g === "f") mulheres += 1;
    else sexoNi += 1;
  }
  return {
    total: memberDocs.length,
    ativos,
    inativos,
    pendentes,
    homens,
    mulheres,
    sexoNi,
  };
}

/**
 * Ticket monotônico por tenant — obtido ANTES do trabalho pesado (scan/merge
 * de `membros`), para refletir a ordem de chegada dos pedidos de recompute.
 * Escritas concorrentes do mesmo cache (ex.: assinar 59 carteirinhas de uma
 * vez dispara 59 triggers `onWrite` em paralelo) terminam fora de ordem —
 * sem isso, a última a TERMINAR vence, mesmo que tenha lido um estado mais
 * antigo/incompleto de `membros`. Ver [writeMembersDirectoryIfNewer].
 */
async function nextMembersDirectorySeq(tid: string): Promise<number> {
  const seqRef = admin
    .firestore()
    .collection("igrejas")
    .doc(tid)
    .collection("_panel_cache")
    .doc("_members_directory_seq");
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(seqRef);
    const current = (snap.data()?.seq as number | undefined) ?? 0;
    const next = current + 1;
    tx.set(seqRef, { seq: next }, { merge: true });
    return next;
  });
}

/**
 * Só aplica a escrita se [ticket] for >= ao `writeSeq` já persistido —
 * descarta resultados de execuções concorrentes mais antigas que terminaram
 * depois de uma mais nova (condição de corrida do trigger `onWrite`).
 */
async function writeMembersDirectoryIfNewer(
  ref: admin.firestore.DocumentReference,
  ticket: number,
  payload: Record<string, unknown>,
): Promise<boolean> {
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const currentSeq = (snap.data()?.writeSeq as number | undefined) ?? 0;
    if (ticket < currentSeq) return false;
    tx.set(ref, { ...payload, writeSeq: ticket }, { merge: false });
    return true;
  });
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
  if (isForbiddenTestChurchId(tid)) return;
  const churchRef = admin.firestore().collection("igrejas").doc(tid);
  if (!(await churchRef.get()).exists) return;

  const ticket = await nextMembersDirectorySeq(tid);

  const summary = computeMembersSummary(memberDocs);
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

  const resolvedTotal =
    typeof totalCount === "number" && totalCount > 0
      ? totalCount
      : memberDocs.length;

  const applied = await writeMembersDirectoryIfNewer(ref, ticket, {
    schemaVersion: 2,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    totalCount: resolvedTotal,
    summary: {
      ...summary,
      total: resolvedTotal,
    },
    entries,
  });

  if (!applied) {
    functions.logger.info("membersDirectoryCache: descartado (superado)", {
      tenantId: tid,
      ticket,
    });
    return;
  }

  functions.logger.info("membersDirectoryCache: atualizado", {
    tenantId: tid,
    entries: entries.length,
    totalCount: resolvedTotal,
    ativos: summary.ativos,
    ticket,
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
      // Sem orderBy — docs legados sem `updatedAt` entravam no count() mas não na lista (46 vs 62).
      const membrosSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .limit(DIRECTORY_MAX)
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
