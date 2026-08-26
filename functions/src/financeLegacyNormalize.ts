import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Normaliza lançamentos antigos de `igrejas/{tenantId}/finance`.
 *
 * Doações do Mercado Pago e receitas recorrentes eram gravadas só em português
 * (`tipo: "entrada"`, `descricao`, `categoria`) e, no caso das recorrentes, sem
 * nenhum campo de data. O módulo Financeiro consulta o período por
 * `date`/`effectiveDate`/`paidAt` e compara `type` com "income"/"expense" — por
 * isso esses lançamentos existiam no banco mas não apareciam na tela (ou eram
 * somados como despesa). A gravação já foi corrigida na origem; esta callable
 * conserta o que ficou para trás.
 */

function fs(): admin.firestore.Firestore {
  return admin.firestore();
}

const MANAGER_ROLES = [
  "MASTER",
  "ADMIN",
  "ADM",
  "GESTOR",
  "PASTOR",
  "PASTORA",
  "PASTOR_PRESIDENTE",
  "PASTOR_AUXILIAR",
  "TESOUREIRO",
  "TESOURARIA",
];

async function callerCanNormalize(
  uid: string,
  tokenRole: unknown,
  tokenTenantId: unknown,
  tenantId: string,
): Promise<boolean> {
  let role = String(tokenRole || "").trim().toUpperCase();
  if (!role) {
    try {
      const u = await fs().collection("users").doc(uid).get();
      const d = u.exists ? u.data() || {} : {};
      role = String(d.role ?? d.nivel ?? d.perfil ?? "").trim().toUpperCase();
    } catch {
      role = "";
    }
  }
  if (["MASTER", "ADMIN", "ADM"].includes(role)) return true;
  if (!MANAGER_ROLES.includes(role)) return false;
  const tokenTenant = String(tokenTenantId || "").trim();
  if (tokenTenant && tokenTenant === tenantId) return true;
  try {
    const u = await fs().collection("users").doc(uid).get();
    const d = u.exists ? u.data() || {} : {};
    const userTenant = String(d.tenantId || d.igrejaId || "").trim();
    return !!userTenant && userTenant === tenantId;
  } catch {
    return false;
  }
}

function normalizedType(d: Record<string, unknown>): "income" | "expense" | null {
  const raw = String(d.type ?? d.tipo ?? "").trim().toLowerCase();
  if (raw === "income" || raw === "expense") return raw;
  if (raw.includes("entrada") || raw.includes("receita")) return "income";
  if (raw.includes("saida") || raw.includes("saída") || raw.includes("despesa")) {
    return "expense";
  }
  if (raw === "transferencia" || raw === "transferência") return null;
  const origem = String(d.contaOrigemId ?? "").trim();
  const destino = String(d.contaDestinoId ?? d.contaId ?? "").trim();
  if (destino && !origem) return "income";
  if (origem && !destino) return "expense";
  return null;
}

function toTimestamp(v: unknown): admin.firestore.Timestamp | null {
  if (v instanceof admin.firestore.Timestamp) return v;
  const maybe = v as { toDate?: () => Date } | null;
  if (maybe && typeof maybe.toDate === "function") {
    try {
      return admin.firestore.Timestamp.fromDate(maybe.toDate());
    } catch {
      return null;
    }
  }
  if (v instanceof Date) return admin.firestore.Timestamp.fromDate(v);
  return null;
}

/** `2026-08` → 01/08/2026 (competência das recorrentes). */
function timestampFromCompetencia(v: unknown): admin.firestore.Timestamp | null {
  const raw = String(v ?? "").trim();
  const m = /^(\d{4})-(\d{2})$/.exec(raw);
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  if (!year || month < 1 || month > 12) return null;
  return admin.firestore.Timestamp.fromDate(new Date(year, month - 1, 1));
}

