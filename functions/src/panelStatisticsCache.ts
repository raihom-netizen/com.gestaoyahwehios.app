import * as admin from "firebase-admin";

/** Entrada agregada — gravada em `_panel_cache/statistics_summary`. */
export type PanelStatisticsInput = {
  membersTotalCount: number;
  activeMembersCount: number;
  pendingMembersCount: number;
  newVisitorsCount: number;
  openPrayerRequestsCount: number;
  birthdaysTodayCount: number;
  birthdaysWeekCount: number;
  birthdaysMonthCount: number;
  avisosCount: number;
  eventsCount: number;
  upcomingEventsCount: number;
  departmentsCount: number;
};

/**
 * Estatísticas consolidadas do painel — 1 leitura para KPIs / relatórios / dashboard_stats.
 * Espelha também `dashboard_stats/summary` (compatibilidade Flutter legado).
 */
export async function writePanelStatisticsCache(
  tenantId: string,
  input: PanelStatisticsInput,
): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const db = admin.firestore();
  const churchRef = db.collection("igrejas").doc(tid);
  const cacheCol = churchRef.collection("_panel_cache");
  const ts = admin.firestore.FieldValue.serverTimestamp();

  const eventosTotal = input.eventsCount + input.upcomingEventsCount;

  const payload: Record<string, unknown> = {
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

  await churchRef.collection("dashboard_stats").doc("summary").set(
    {
      members: input.membersTotalCount,
      avisos: input.avisosCount,
      eventos: eventosTotal,
      updatedAt: ts,
      source: "_panel_cache/statistics_summary",
    },
    { merge: true },
  );

  await churchRef.collection("dashboard").doc("home").set(
    {
      members: input.membersTotalCount,
      avisos: input.avisosCount,
      eventos: eventosTotal,
      updatedAt: ts,
      source: "_panel_cache/statistics_summary",
    },
    { merge: true },
  );
}
