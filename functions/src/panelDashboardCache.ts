import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const RECOMPUTE_MIN_INTERVAL_MS = 45_000;
const RECENT_AVISOS = 6;
const RECENT_EVENTOS = 8;

async function safeCount(q: admin.firestore.Query): Promise<number> {
  try {
    const agg = await q.count().get();
    return agg.data().count;
  } catch (e) {
    functions.logger.warn("panelDashboardCache: count falhou", { e });
    return 0;
  }
}

function lightPost(
  doc: admin.firestore.QueryDocumentSnapshot,
  kind: "aviso" | "evento",
): Record<string, unknown> {
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
export async function recomputePanelDashboardSummary(tenantId: string): Promise<void> {
  const db = admin.firestore();
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const churchRef = db.collection("igrejas").doc(tid);
  const cacheCol = churchRef.collection("_panel_cache");
  const lockRef = cacheCol.doc("_dashboard_recompute_lock");
  const summaryRef = cacheCol.doc("dashboard_summary");

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

  const membrosCol = churchRef.collection("membros");
  const avisosCol = churchRef.collection("avisos");
  const noticiasCol = churchRef.collection("noticias");

  const [
    pendingMembers,
    newVisitors,
    openPrayers,
    membersTotal,
    avisosSnap,
    eventosSnap,
    eventosProximosSnap,
  ] = await Promise.all([
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
      return st.toMillis() >= nowMsEvt - 86_400_000;
    }
    return true;
  }).slice(0, 12);

  await summaryRef.set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      schemaVersion: 1,
      pendingMembersCount: pendingMembers,
      newVisitorsCount: newVisitors,
      openPrayerRequestsCount: openPrayers,
      membersTotalCount: membersTotal,
      recentAvisos: avisosSnap.docs.map((d) => lightPost(d, "aviso")),
      recentEventos: eventosSnap.docs.map((d) => lightPost(d, "evento")),
      upcomingEventos: upcomingDocs.map((d) => lightPost(d, "evento")),
    },
    { merge: false },
  );

  functions.logger.info("panelDashboardCache: atualizado", {
    tenantId: tid,
    pendingMembers,
    membersTotal,
  });
}

function scheduleRecompute(tenantId: string) {
  recomputePanelDashboardSummary(tenantId).catch((e) => {
    functions.logger.error("panelDashboardCache: recompute", { tenantId, e });
  });
}

const dashboardTrigger = (path: string) =>
  functions
    .region("us-central1")
    .firestore.document(path)
    .onWrite((_, context) => {
      scheduleRecompute(context.params.tenantId as string);
      return null;
    });

export const onChurchMembroWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/membros/{docId}",
);
export const onChurchAvisoWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/avisos/{docId}",
);
export const onChurchNoticiaWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/noticias/{docId}",
);
export const onChurchVisitanteWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/visitantes/{docId}",
);
export const onChurchPedidoOracaoWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/pedidosOracao/{docId}",
);

/** Leitura rápida do painel (1 round-trip). Recalcula se o cache estiver ausente ou velho. */
export const getChurchPanelSnapshot = functions
  .region("us-central1")
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const claims = (token.customClaims || {}) as Record<string, unknown>;
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
    const updated = data?.updatedAt as admin.firestore.Timestamp | undefined;
    const isStale =
      !snap.exists ||
      !updated ||
      Date.now() - updated.toMillis() > staleMs;

    if (isStale) {
      await recomputePanelDashboardSummary(tenantId);
      data = (await summaryRef.get()).data();
    }

    return { ok: true, tenantId, summary: data ?? {} };
  });
