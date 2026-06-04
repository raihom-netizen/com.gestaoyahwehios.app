import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { isPlatformOperatorToken } from "./masterPlatformAuth";

const RECOMPUTE_MIN_INTERVAL_MS = 60_000;
const STALE_MS = 15 * 60 * 1000;
const IGREJAS_SCAN = 500;
const USERS_SAMPLE = 400;

function isMasterCaller(token: Record<string, unknown> | undefined): boolean {
  return isPlatformOperatorToken(token);
}

function parseDate(v: unknown): Date | null {
  if (v == null) return null;
  if (v instanceof admin.firestore.Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "object" && v !== null) {
    const o = v as Record<string, unknown>;
    const sec = o.seconds ?? o._seconds;
    if (typeof sec === "number") return new Date(sec * 1000);
  }
  const t = Date.parse(String(v));
  return Number.isNaN(t) ? null : new Date(t);
}

function monthKey(dt: Date): string {
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(key: string): string {
  const parts = key.split("-");
  const y = parts[0] ?? "";
  const m = parts[1] ?? "01";
  return `${m}/${y.length >= 4 ? y.substring(2) : y}`;
}

function last12MonthKeys(): string[] {
  const now = new Date();
  const keys: string[] = [];
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    keys.push(monthKey(d));
  }
  return keys;
}

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function churchIsBlocked(data: Record<string, unknown>): boolean {
  if (data.adminBlocked === true) return true;
  const lic = data.license;
  if (lic && typeof lic === "object") {
    const l = lic as Record<string, unknown>;
    if (l.adminBlocked === true || l.blocked === true) return true;
  }
  return false;
}

function churchIsFree(data: Record<string, unknown>): boolean {
  const plan = pickString(data, ["plano", "planId", "plan"]).toLowerCase();
  if (plan === "free") return true;
  if (data.isFree === true) return true;
  const lic = data.license;
  if (lic && typeof lic === "object") {
    const l = lic as Record<string, unknown>;
    if (l.isFree === true) return true;
  }
  return false;
}

function licenseActive(data: Record<string, unknown>): boolean {
  const lic = data.license;
  if (lic && typeof lic === "object") {
    const l = lic as Record<string, unknown>;
    if (l.active === true || l.status === "active") return true;
  }
  return false;
}

function vencimentoFromChurch(data: Record<string, unknown>): Date | null {
  const lic = data.license;
  let licUntil: unknown;
  if (lic && typeof lic === "object") {
    const l = lic as Record<string, unknown>;
    licUntil = l.validUntil ?? l.valid_until;
  }
  return parseDate(data.dataVencimento ?? data.vencimento ?? licUntil);
}

async function safeCount(q: admin.firestore.Query): Promise<number> {
  try {
    const agg = await q.count().get();
    return agg.data().count;
  } catch {
    return 0;
  }
}

