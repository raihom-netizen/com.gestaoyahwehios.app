"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ANCHORED_CLUSTERS = exports.BPC_LEGACY_TENANT_IDS = exports.BPC_PUBLIC_SLUG = exports.BPC_CANONICAL_IGREJA_ID = void 0;
exports.resolveAnchoredCanonicalTenantId = resolveAnchoredCanonicalTenantId;
exports.addAnchoredCluster = addAnchoredCluster;
exports.tenantIdsForPushTopic = tenantIdsForPushTopic;
/**
 * Igreja Brasil para Cristo — doc Firestore + prefixo Storage canónicos.
 * Após consolidação: dados só em `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/…`.
 * IDs legados → `church_aliases/{alias}` → canónico.
 */
exports.BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";
/** Slug público BPC (URL `/igreja/{slug}/…`) — distinto do ID do doc Firestore. */
exports.BPC_PUBLIC_SLUG = "o-brasil-cristo-jardim-goiano";
/** Docs irmãos legados — migrados e removidos por `consolidateBpcChurchToCanonical`. */
exports.BPC_LEGACY_TENANT_IDS = [
    "brasilparacristo",
    "brasilparacristo_sistema",
    "iobpc-jardim-goiano",
    "o-brasil-cristo-jardim-goiano",
];
exports.ANCHORED_CLUSTERS = {
    [exports.BPC_CANONICAL_IGREJA_ID]: [exports.BPC_CANONICAL_IGREJA_ID],
};
function resolveAnchoredCanonicalTenantId(seed) {
    const t = String(seed || "").trim();
    if (!t)
        return t;
    if (t === exports.BPC_CANONICAL_IGREJA_ID)
        return exports.BPC_CANONICAL_IGREJA_ID;
    if (exports.BPC_LEGACY_TENANT_IDS.includes(t)) {
        return exports.BPC_CANONICAL_IGREJA_ID;
    }
    for (const [canonical, members] of Object.entries(exports.ANCHORED_CLUSTERS)) {
        if (t === canonical || members.includes(t))
            return canonical;
    }
    return t;
}
function addAnchoredCluster(seed, out) {
    const t = String(seed || "").trim();
    if (!t)
        return;
    const canonical = resolveAnchoredCanonicalTenantId(t);
    if (canonical)
        out.add(canonical);
    if (exports.BPC_LEGACY_TENANT_IDS.includes(t)) {
        for (const leg of exports.BPC_LEGACY_TENANT_IDS)
            out.add(leg);
    }
    for (const [key, members] of Object.entries(exports.ANCHORED_CLUSTERS)) {
        if (key === t || members.includes(t)) {
            out.add(key);
            for (const m of members)
                out.add(m);
        }
    }
}
/** IDs para tópico FCM — canónico + alias legado (até FCM topics atualizarem). */
function tenantIdsForPushTopic(rawTenantId) {
    const raw = String(rawTenantId || "").trim();
    if (!raw)
        return [];
    const canonical = resolveAnchoredCanonicalTenantId(raw);
    const out = new Set([raw, canonical]);
    if (exports.BPC_LEGACY_TENANT_IDS.includes(raw)) {
        out.add(exports.BPC_CANONICAL_IGREJA_ID);
    }
    return Array.from(out).filter(Boolean);
}
//# sourceMappingURL=churchClusterAnchors.js.map