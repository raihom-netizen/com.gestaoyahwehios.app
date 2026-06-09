import * as admin from "firebase-admin";

/** Contadores espelhados no doc raiz `igrejas/{churchId}` (leitura instantânea no app). */
export type ChurchRootCountersPayload = {
  membersCount: number;
  membersTotalCount: number;
  activeMembersCount: number;
  eventsCount: number;
  avisosCount: number;
  departmentsCount: number;
  pendingMembersCount?: number;
  newVisitorsCount?: number;
  openPrayerRequestsCount?: number;
  birthdaysTodayCount?: number;
  upcomingEventsCount?: number;
};

/**
 * Espelha contadores no doc raiz — evita scan de coleções no cliente.
 * Chamado após atualizar `_panel_cache/dashboard_summary` e `finance_summary`.
 */
export async function mirrorChurchCountersToRoot(
  churchRef: admin.firestore.DocumentReference,
  counters: ChurchRootCountersPayload,
  extra?: Record<string, unknown>,
): Promise<void> {
  const ts = admin.firestore.FieldValue.serverTimestamp();
  await churchRef.set(
    {
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
    },
    { merge: true },
  );
}

/** Alias spec: `_panel_cache/dashboard` (mesmo payload que `dashboard_summary`). */
export async function mirrorDashboardCacheAlias(
  cacheCol: admin.firestore.CollectionReference,
  summaryData: Record<string, unknown>,
): Promise<void> {
  await cacheCol.doc("dashboard").set(summaryData, { merge: false });
}

/** Financeiro pré-calculado no doc raiz (complementa `financeAggregates` da CF finance). */
export async function mirrorFinanceAggregatesToRoot(
  churchRef: admin.firestore.DocumentReference,
  aggregates: Record<string, unknown>,
): Promise<void> {
  await churchRef.set(
    {
      financeAggregates: aggregates,
      financeAggregatesUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      receitasMes: aggregates.receitasMes ?? 0,
      despesasMes: aggregates.despesasMes ?? 0,
      saldoAtual: aggregates.saldoAtual ?? 0,
      saldoAnterior: aggregates.saldoAnterior ?? 0,
      mesReferencia: aggregates.mesReferencia ?? "",
    },
    { merge: true },
  );
}