export async function recomputeMasterDashboardSummary(): Promise<void> {
  const db = admin.firestore();
  const lockRef = db.collection("config").doc("_master_dashboard_lock");
  const summaryRef = db.collection("config").doc("master_dashboard_summary");

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

  const mesesKeys = last12MonthKeys();
  const byMonthIgrejas: Record<string, number> = {};
  const byMonthUsuarios: Record<string, number> = {};
  const byMonthReceita: Record<string, number> = {};
  for (const k of mesesKeys) {
    byMonthIgrejas[k] = 0;
    byMonthUsuarios[k] = 0;
    byMonthReceita[k] = 0;
  }

  let igrejas = 0;
  let usuarios = 0;
  let membrosTotal = 0;
  let alertas = 0;
  let licencasAtivas = 0;
  let venc7 = 0;
  let venc30 = 0;
  let blocked = 0;
  let freeCount = 0;
  let panelStale = 0;
  let receita = 0;
  let receitaPix = 0;
  let receitaCartao = 0;
  let suggestionsPending = 0;

  const now = new Date();
  const in7 = new Date(now.getTime() + 7 * 86400000);
  const in30 = new Date(now.getTime() + 30 * 86400000);
  const expiringChurches: Record<string, unknown>[] = [];

  const [igCount, userCount, alertSnap, paySnap, sugSnap] = await Promise.all([
    safeCount(db.collection("igrejas")),
    safeCount(db.collection("users")),
    db.collection("alertas").limit(250).get(),
    db
      .collection("pagamentos")
      .where("status", "in", ["approved", "paid", "accredited"])
      .limit(500)
      .get(),
    db.collection("suggestions").limit(300).get(),
  ]);

  igrejas = igCount;
  usuarios = userCount;

  alertas = alertSnap.docs.filter((d) => {
    const data = d.data();
    return data.lido !== true && data.read !== true;
  }).length;

  suggestionsPending = sugSnap.docs.filter((d) => {
    const st = String(d.data().status ?? "pendente").toLowerCase();
    return st !== "respondido" && st !== "resolved";
  }).length;

  for (const d of paySnap.docs) {
    const data = d.data();
    const amt = data.amount ?? data.valor ?? 0;
    const val = typeof amt === "number" ? amt : parseFloat(String(amt)) || 0;
    receita += val;
  }

  const igSnap = await db.collection("igrejas").limit(IGREJAS_SCAN).get();
  for (const doc of igSnap.docs) {
    const data = doc.data();
    if (churchIsBlocked(data)) blocked++;
    if (churchIsFree(data)) freeCount++;
    if (licenseActive(data)) licencasAtivas++;

    try {
      const dirSnap = await doc.ref
        .collection("_panel_cache")
        .doc("members_directory")
        .get();
      const dirData = dirSnap.data();
      const tc =
        dirData?.totalCount ??
        (dirData?.summary as Record<string, unknown> | undefined)?.totalCount;
      if (typeof tc === "number" && tc > 0) {
        membrosTotal += tc;
      } else {
        const mc = await doc.ref.collection("membros").count().get();
        membrosTotal += mc.data().count;
      }
    } catch (_) {
      try {
        const mc = await doc.ref.collection("membros").count().get();
        membrosTotal += mc.data().count;
      } catch (_) {}
    }

    const dt = vencimentoFromChurch(data);
    if (dt && dt >= now) {
      if (dt <= in7) {
        venc7++;
        if (expiringChurches.length < 12) {
          expiringChurches.push({
            tenantId: doc.id,
            nome: pickString(data, ["nome", "name", "slug"]) || doc.id,
            dataVencimento: admin.firestore.Timestamp.fromDate(dt),
          });
        }
      } else if (dt <= in30) {
        venc30++;
      }
    }

    const created = parseDate(
      data.createdAt ?? data.created_at ?? data.dataCadastro,
    );
    if (created) {
      const key = monthKey(created);
      if (byMonthIgrejas[key] != null) byMonthIgrejas[key]++;
    }

  }

  const panelStaleSample = igSnap.docs.slice(0, 24);
  const staleFlags = await Promise.all(
    panelStaleSample.map(async (doc) => {
      try {
        const cache = await doc.ref
          .collection("_panel_cache")
          .doc("dashboard_summary")
          .get();
        const updated = cache.data()?.updatedAt as
          | admin.firestore.Timestamp
          | undefined;
        const staleMs = 24 * 60 * 60 * 1000;
        return (
          !cache.exists ||
          !updated ||
          Date.now() - updated.toMillis() > staleMs
        );
      } catch {
        return false;
      }
    }),
  );
  panelStale = staleFlags.filter(Boolean).length;
  if (igSnap.size > panelStaleSample.length && panelStale > 0) {
    panelStale = Math.max(
      panelStale,
      Math.round((panelStale / panelStaleSample.length) * igSnap.size),
    );
  }

  try {
    const usersSnap = await db.collection("users").limit(USERS_SAMPLE).get();
    for (const d of usersSnap.docs) {
      const created = parseDate(d.data().createdAt ?? d.data().created_at);
      if (created) {
        const key = monthKey(created);
        if (byMonthUsuarios[key] != null) byMonthUsuarios[key]++;
      }
    }
  } catch (_) {}

  try {
    const salesSnap = await db.collection("sales").limit(400).get();
    for (const d of salesSnap.docs) {
      const data = d.data();
      const st = String(data.status ?? "").toLowerCase();
      if (!["approved", "paid", "accredited"].includes(st)) continue;
      const amt = data.amount ?? 0;
      const val = typeof amt === "number" ? amt : parseFloat(String(amt)) || 0;
      const method = String(
        data.payment_method ?? data.paymentMethod ?? data.payment_type ?? "",
      ).toLowerCase();
      if (method.includes("pix")) receitaPix += val;
      else receitaCartao += val;

      const created = parseDate(data.createdAt);
      if (created) {
        const key = monthKey(created);
        if (byMonthReceita[key] != null) byMonthReceita[key] += val;
      }
    }
  } catch (e) {
    functions.logger.warn("masterDashboardCache: sales", { e });
  }

  receita += receitaPix + receitaCartao;

  const actionQueue: Record<string, unknown>[] = [];
  if (venc7 > 0) {
    actionQueue.push({
      id: "venc_7d",
      title: "Licenças a vencer (7 dias)",
      subtitle: "Renovar antes do bloqueio",
      count: venc7,
      menuItem: "igrejasPlanos",
    });
  }
  if (alertas > 0) {
    actionQueue.push({
      id: "alertas",
      title: "Alertas não lidos",
      subtitle: "Rever notificações da plataforma",
      count: alertas,
      menuItem: "sistemaAlertas",
    });
  }
  if (blocked > 0) {
    actionQueue.push({
      id: "blocked",
      title: "Igrejas bloqueadas",
      subtitle: "Verificar pagamento ou FREE",
      count: blocked,
      menuItem: "igrejasLista",
    });
  }
  if (suggestionsPending > 0) {
    actionQueue.push({
      id: "suggestions",
      title: "Sugestões pendentes",
      subtitle: "Feedback de utilizadores",
      count: suggestionsPending,
      menuItem: "sistemaSugestoes",
    });
  }
  if (panelStale > 0) {
    actionQueue.push({
      id: "panel_stale",
      title: "Painéis desatualizados",
      subtitle: "Cache do painel igreja >24h",
      count: panelStale,
      menuItem: "igrejasLista",
    });
  }

  await summaryRef.set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      schemaVersion: 2,
      igrejas,
      usuarios,
      membrosTotal,
      receita,
      receitaPix,
      receitaCartao,
      alertas,
      licencasAtivas,
      vencimentos7d: venc7,
      vencimentos30d: venc30,
      blockedCount: blocked,
      freeCount,
      suggestionsPending,
      panelCacheStaleCount: panelStale,
      igrejasPorMes: mesesKeys.map((k) => ({
        key: k,
        label: monthLabel(k),
        valor: byMonthIgrejas[k] ?? 0,
      })),
      usuariosPorMes: mesesKeys.map((k) => ({
        key: k,
        label: monthLabel(k),
        valor: byMonthUsuarios[k] ?? 0,
      })),
      receitaPorMes: mesesKeys.map((k) => ({
        key: k,
        label: monthLabel(k),
        valor: byMonthReceita[k] ?? 0,
      })),
      expiringChurches,
      actionQueue,
    },
    { merge: false },
  );
}

