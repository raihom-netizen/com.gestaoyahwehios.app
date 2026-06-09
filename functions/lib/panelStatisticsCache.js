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
exports.writePanelStatisticsCache = writePanelStatisticsCache;
const admin = __importStar(require("firebase-admin"));
/**
 * Estatísticas consolidadas do painel — 1 leitura para KPIs / relatórios / dashboard_stats.
 * Espelha também `dashboard_stats/summary` (compatibilidade Flutter legado).
 */
async function writePanelStatisticsCache(tenantId, input) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tid);
    const cacheCol = churchRef.collection("_panel_cache");
    const ts = admin.firestore.FieldValue.serverTimestamp();
    const eventosTotal = input.eventsCount + input.upcomingEventsCount;
    const payload = {
        schemaVersion: 1,
        updatedAt: ts,
        membersTotalCount: input.membersTotalCount,
        activeMembersCount: input.activeMembersCount,
        pendingMembersCount: input.pendingMembersCount,
        newVisitorsCount: input.newVisitorsCount,
        openPrayerRequestsCount: input.openPrayerRequestsCount,
        birthdaysTodayCount: input.birthdaysTodayCount,
        birthdaysWeekCount: input.birthdaysWeekCount,
        birthdaysMonthCount: input.birthdaysMonthCount,
        avisosCount: input.avisosCount,
        eventsCount: input.eventsCount,
        upcomingEventsCount: input.upcomingEventsCount,
        departmentsCount: input.departmentsCount,
        // aliases legados (dashboard_stats / UI)
        members: input.membersTotalCount,
        membros: input.membersTotalCount,
        avisos: input.avisosCount,
        eventos: eventosTotal,
        visitantes: input.newVisitorsCount,
        pedidosOracao: input.openPrayerRequestsCount,
        departamentos: input.departmentsCount,
    };
    await cacheCol.doc("statistics_summary").set(payload, { merge: false });
    await churchRef.collection("dashboard_stats").doc("summary").set({
        members: input.membersTotalCount,
        avisos: input.avisosCount,
        eventos: eventosTotal,
        updatedAt: ts,
        source: "_panel_cache/statistics_summary",
    }, { merge: true });
    await churchRef.collection("dashboard").doc("home").set({
        members: input.membersTotalCount,
        avisos: input.avisosCount,
        eventos: eventosTotal,
        updatedAt: ts,
        source: "_panel_cache/statistics_summary",
    }, { merge: true });
}
//# sourceMappingURL=panelStatisticsCache.js.map