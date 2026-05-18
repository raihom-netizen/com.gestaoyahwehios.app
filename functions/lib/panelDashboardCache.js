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
exports.getChurchPanelSnapshot = exports.onChurchPedidoOracaoWritePanelDashboard = exports.onChurchVisitanteWritePanelDashboard = exports.onChurchNoticiaWritePanelDashboard = exports.onChurchAvisoWritePanelDashboard = exports.onChurchMembroWritePanelDashboard = void 0;
exports.recomputePanelDashboardSummary = recomputePanelDashboardSummary;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const RECOMPUTE_MIN_INTERVAL_MS = 45000;
const RECENT_AVISOS = 6;
const RECENT_EVENTOS = 8;
async function safeCount(q) {
    try {
        const agg = await q.count().get();
        return agg.data().count;
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: count falhou", { e });
        return 0;
    }
}
function lightPost(doc, kind) {
    const d = doc.data();
    const title = String(d.title ?? d.titulo ?? d.name ?? "").trim();
    return {
        id: doc.id,
        title: title || (kind === "evento" ? "Evento" : "Aviso"),
        createdAt: d.createdAt ?? null,
        startAt: d.startAt ?? null,
        commentsCount: typeof d.commentsCount === "number" ? d.commentsCount : 0,
        type: String(d.type ?? ""),
    };
}
/**
 * Resumo leve do painel: contadores + últimos avisos/eventos.
 * Grava em `igrejas/{tenantId}/_panel_cache/dashboard_summary`.
 */
async function recomputePanelDashboardSummary(tenantId) {
    const db = admin.firestore();
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const churchRef = db.collection("igrejas").doc(tid);
    const cacheCol = churchRef.collection("_panel_cache");
    const lockRef = cacheCol.doc("_dashboard_recompute_lock");
    const summaryRef = cacheCol.doc("dashboard_summary");
    const nowMs = Date.now();
    const lockSnap = await lockRef.get();
    if (lockSnap.exists) {
        const last = lockSnap.data()?.lastRun;
        if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_INTERVAL_MS) {
            return;
        }
    }
    await lockRef.set({ lastRun: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const membrosCol = churchRef.collection("membros");
    const avisosCol = churchRef.collection("avisos");
    const noticiasCol = churchRef.collection("noticias");
    const [pendingMembers, newVisitors, openPrayers, membersTotal, avisosSnap, eventosSnap, eventosProximosSnap,] = await Promise.all([
        safeCount(membrosCol.where("status", "==", "pendente")),
        safeCount(churchRef.collection("visitantes").where("status", "==", "Novo")),
        safeCount(churchRef.collection("pedidosOracao").where("respondida", "==", false)),
        safeCount(membrosCol),
        avisosCol.orderBy("createdAt", "desc").limit(RECENT_AVISOS).get(),
        noticiasCol.orderBy("startAt", "desc").limit(RECENT_EVENTOS).get(),
        noticiasCol
            .where("type", "==", "evento")
            .orderBy("startAt", "asc")
            .limit(24)
            .get(),
    ]);
    const nowMsEvt = Date.now();
    const upcomingDocs = eventosProximosSnap.docs.filter((d) => {
        const st = d.data().startAt;
        if (st instanceof admin.firestore.Timestamp) {
            return st.toMillis() >= nowMsEvt - 86400000;
        }
        return true;
    }).slice(0, 12);
    await summaryRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        schemaVersion: 1,
        pendingMembersCount: pendingMembers,
        newVisitorsCount: newVisitors,
        openPrayerRequestsCount: openPrayers,
        membersTotalCount: membersTotal,
        recentAvisos: avisosSnap.docs.map((d) => lightPost(d, "aviso")),
        recentEventos: eventosSnap.docs.map((d) => lightPost(d, "evento")),
        upcomingEventos: upcomingDocs.map((d) => lightPost(d, "evento")),
    }, { merge: false });
    functions.logger.info("panelDashboardCache: atualizado", {
        tenantId: tid,
        pendingMembers,
        membersTotal,
    });
}
function scheduleRecompute(tenantId) {
    recomputePanelDashboardSummary(tenantId).catch((e) => {
        functions.logger.error("panelDashboardCache: recompute", { tenantId, e });
    });
}
const dashboardTrigger = (path) => functions
    .region("us-central1")
    .firestore.document(path)
    .onWrite((_, context) => {
    scheduleRecompute(context.params.tenantId);
    return null;
});
exports.onChurchMembroWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/membros/{docId}");
exports.onChurchAvisoWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/avisos/{docId}");
exports.onChurchNoticiaWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/noticias/{docId}");
exports.onChurchVisitanteWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/visitantes/{docId}");
exports.onChurchPedidoOracaoWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/pedidosOracao/{docId}");
/** Leitura rápida do painel (1 round-trip). Recalcula se o cache estiver ausente ou velho. */
exports.getChurchPanelSnapshot = functions
    .region("us-central1")
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const claims = (token.customClaims || {});
    const tenantId = String(claims.igrejaId || claims.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const db = admin.firestore();
    const summaryRef = db
        .collection("igrejas")
        .doc(tenantId)
        .collection("_panel_cache")
        .doc("dashboard_summary");
    const snap = await summaryRef.get();
    const staleMs = 8 * 60 * 1000;
    let data = snap.data();
    const updated = data?.updatedAt;
    const isStale = !snap.exists ||
        !updated ||
        Date.now() - updated.toMillis() > staleMs;
    if (isStale) {
        await recomputePanelDashboardSummary(tenantId);
        data = (await summaryRef.get()).data();
    }
    return { ok: true, tenantId, summary: data ?? {} };
});
//# sourceMappingURL=panelDashboardCache.js.map