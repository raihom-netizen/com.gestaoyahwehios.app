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
exports.scheduledFinanceVencimento24h = exports.scheduledFinanceDailyDigest = void 0;
/**
 * Lembretes push (FCM) de contas a pagar / a receber no Financeiro.
 * Destinatários: pastor, admin, gestor, tesoureiro (tópico `gypush_{tenant}_financeiro`).
 *
 * - 7h (SP): resumo do dia (vencimentos hoje + em atraso).
 * - A cada 10 min: janela ~24h antes do vencimento (item a item, deduplicado).
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const pushNovoConteudo_1 = require("./pushNovoConteudo");
const notificationBranding_1 = require("./notificationBranding");
const db = admin.firestore();
const TZ_BR = "America/Sao_Paulo";
const MS_24H = 24 * 60 * 60 * 1000;
const WINDOW_MS = 14 * 60 * 1000;
function financeTipoLower(d) {
    return String(d.type || d.tipo || "").toLowerCase();
}
function isPendingPagamento(d) {
    const tipo = financeTipoLower(d);
    if (tipo === "transferencia")
        return false;
    if (tipo.includes("saida") || tipo.includes("despesa")) {
        return d.pagamentoConfirmado === false;
    }
    return false;
}
function isPendingRecebimento(d) {
    const tipo = financeTipoLower(d);
    if (tipo === "transferencia")
        return false;
    if (tipo.includes("entrada") || tipo.includes("receita")) {
        return d.recebimentoConfirmado === false;
    }
    return false;
}
function financeLancamentoDate(d) {
    const raw = d.date ?? d.dataCompetencia ?? d.createdAt;
    if (!raw)
        return null;
    if (typeof raw.toDate === "function") {
        return raw.toDate();
    }
    return null;
}
function ymdInTz(d, tz) {
    return d.toLocaleDateString("en-CA", { timeZone: tz });
}
function clip(s, max) {
    const t = String(s || "").trim();
    if (t.length <= max)
        return t;
    return `${t.slice(0, Math.max(0, max - 3))}...`;
}
function lancamentoTitulo(d) {
    return clip(String(d.descricao || d.description || d.categoria || d.title || "Lançamento"), 72);
}
/** Resumo diário 7h — vencimentos de hoje e itens em atraso (pendentes). */
exports.scheduledFinanceDailyDigest = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .pubsub.schedule("0 7 * * *")
    .timeZone(TZ_BR)
    .onRun(async () => {
    const now = new Date();
    const todayYmd = ymdInTz(now, TZ_BR);
    const igrejasSnap = await db.collection("igrejas").get();
    let sent = 0;
    for (const church of igrejasSnap.docs) {
        const tenantId = church.id;
        try {
            const stateRef = db
                .collection("igrejas")
                .doc(tenantId)
                .collection("internal_notif_state")
                .doc("finance_daily_digest");
            const st = await stateRef.get();
            if (String(st.data()?.lastSentYmd || "").trim() === todayYmd)
                continue;
            const finCol = db.collection("igrejas").doc(tenantId).collection("finance");
            let lastDoc = null;
            let pagarHoje = 0;
            let receberHoje = 0;
            let pagarAtraso = 0;
            let receberAtraso = 0;
            for (;;) {
                const base = finCol.orderBy(admin.firestore.FieldPath.documentId()).limit(400);
                const snap = lastDoc ? await base.startAfter(lastDoc).get() : await base.get();
                if (snap.empty)
                    break;
                for (const doc of snap.docs) {
                    const d = doc.data();
                    const dt = financeLancamentoDate(d);
                    if (!dt)
                        continue;
                    const ymd = ymdInTz(dt, TZ_BR);
                    const isToday = ymd === todayYmd;
                    const isPast = ymd < todayYmd;
                    if (isPendingPagamento(d)) {
                        if (isToday)
                            pagarHoje += 1;
                        else if (isPast)
                            pagarAtraso += 1;
                    }
                    if (isPendingRecebimento(d)) {
                        if (isToday)
                            receberHoje += 1;
                        else if (isPast)
                            receberAtraso += 1;
                    }
                }
                lastDoc = snap.docs[snap.docs.length - 1];
                if (snap.docs.length < 400)
                    break;
            }
            const total = pagarHoje + receberHoje + pagarAtraso + receberAtraso;
            if (total === 0) {
                await stateRef.set({ lastSentYmd: todayYmd, skippedEmpty: true }, { merge: true });
                continue;
            }
            const parts = [];
            if (pagarHoje > 0)
                parts.push(`${pagarHoje} a pagar hoje`);
            if (receberHoje > 0)
                parts.push(`${receberHoje} a receber hoje`);
            if (pagarAtraso > 0)
                parts.push(`${pagarAtraso} a pagar em atraso`);
            if (receberAtraso > 0)
                parts.push(`${receberAtraso} a receber em atraso`);
            const body = clip(parts.join(" · "), 180);
            await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
                topic: (0, pushNovoConteudo_1.topicPushNovo)(tenantId, "financeiro"),
                title: "💰 Financeiro — vencimentos",
                body,
                data: {
                    type: "financeiro_vencimento_digest",
                    tenantId,
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                module: "financeiro",
            }));
            await db.collection("igrejas").doc(tenantId).collection("notificacoes").add({
                type: "financeiro_vencimento_digest",
                title: "Financeiro — vencimentos",
                body,
                pagarHoje,
                receberHoje,
                pagarAtraso,
                receberAtraso,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            await stateRef.set({ lastSentYmd: todayYmd, sentAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            sent += 1;
        }
        catch (e) {
            functions.logger.error("scheduledFinanceDailyDigest", { tenantId, e });
        }
    }
    functions.logger.info("scheduledFinanceDailyDigest done", { todayYmd, sent });
    return null;
});
/** ~24h antes do vencimento — push item a item (deduplicado por doc). */
exports.scheduledFinanceVencimento24h = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .pubsub.schedule("every 10 minutes")
    .timeZone(TZ_BR)
    .onRun(async () => {
    const now = Date.now();
    const horizon = now + 50 * 60 * 60 * 1000;
    const igrejasSnap = await db.collection("igrejas").get();
    let sentPay = 0;
    let sentRec = 0;
    for (const church of igrejasSnap.docs) {
        const tenantId = church.id;
        const finCol = db.collection("igrejas").doc(tenantId).collection("finance");
        let q;
        try {
            q = await finCol
                .where("date", ">=", admin.firestore.Timestamp.fromMillis(now))
                .where("date", "<=", admin.firestore.Timestamp.fromMillis(horizon))
                .get();
        }
        catch (e) {
            functions.logger.warn("financeVencimento24h query", { tenantId, e });
            continue;
        }
        for (const doc of q.docs) {
            const d = doc.data();
            const ts = d.date;
            if (!ts || typeof ts.toMillis !== "function")
                continue;
            const diffMs = ts.toMillis() - now;
            if (diffMs <= 0)
                continue;
            if (diffMs < MS_24H - WINDOW_MS || diffMs > MS_24H + WINDOW_MS)
                continue;
            const titulo = lancamentoTitulo(d);
            const isPay = isPendingPagamento(d);
            const isRec = isPendingRecebimento(d);
            if (!isPay && !isRec)
                continue;
            const sentField = isPay ? "pushVencimento24hPagarSentAt" : "pushVencimento24hReceberSentAt";
            if (d[sentField])
                continue;
            try {
                await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
                    topic: (0, pushNovoConteudo_1.topicPushNovo)(tenantId, "financeiro"),
                    title: isPay ? "💸 Conta a pagar — 24h" : "💵 Conta a receber — 24h",
                    body: clip(`${titulo} vence amanhã.`, 160),
                    data: {
                        type: "financeiro_vencimento_24h",
                        tenantId,
                        financeId: doc.id,
                        kind: isPay ? "pagar" : "receber",
                        click_action: "FLUTTER_NOTIFICATION_CLICK",
                    },
                    module: "financeiro",
                }));
                await doc.ref.update({
                    [sentField]: admin.firestore.FieldValue.serverTimestamp(),
                });
                if (isPay)
                    sentPay += 1;
                else
                    sentRec += 1;
            }
            catch (e) {
                functions.logger.error("financeVencimento24h FCM", { tenantId, id: doc.id, e });
            }
        }
    }
    functions.logger.info("scheduledFinanceVencimento24h done", { sentPay, sentRec });
    return null;
});
//# sourceMappingURL=financeVencimentoReminders.js.map