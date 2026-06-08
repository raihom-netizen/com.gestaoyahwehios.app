"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ANCHORED_CLUSTERS = exports.BPC_CANONICAL_IGREJA_ID = void 0;
exports.resolveAnchoredCanonicalTenantId = resolveAnchoredCanonicalTenantId;
exports.addAnchoredCluster = addAnchoredCluster;
exports.tenantIdsForPushTopic = tenantIdsForPushTopic;
/**
 * Igreja Brasil para Cristo — doc Firestore + prefixo Storage canónicos.
 * Dados reais vivem em `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/…`.
 */
exports.BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";
exports.ANCHORED_CLUSTERS = {
    [exports.BPC_CANONICAL_IGREJA_ID]: [
        exports.BPC_CANONICAL_IGREJA_ID,
        "brasilparacristo",
        "brasilparacristo_sistema",
        "iobpc-jardim-goiano",
        "o-brasil-cristo-jardim-goiano",
    ],
};
function resolveAnchoredCanonicalTenantId(seed) {
    const t = String(seed || "").trim();
    if (!t)
        return t;
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
    for (const [key, members] of Object.entries(exports.ANCHORED_CLUSTERS)) {
        if (key === t || members.includes(t)) {
            out.add(key);
            for (const m of members)
                out.add(m);
        }
    }
}
/** IDs para tópico FCM — canónico + alias (ex.: BPC legado vs `_sistema`). */
function tenantIdsForPushTopic(rawTenantId) {
    const raw = String(rawTenantId || "").trim();
    if (!raw)
        return [];
    const canonical = resolveAnchoredCanonicalTenantId(raw);
    const out = new Set([raw, canonical]);
    for (const [key, members] of Object.entries(exports.ANCHORED_CLUSTERS)) {
        if (key === raw || members.includes(raw)) {
            out.add(key);
            for (const m of members)
                out.add(m);
        }
    }
    return Array.from(out).filter(Boolean);
}
//# sourceMappingURL=churchClusterAnchors.js.map