/** Cache global do Painel Master — `config/master_dashboard_summary`. */
export const getMasterDashboardSnapshot = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = (context.auth.token || {}) as Record<string, unknown>;
    if (!isMasterCaller(token)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Acesso apenas para administradores da plataforma",
      );
    }

    const db = admin.firestore();
    const summaryRef = db.collection("config").doc("master_dashboard_summary");
    const snap = await summaryRef.get();
    const updated = snap.data()?.updatedAt as admin.firestore.Timestamp | undefined;
    const isStale =
      !snap.exists ||
      !updated ||
      Date.now() - updated.toMillis() > STALE_MS;

    if (isStale) {
      await recomputeMasterDashboardSummary();
    }

    const fresh = await summaryRef.get();
    return {
      ok: true,
      summary: fresh.data() ?? {},
      updatedAt: fresh.data()?.updatedAt ?? null,
    };
  });

/** Recomputa cache do painel de uma igreja (suporte master). */
export const warmChurchPanelFromMaster = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = (context.auth.token || {}) as Record<string, unknown>;
    if (!isMasterCaller(token)) {
      throw new functions.https.HttpsError("permission-denied", "Sem permissao");
    }
    const body = (data || {}) as Record<string, unknown>;
    const tenantId = String(body.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatorio");
    }
    const { recomputePanelDashboardSummary } = await import("./panelDashboardCache");
    await recomputePanelDashboardSummary(tenantId);
    return { ok: true, tenantId };
  });

export const scheduledRefreshMasterDashboard = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "1GB" })
  .pubsub.schedule("every 30 minutes")
  .onRun(async () => {
    try {
      await recomputeMasterDashboardSummary();
      functions.logger.info("masterDashboardCache: scheduled refresh ok");
    } catch (e) {
      functions.logger.error("masterDashboardCache: scheduled failed", { e });
    }
    return null;
  });
