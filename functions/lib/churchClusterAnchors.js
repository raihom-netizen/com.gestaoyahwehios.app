"use strict";
/**
 * SaaS multi-tenant — cada igreja isolada em `igrejas/{churchId}/…`.
 * Sem `church_aliases`, cluster ou docs irmãos.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.ANCHORED_CLUSTERS = exports.BPC_LEGACY_TENANT_IDS = exports.BPC_PUBLIC_SLUG = exports.BPC_CANONICAL_IGREJA_ID = void 0;
exports.resolveAnchoredCanonicalTenantId = resolveAnchoredCanonicalTenantId;
exports.addAnchoredCluster = addAnchoredCluster;
exports.tenantIdsForPushTopic = tenantIdsForPushTopic;
/** Legado BPC — só referência em scripts de migração one-shot (não usar em runtime). */
exports.BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";
exports.BPC_PUBLIC_SLUG = "o-brasil-cristo-jardim-goiano";
exports.BPC_LEGACY_TENANT_IDS = [
    "brasilparacristo",
    "brasilparacristo_sistema",
    "iobpc-jardim-goiano",
    "o-brasil-cristo-jardim-goiano",
];
exports.ANCHORED_CLUSTERS = {};
/** ID directo do doc `igrejas/{churchId}`. */
function resolveAnchoredCanonicalTenantId(seed) {
    return String(seed || "").trim();
}
function addAnchoredCluster(seed, out) {
    const t = String(seed || "").trim();
    if (t)
        out.add(t);
}
/** FCM — um tópico por igreja: `gypush_{churchId}_{kind}`. */
function tenantIdsForPushTopic(rawTenantId) {
    const t = String(rawTenantId || "").trim();
    return t ? [t] : [];
}
//# sourceMappingURL=churchClusterAnchors.js.map