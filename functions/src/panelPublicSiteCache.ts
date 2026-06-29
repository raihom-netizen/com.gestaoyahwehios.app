import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import { refreshPublicFeedCacheForTenant } from "./churchPerformancePack";
import { recomputePublicSiteMediaPrefetch } from "./publicSiteMediaPrefetch";
import { syncPublicChurchSlugIndexForChurch } from "./publicChurchSlugIndex";

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (v != null && String(v).trim()) return String(v).trim();
  }
  return "";
}

/**
 * Espelha `_performance_cache/public_feed` + metadados da igreja em
 * `_panel_cache/public_site` (fonte única para painel + site público).
 */
export async function mirrorPublicSitePanelCache(tenantId: string): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const db = admin.firestore();
  const churchRef = db.collection("igrejas").doc(tid);

  const [churchSnap, perfSnap] = await Promise.all([
    churchRef.get(),
    churchRef.collection("_performance_cache").doc("public_feed").get(),
  ]);

  const church = (churchSnap.data() ?? {}) as Record<string, unknown>;
  const perf = (perfSnap.data() ?? {}) as Record<string, unknown>;
  const feed = Array.isArray(perf.data)
    ? (perf.data as Record<string, unknown>[])
    : [];

  let avisosCount = 0;
  let eventosCount = 0;
  for (const row of feed) {
    const col = String(row.collection ?? "").trim();
    if (col === "avisos") avisosCount += 1;
    if (col === "eventos") eventosCount += 1;
  }

  const payload: Record<string, unknown> = {
    schemaVersion: 1,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    churchName: pickString(church, ["nome", "name", "NOME_IGREJA", "nomeIgreja"]),
    churchSlug: pickString(church, ["slug", "siteSlug", "churchSlug"]),
    sitePublicoUrl: pickString(church, [
      "sitePublico",
      "site_publico",
      "siteUrl",
      "urlSite",
    ]),
    churchLogoUrl: perf.churchLogoUrl ?? null,
    prefetchUrls: Array.isArray(perf.prefetchUrls) ? perf.prefetchUrls : [],
    publicAvisosCount: avisosCount,
    publicEventosCount: eventosCount,
    feedPreview: feed.slice(0, 12),
    data: feed.slice(0, 50),
  };

  await churchRef.collection("_panel_cache").doc("public_site").set(payload, {
    merge: false,
  });

  try {
    await syncPublicChurchSlugIndexForChurch(tid, church);
  } catch (e) {
    functions.logger.warn("mirrorPublicSitePanelCache: slug index", { tenantId: tid, e });
  }
}

/** Atualiza feed público + mídia + espelho `_panel_cache/public_site`. */
export async function recomputePanelPublicSiteCache(tenantId: string): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  try {
    await refreshPublicFeedCacheForTenant(tid);
  } catch (e) {
    functions.logger.warn("panelPublicSiteCache: refresh feed", { tenantId: tid, e });
  }

  try {
    await recomputePublicSiteMediaPrefetch(tid);
  } catch (e) {
    functions.logger.warn("panelPublicSiteCache: media prefetch", { tenantId: tid, e });
  }

  await mirrorPublicSitePanelCache(tid);
}

export async function resolvePublicChurchIdFromInput(raw: unknown): Promise<string> {
  const db = admin.firestore();
  const seed = String(raw || "").trim();
  if (!seed) return "";

  // 1) Doc id direto.
  try {
    const direct = await db.collection("igrejas").doc(seed).get();
    if (direct.exists) return seed;
  } catch (_) {}

  // 2) Índice público por slug.
  const slug = seed.toLowerCase().replace(/[\s_]+/g, "-");
  if (slug) {
    try {
      const idx = await db.collection("public_church_slugs").doc(slug).get();
      const churchId = String(idx.data()?.churchId || "").trim();
      if (churchId) return churchId;
    } catch (_) {}
  }

  // 3) Fallback por campo slug no doc da igreja.
  try {
    const q = await db
      .collection("igrejas")
      .where("slug", "==", slug || seed)
      .limit(1)
      .get();
    if (!q.empty) return q.docs[0].id;
  } catch (_) {}

  return "";
}

/**
 * Warmup explícito do site público/cadastro público:
 * - feed público cacheado
 * - prefetch de mídia
 * - snapshot `_panel_cache/public_site`
 * - índice `public_church_slugs`
 */
export const warmPublicSiteAndSignupCache = functions
  .region("southamerica-east1")
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .https.onCall(async (data) => {
    const churchId = await resolvePublicChurchIdFromInput(
      data?.churchId ?? data?.slug ?? data?.tenantId
    );
    if (!churchId) {
      return { ok: false, reason: "church-not-found" };
    }

    await recomputePanelPublicSiteCache(churchId);
    return { ok: true, churchId };
  });
