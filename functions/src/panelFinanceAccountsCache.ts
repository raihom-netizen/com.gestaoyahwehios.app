import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import { mirrorFinanceAggregatesToRoot } from "./churchRootCountersMirror";

/** Alinhado a `ChurchDashboardQueryLimits.financeLedgerSnapshotMax`. */
const FINANCE_LEDGER_CAP = 2500;

const RECOMPUTE_MIN_INTERVAL_MS = 45_000;

function toDateMaybe(v: unknown): Date | undefined {
  if (v == null) return undefined;
  if (v instanceof admin.firestore.Timestamp) return v.toDate();
  const any = v as { toDate?: () => Date };
  if (typeof any.toDate === "function") return any.toDate();
  return undefined;
}

function financeLancamentoDate(data: Record<string, unknown>): Date | undefined {
  const raw = data["date"] ?? data["dataCompetencia"] ?? data["createdAt"];
  return toDateMaybe(raw);
}

function tipoLower(data: Record<string, unknown>): string {
  return String(data["type"] ?? data["tipo"] ?? "").toLowerCase();
}

function parseAmount(data: Record<string, unknown>): number {
  const raw = data["amount"] ?? data["valor"];
  if (typeof raw === "number" && !Number.isNaN(raw)) return Math.abs(raw);
  const s = String(raw ?? "")
    .trim()
    .replace(/\./g, "")
    .replace(",", ".");
  const n = parseFloat(s);
  return Number.isFinite(n) ? Math.abs(n) : 0;
}

function lancamentoEfetivado(data: Record<string, unknown>): boolean {
  const tipo = tipoLower(data);
  if (tipo === "transferencia") return true;
  if (tipo.includes("entrada") || tipo.includes("receita")) {
    return data["recebimentoConfirmado"] !== false;
  }
  if (tipo.includes("saida") || tipo.includes("despesa")) {
    return data["pagamentoConfirmado"] !== false;
  }
  return true;
}

function contaDestinoReceitaId(data: Record<string, unknown>): string {
  const a = String(data["contaDestinoId"] ?? "").trim();
  if (a) return a;
  return String(data["contaId"] ?? "").trim();
}