function numberOrNull(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v.replace(",", "."));
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/** Campos em falta para o doc aparecer e somar certo no Financeiro. */
export function buildFinanceNormalizationPatch(
  d: Record<string, unknown>,
): Record<string, unknown> {
  const patch: Record<string, unknown> = {};

  const type = normalizedType(d);
  const currentType = String(d.type ?? "").trim();
  if (type && currentType !== type) {
    patch.type = type;
    if (!String(d.tipo ?? "").trim()) {
      patch.tipo = type === "income" ? "entrada" : "saida";
    }
  }

  if (numberOrNull(d.amount) == null) {
    const valor = numberOrNull(d.valor);
    if (valor != null) patch.amount = valor;
  }

  const descricao = String(d.descricao ?? "").trim();
  if (!String(d.description ?? "").trim() && descricao) {
    patch.description = descricao;
  }
  const categoria = String(d.categoria ?? "").trim();
  if (!String(d.category ?? "").trim() && categoria) {
    patch.category = categoria;
  }

  if (!String(d.status ?? "").trim()) {
    const pendente =
      d.pendenteConciliacaoRecorrencia === true ||
      d.recebimentoConfirmado === false ||
      d.pagamentoConfirmado === false;
    patch.status = pendente ? "pending" : "paid";
  }

  const date =
    toTimestamp(d.date) ??
    toTimestamp(d.dataCompetencia) ??
    timestampFromCompetencia(d.competencia) ??
    toTimestamp(d.createdAt);
  if (!toTimestamp(d.date) && date) patch.date = date;

  const paidAt = toTimestamp(d.paidAt);
  if (!toTimestamp(d.effectiveDate)) {
    const effective = paidAt ?? date;
    if (effective) patch.effectiveDate = effective;
  }

  if (!String(d.financeAccountId ?? "").trim()) {
    const conta =
      type === "expense"
        ? String(d.contaOrigemId ?? d.contaId ?? "").trim()
        : String(d.contaDestinoId ?? d.contaId ?? "").trim();
    if (conta) patch.financeAccountId = conta;
  }

  // Vínculo do extrato por membro (recorrentes gravavam só `memberDocId`).
  const memberDocId = String(d.memberDocId ?? "").trim();
  if (memberDocId) {
    if (!String(d.membroId ?? "").trim()) patch.membroId = memberDocId;
    if (!String(d.memberId ?? "").trim()) patch.memberId = memberDocId;
    const memberNome = String(d.memberNome ?? "").trim();
    if (memberNome && !String(d.membroNome ?? "").trim()) {
      patch.membroNome = memberNome;
    }
  }

  return patch;
}

export const normalizeChurchFinanceLancamentos = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "tenantId é obrigatório.",
      );
    }
    const token = context.auth.token as Record<string, unknown>;
    const allowed = await callerCanNormalize(
      context.auth.uid,
      token?.role,
      token?.igrejaId ?? token?.tenantId,
      tenantId,
    );
    if (!allowed) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Sem permissão para normalizar o financeiro desta igreja.",
      );
    }

    const dryRun = data?.dryRun === true;
    const limit = Math.min(Math.max(Number(data?.limit || 500), 1), 2000);
    const startAfter = String(data?.startAfter || "").trim();

    const col = fs().collection("igrejas").doc(tenantId).collection("finance");
    let query = col.orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
    if (startAfter) query = query.startAfter(startAfter);

    const snap = await query.get();
    let updated = 0;
    let batch = fs().batch();
    let pending = 0;
    for (const doc of snap.docs) {
      const patch = buildFinanceNormalizationPatch(
        (doc.data() || {}) as Record<string, unknown>,
      );
      if (Object.keys(patch).length === 0) continue;
      updated++;
      if (dryRun) continue;
      batch.set(doc.ref, patch, { merge: true });
      pending++;
      if (pending >= 400) {
        await batch.commit();
        batch = fs().batch();
        pending = 0;
      }
    }
    if (!dryRun && pending > 0) await batch.commit();

    const last = snap.docs.length ? snap.docs[snap.docs.length - 1].id : "";
    return {
      ok: true,
      tenantId,
      scanned: snap.docs.length,
      updated,
      dryRun,
      // Repetir a chamada com este cursor até `done: true`.
      nextCursor: snap.docs.length === limit ? last : "",
      done: snap.docs.length < limit,
    };
  });
