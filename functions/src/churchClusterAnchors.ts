/**
 * Igreja Brasil para Cristo — doc Firestore + prefixo Storage canónicos.
 * Após consolidação: dados só em `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/…`.
 * IDs legados → `church_aliases/{alias}` → canónico.
 */
export const BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";

/** Slug público BPC (URL `/igreja/{slug}/…`) — distinto do ID do doc Firestore. */
export const BPC_PUBLIC_SLUG = "o-brasil-cristo-jardim-goiano";

/** Docs irmãos legados — migrados e removidos por `consolidateBpcChurchToCanonical`. */
export const BPC_LEGACY_TENANT_IDS = [
  "brasilparacristo",
  "brasilparacristo_sistema",
  "iobpc-jardim-goiano",
  "o-brasil-cristo-jardim-goiano",
] as const;

export const ANCHORED_CLUSTERS: Record<string, string[]> = {
  [BPC_CANONICAL_IGREJA_ID]: [BPC_CANONICAL_IGREJA_ID],
};

export function resolveAnchoredCanonicalTenantId(seed: string): string {
  const t = String(seed || "").trim();
  if (!t) return t;
  if (t === BPC_CANONICAL_IGREJA_ID) return BPC_CANONICAL_IGREJA_ID;
  if ((BPC_LEGACY_TENANT_IDS as readonly string[]).includes(t)) {
    return BPC_CANONICAL_IGREJA_ID;
  }
  for (const [canonical, members] of Object.entries(ANCHORED_CLUSTERS)) {
    if (t === canonical || members.includes(t)) return canonical;
  }
  return t;
}

export function addAnchoredCluster(seed: string, out: Set<string>) {
  const t = String(seed || "").trim();
  if (!t) return;
  const canonical = resolveAnchoredCanonicalTenantId(t);
  if (canonical) out.add(canonical);
  if ((BPC_LEGACY_TENANT_IDS as readonly string[]).includes(t)) {
    for (const leg of BPC_LEGACY_TENANT_IDS) out.add(leg);
  }
  for (const [key, members] of Object.entries(ANCHORED_CLUSTERS)) {
    if (key === t || members.includes(t)) {
      out.add(key);
      for (const m of members) out.add(m);
    }
  }
}

/** IDs para tópico FCM — canónico + alias legado (até FCM topics atualizarem). */
export function tenantIdsForPushTopic(rawTenantId: string): string[] {
  const raw = String(rawTenantId || "").trim();
  if (!raw) return [];
  const canonical = resolveAnchoredCanonicalTenantId(raw);
  const out = new Set<string>([raw, canonical]);
  if ((BPC_LEGACY_TENANT_IDS as readonly string[]).includes(raw)) {
    out.add(BPC_CANONICAL_IGREJA_ID);
  }
  return Array.from(out).filter(Boolean);
}
