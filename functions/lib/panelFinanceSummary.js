"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onChurchFinanceWritePanelSummary = void 0;
exports.recomputePanelFinanceSummary = recomputePanelFinanceSummary;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const churchRootCountersMirror_1 = require("./churchRootCountersMirror");
const panelFinanceAccountsCache_1 = require("./panelFinanceAccountsCache");
/** Alinhado a `ChurchDashboardQueryLimits.financeLedgerSnapshotMax` no Flutter. */
const FINANCE_LEDGER_CAP = 2500;
/** Mínimo entre recomputações completas por igreja (evita N×2500 leituras em rajadas). */
const RECOMPUTE_MIN_INTERVAL_MS = 90000;
const MONTH_KEYS_KEPT = 24;
function toDateMaybe(v) {
    if (v == null)
        return undefined;
    if (v instanceof admin.firestore.Timestamp)
        return v.toDate();
    const any = v;
    if (typeof any.toDate === "function")
        return any.toDate();
    return undefined;
}
/** Espelha `financeLancamentoDate` em `flutter_app/lib/core/finance_saldo_policy.dart`. */
function financeLancamentoDate(data) {
    const raw = data["date"] ?? data["dataCompetencia"] ?? data["createdAt"];
    return toDateMaybe(raw);
}
function parseAmount(data) {
    const raw = data["amount"] ?? data["valor"];
    if (typeof raw === "number" && !Number.isNaN(raw))
        return raw;
    const s = String(raw ?? "")
        .trim()
        .replace(/\./g, "")
        .replace(",", ".");
    const n = parseFloat(s);
    return Number.isFinite(n) ? n : 0;
}
function tipoLower(data) {
    return String(data["type"] ?? data["tipo"] ?? "").toLowerCase();
}
function monthKeyPtBr(d) {
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}`;
}
/**
 * Recalcula resumo leve a partir dos últimos [FINANCE_LEDGER_CAP] lançamentos por `createdAt` desc.
 * Grava em `igrejas/{tenantId}/_panel_cache/finance_summary` (leitura opcional no app; escrita só Admin).
 */
async function recomputePanelFinanceSummary(tenantId) {
    const db = admin.firestore();
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const cacheCol = db.collection("igrejas").doc(tid).collection("_panel_cache");
    const lockRef = cacheCol.doc("_recompute_lock");
    const summaryRef = cacheCol.doc("finance_summary");
    const nowMs = Date.now();
    const lockSnap = await lockRef.get();
    if (lockSnap.exists) {
        const last = lockSnap.data()?.lastRun;
        if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_INTERVAL_MS) {
            return;
        }
    }
    await lockRef.set({ lastRun: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    let snap;
    try {
        snap = await db
            .collection("igrejas")
            .doc(tid)
            .collection("finance")
            .orderBy("createdAt", "desc")
            .limit(FINANCE_LEDGER_CAP)
            .get();
    }
    catch (e) {
        functions.logger.warn("panelFinanceSummary: query finance falhou", { tid, e });
        return;
    }
    const monthTotals = {};
    for (const doc of snap.docs) {
        const data = doc.data();
        const dt = financeLancamentoDate(data);
        if (!dt)
            continue;
        const mk = monthKeyPtBr(dt);
        const tipo = tipoLower(data);
        const v = Math.abs(parseAmount(data));
        if (v <= 0)
            continue;
        let bucket = monthTotals[mk];
        if (!bucket) {
            bucket = { entradas: 0, saidas: 0 };
            monthTotals[mk] = bucket;
        }
        if (tipo.includes("entrada") || tipo.includes("receita")) {
            bucket.entradas += v;
        }
        else if (tipo.includes("saida") || tipo.includes("despesa")) {
            bucket.saidas += v;
        }
    }
    const first = snap.docs[0];
    const lastCreatedRaw = first?.data()?.["createdAt"];
    const lastCreated = lastCreatedRaw instanceof admin.firestore.Timestamp ? lastCreatedRaw : null;
    const monthKeys = Object.keys(monthTotals).sort().reverse().slice(0, MONTH_KEYS_KEPT);
    const monthsTrim = {};
    for (const k of monthKeys) {
        monthsTrim[k] = monthTotals[k];
    }
    const now = new Date();
    const mesReferencia = monthKeyPtBr(now);
    const cur = monthTotals[mesReferencia] ?? { entradas: 0, saidas: 0 };
    let saldoAtual = 0;
    let saldoAnterior = 0;
    for (const [mk, bucket] of Object.entries(monthTotals)) {
        const net = bucket.entradas - bucket.saidas;
        saldoAtual += net;
        if (mk < mesReferencia)
            saldoAnterior += net;
    }
    const aggregates = {
        mesReferencia,
        receitasMes: cur.entradas,
        despesasMes: cur.saidas,
        saldoAtual,
        saldoAnterior,
    };
    await summaryRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        basisCap: FINANCE_LEDGER_CAP,
        basisDocCount: snap.size,
        months: monthsTrim,
        lastLancamentoCreatedAt: lastCreated ?? null,
        schemaVersion: 2,
        ...aggregates,
    }, { merge: false });
    try {
        await (0, churchRootCountersMirror_1.mirrorFinanceAggregatesToRoot)(db.collection("igrejas").doc(tid), aggregates);
    }
    catch (e) {
        functions.logger.warn("panelFinanceSummary: mirror root finance", { tenantId: tid, e });
    }
    try {
        await (0, panelFinanceAccountsCache_1.recomputePanelFinanceAccounts)(tid);
    }
    catch (e) {
        functions.logger.warn("panelFinanceSummary: finance_accounts", { tenantId: tid, e });
    }
    functions.logger.info("panelFinanceSummary: atualizado", {
        tenantId: tid,
        docs: snap.size,
    });
}
/**
 * Trigger: qualquer escrita em `finance` — resumo com throttle por igreja.
 * O painel Flutter continua a usar o stream local; este doc serve cache / futuras otimizações / BI.
 */
exports.onChurchFinanceWritePanelSummary = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/finance/{docId}")
    .onWrite(async (change, context) => {
    const tenantId = context.params.tenantId;
    try {
        await recomputePanelFinanceSummary(tenantId);
    }
    catch (e) {
        functions.logger.error("onChurchFinanceWritePanelSummary", { tenantId, e });
    }
    return null;
});
//# sourceMappingURL=panelFinanceSummary.js.map