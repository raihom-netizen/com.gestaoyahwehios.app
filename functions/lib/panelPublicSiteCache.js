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
exports.warmPublicSiteAndSignupCache = void 0;
exports.mirrorPublicSitePanelCache = mirrorPublicSitePanelCache;
exports.recomputePanelPublicSiteCache = recomputePanelPublicSiteCache;
exports.resolvePublicChurchIdFromInput = resolvePublicChurchIdFromInput;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const forbiddenTestChurchIds_1 = require("./forbiddenTestChurchIds");
const churchPerformancePack_1 = require("./churchPerformancePack");
const publicSiteMediaPrefetch_1 = require("./publicSiteMediaPrefetch");
const publicChurchSlugIndex_1 = require("./publicChurchSlugIndex");
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (v != null && String(v).trim())
            return String(v).trim();
    }
    return "";
}
/**
 * Espelha `_performance_cache/public_feed` + metadados da igreja em
 * `_panel_cache/public_site` (fonte única para painel + site público).
 */
async function mirrorPublicSitePanelCache(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    if ((0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(tid))
        return;
    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tid);
    const [churchSnap, perfSnap] = await Promise.all([
        churchRef.get(),
        churchRef.collection("_performance_cache").doc("public_feed").get(),
    ]);
    if (!churchSnap.exists) {
        functions.logger.warn("mirrorPublicSitePanelCache: skip — raiz inexistente", {
            tenantId: tid,
        });
        return;
    }
    const church = (churchSnap.data() ?? {});
    const perf = (perfSnap.data() ?? {});
    const feed = Array.isArray(perf.data)
        ? perf.data
        : [];
    let avisosCount = 0;
    let eventosCount = 0;
    for (const row of feed) {
        const col = String(row.collection ?? "").trim();
        if (col === "avisos")
            avisosCount += 1;
        if (col === "eventos")
            eventosCount += 1;
    }
    const payload = {
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
        await (0, publicChurchSlugIndex_1.syncPublicChurchSlugIndexForChurch)(tid, church);
    }
    catch (e) {
        functions.logger.warn("mirrorPublicSitePanelCache: slug index", { tenantId: tid, e });
    }
}
/** Atualiza feed público + mídia + espelho `_panel_cache/public_site`. */
async function recomputePanelPublicSiteCache(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    try {
        await (0, churchPerformancePack_1.refreshPublicFeedCacheForTenant)(tid);
    }
    catch (e) {
        functions.logger.warn("panelPublicSiteCache: refresh feed", { tenantId: tid, e });
    }
    try {
        await (0, publicSiteMediaPrefetch_1.recomputePublicSiteMediaPrefetch)(tid);
    }
    catch (e) {
        functions.logger.warn("panelPublicSiteCache: media prefetch", { tenantId: tid, e });
    }
    await mirrorPublicSitePanelCache(tid);
}
async function resolvePublicChurchIdFromInput(raw) {
    const db = admin.firestore();
    const seed = String(raw || "").trim();
    if (!seed)
        return "";
    // 1) Doc id direto.
    try {
        const direct = await db.collection("igrejas").doc(seed).get();
        if (direct.exists)
            return seed;
    }
    catch (_) { }
    // 2) Índice público por slug.
    const slug = seed.toLowerCase().replace(/[\s_]+/g, "-");
    if (slug) {
        try {
            const idx = await db.collection("public_church_slugs").doc(slug).get();
            const churchId = String(idx.data()?.churchId || "").trim();
            if (churchId)
                return churchId;
        }
        catch (_) { }
    }
    // 3) Fallback por campo slug no doc da igreja.
    try {
        const q = await db
            .collection("igrejas")
            .where("slug", "==", slug || seed)
            .limit(1)
            .get();
        if (!q.empty)
            return q.docs[0].id;
    }
    catch (_) { }
    return "";
}
/**
 * Warmup explícito do site público/cadastro público:
 * - feed público cacheado
 * - prefetch de mídia
 * - snapshot `_panel_cache/public_site`
 * - índice `public_church_slugs`
 */
exports.warmPublicSiteAndSignupCache = functions
    .region("southamerica-east1")
    .runWith({ memory: "256MB", timeoutSeconds: 60 })
    .https.onCall(async (data) => {
    const churchId = await resolvePublicChurchIdFromInput(data?.churchId ?? data?.slug ?? data?.tenantId);
    if (!churchId) {
        return { ok: false, reason: "church-not-found" };
    }
    await recomputePanelPublicSiteCache(churchId);
    return { ok: true, churchId };
});
//# sourceMappingURL=panelPublicSiteCache.js.map