function monthKeyPtBr(d: Date): string {
  return `${String(d.getFullYear()).padStart(4, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function endOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
}

/**
 * Saldos por conta + fluxo do mês — `_panel_cache/finance_accounts`.
 * Espelha totais no doc raiz `igrejas/{id}`.
 */
export async function recomputePanelFinanceAccounts(tenantId: string): Promise<void> {
  const db = admin.firestore();
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const churchRef = db.collection("igrejas").doc(tid);
  const cacheCol = churchRef.collection("_panel_cache");
  const lockRef = cacheCol.doc("_finance_accounts_lock");
  const accountsRef = cacheCol.doc("finance_accounts");

  const nowMs = Date.now();
  const lockSnap = await lockRef.get();
  if (lockSnap.exists) {
    const last = lockSnap.data()?.lastRun as admin.firestore.Timestamp | undefined;
    if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_INTERVAL_MS) {
      return;
    }
  }
  await lockRef.set(
    { lastRun: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  let contasSnap: admin.firestore.QuerySnapshot;
  let financeSnap: admin.firestore.QuerySnapshot;
  try {
    [contasSnap, financeSnap] = await Promise.all([
      churchRef.collection("contas").orderBy("nome").get(),
      churchRef
        .collection("finance")
        .orderBy("createdAt", "desc")
        .limit(FINANCE_LEDGER_CAP)
        .get(),
    ]);
  } catch (e) {
    functions.logger.warn("panelFinanceAccountsCache: query falhou", { tid, e });
    return;
  }

  const contaIds = new Set<string>();
  const contasMeta: Record<string, { nome: string; bancoNome?: string; tipoConta?: string }> = {};
  for (const doc of contasSnap.docs) {
    const d = doc.data() as Record<string, unknown>;
    if (d["ativo"] === false) continue;
    contaIds.add(doc.id);
    contasMeta[doc.id] = {
      nome: String(d["nome"] ?? doc.id).trim(),
      bancoNome: String(d["bancoNome"] ?? d["banco"] ?? "").trim() || undefined,
      tipoConta: String(d["tipoConta"] ?? "").trim() || undefined,
    };
  }

  const saldoPorConta: Record<string, number> = {};
  const receitasMes: Record<string, number> = {};
  const despesasMes: Record<string, number> = {};
  for (const id of contaIds) {
    saldoPorConta[id] = 0;
    receitasMes[id] = 0;
    despesasMes[id] = 0;
  }

  const now = new Date();
  const mesStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const mesEnd = endOfMonth(now);
  const ateInclusive = mesEnd;

  for (const doc of financeSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const dt = financeLancamentoDate(data);
    if (!dt) continue;
    const valor = parseAmount(data);
    if (valor <= 0) continue;
    const tipo = tipoLower(data);
    const inMes = dt >= mesStart && dt <= mesEnd;

    if (dt <= ateInclusive && lancamentoEfetivado(data)) {
      if (tipo === "transferencia") {
        const origem = String(data["contaOrigemId"] ?? "").trim();
        const destino = String(data["contaDestinoId"] ?? "").trim();
        if (destino && contaIds.has(destino)) saldoPorConta[destino] += valor;
        if (origem && contaIds.has(origem)) saldoPorConta[origem] -= valor;
      } else if (tipo.includes("entrada") || tipo.includes("receita")) {
        const destino = contaDestinoReceitaId(data);
        if (destino && contaIds.has(destino)) saldoPorConta[destino] += valor;
      } else {
        const origem = String(data["contaOrigemId"] ?? "").trim();
        if (origem && contaIds.has(origem)) saldoPorConta[origem] -= valor;
      }
    }

    if (inMes) {
      if (tipo === "transferencia") {
        const origem = String(data["contaOrigemId"] ?? "").trim();
        const destino = String(data["contaDestinoId"] ?? "").trim();
        if (destino && contaIds.has(destino)) receitasMes[destino] += valor;
        if (origem && contaIds.has(origem)) despesasMes[origem] += valor;
      } else if (tipo.includes("entrada") || tipo.includes("receita")) {
        const destino = contaDestinoReceitaId(data);
        if (destino && contaIds.has(destino)) receitasMes[destino] += valor;
      } else if (tipo.includes("saida") || tipo.includes("despesa")) {
        const origem = String(data["contaOrigemId"] ?? "").trim();
        if (origem && contaIds.has(origem)) despesasMes[origem] += valor;
      }
    }
  }

  let saldoTotal = 0;
  let receitasMesTotal = 0;
  let despesasMesTotal = 0;
  const contasOut: Record<string, unknown>[] = [];
  for (const id of contaIds) {
    const saldo = saldoPorConta[id] ?? 0;
    const rec = receitasMes[id] ?? 0;
    const des = despesasMes[id] ?? 0;
    saldoTotal += saldo;
    receitasMesTotal += rec;
    despesasMesTotal += des;
    const meta = contasMeta[id];
    contasOut.push({
      contaId: id,
      nome: meta?.nome ?? id,
      bancoNome: meta?.bancoNome ?? "",
      tipoConta: meta?.tipoConta ?? "",
      saldoAtual: saldo,
      receitasMes: rec,
      despesasMes: des,
      fluxoMes: rec - des,
    });
  }
  contasOut.sort((a, b) =>
    String(a["nome"]).localeCompare(String(b["nome"]), "pt-BR"),
  );

  const mesReferencia = monthKeyPtBr(now);
  const payload = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    schemaVersion: 1,
    mesReferencia,
    basisCap: FINANCE_LEDGER_CAP,
    basisDocCount: financeSnap.size,
    saldoTotal,
    receitasMesTotal,
    despesasMesTotal,
    fluxoMesTotal: receitasMesTotal - despesasMesTotal,
    contas: contasOut,
    saldoPorConta,
    receitasMesPorConta: receitasMes,
    despesasMesPorConta: despesasMes,
  };

  await accountsRef.set(payload, { merge: false });

  try {
    await mirrorFinanceAggregatesToRoot(churchRef, {
      mesReferencia,
      saldoAtual: saldoTotal,
      receitasMes: receitasMesTotal,
      despesasMes: despesasMesTotal,
      saldoAnterior: saldoTotal - (receitasMesTotal - despesasMesTotal),
      saldoPorConta,
    });
  } catch (e) {
    functions.logger.warn("panelFinanceAccountsCache: mirror root", { tid, e });
  }

  functions.logger.info("panelFinanceAccountsCache: atualizado", {
    tenantId: tid,
    contas: contaIds.size,
    saldoTotal,
  });
}

/** Recalcula saldos quando contas bancárias mudam. */
export const onChurchContasWriteFinanceAccounts = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/contas/{docId}")
  .onWrite(async (_, context) => {
    const tenantId = context.params.tenantId as string;
    try {
      await recomputePanelFinanceAccounts(tenantId);
    } catch (e) {
      functions.logger.error("onChurchContasWriteFinanceAccounts", { tenantId, e });
    }
    return null;
  });
