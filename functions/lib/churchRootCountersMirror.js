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
exports.mirrorChurchCountersToRoot = mirrorChurchCountersToRoot;
exports.mirrorDashboardCacheAlias = mirrorDashboardCacheAlias;
exports.mirrorFinanceAggregatesToRoot = mirrorFinanceAggregatesToRoot;
const admin = __importStar(require("firebase-admin"));
/**
 * Espelha contadores no doc raiz — evita scan de coleções no cliente.
 * Chamado após atualizar `_panel_cache/dashboard_summary` e `finance_summary`.
 */
async function mirrorChurchCountersToRoot(churchRef, counters, extra) {
    const ts = admin.firestore.FieldValue.serverTimestamp();
    await churchRef.set({
        membersCount: counters.membersCount,
        membersTotalCount: counters.membersTotalCount,
        activeMembersCount: counters.activeMembersCount,
        eventsCount: counters.eventsCount,
        avisosCount: counters.avisosCount,
        departmentsCount: counters.departmentsCount,
        pendingMembersCount: counters.pendingMembersCount ?? 0,
        newVisitorsCount: counters.newVisitorsCount ?? 0,
        openPrayerRequestsCount: counters.openPrayerRequestsCount ?? 0,
        birthdaysTodayCount: counters.birthdaysTodayCount ?? 0,
        upcomingEventsCount: counters.upcomingEventsCount ?? 0,
        countersUpdatedAt: ts,
        dashboardAggregates: {
            membersTotalCount: counters.membersTotalCount,
            activeMembersCount: counters.activeMembersCount,
            pendingMembersCount: counters.pendingMembersCount ?? 0,
            newVisitorsCount: counters.newVisitorsCount ?? 0,
            openPrayerRequestsCount: counters.openPrayerRequestsCount ?? 0,
            birthdaysTodayCount: counters.birthdaysTodayCount ?? 0,
            upcomingEventsCount: counters.upcomingEventsCount ?? 0,
            eventsCount: counters.eventsCount,
            avisosCount: counters.avisosCount,
            departmentsCount: counters.departmentsCount,
            updatedAt: ts,
        },
        ...extra,
    }, { merge: true });
}
/** Alias spec: `_panel_cache/dashboard` (mesmo payload que `dashboard_summary`). */
async function mirrorDashboardCacheAlias(cacheCol, summaryData) {
    await cacheCol.doc("dashboard").set(summaryData, { merge: false });
}
/** Financeiro pré-calculado no doc raiz (complementa `financeAggregates` da CF finance). */
async function mirrorFinanceAggregatesToRoot(churchRef, aggregates) {
    await churchRef.set({
        financeAggregates: aggregates,
        financeAggregatesUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        receitasMes: aggregates.receitasMes ?? 0,
        despesasMes: aggregates.despesasMes ?? 0,
        saldoAtual: aggregates.saldoAtual ?? 0,
        saldoAnterior: aggregates.saldoAnterior ?? 0,
        mesReferencia: aggregates.mesReferencia ?? "",
    }, { merge: true });
}
//# sourceMappingURL=churchRootCountersMirror.js.map