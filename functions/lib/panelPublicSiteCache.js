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
exports.mirrorPublicSitePanelCache = mirrorPublicSitePanelCache;
exports.recomputePanelPublicSiteCache = recomputePanelPublicSiteCache;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const churchPerformancePack_1 = require("./churchPerformancePack");
const publicSiteMediaPrefetch_1 = require("./publicSiteMediaPrefetch");
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
    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tid);
    const [churchSnap, perfSnap] = await Promise.all([
        churchRef.get(),
        churchRef.collection("_performance_cache").doc("public_feed").get(),
    ]);
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
//# sourceMappingURL=panelPublicSiteCache.js.map