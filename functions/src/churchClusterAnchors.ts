/**
 * Igreja Brasil para Cristo — doc Firestore + prefixo Storage canónicos.
 * Dados reais vivem em `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/…`.
 */
export const BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";

export const ANCHORED_CLUSTERS: Record<string, string[]> = {
  [BPC_CANONICAL_IGREJA_ID]: [
    BPC_CANONICAL_IGREJA_ID,
    "brasilparacristo",
    "brasilparacristo_sistema",
    "iobpc-jardim-goiano",
    "o-brasil-cristo-jardim-goiano",
  ],
};

export function resolveAnchoredCanonicalTenantId(seed: string): string {
  const t = String(seed || "").trim();
  if (!t) return t;
  for (const [canonical, members] of Object.entries(ANCHORED_CLUSTERS)) {
    if (t === canonical || members.includes(t)) return canonical;
  }
  return t;
}

export function addAnchoredCluster(seed: string, out: Set<string>) {
  const t = String(seed || "").trim();
  if (!t) return;
  for (const [key, members] of Object.entries(ANCHORED_CLUSTERS)) {
    if (key === t || members.includes(t)) {
      out.add(key);
      for (const m of members) out.add(m);
    }
  }
}

/** IDs para tópico FCM — canónico + alias (ex.: BPC legado vs `_sistema`). */
export function tenantIdsForPushTopic(rawTenantId: string): string[] {
  const raw = String(rawTenantId || "").trim();
  if (!raw) return [];
  const canonical = resolveAnchoredCanonicalTenantId(raw);
  const out = new Set<string>([raw, canonical]);
  for (const [key, members] of Object.entries(ANCHORED_CLUSTERS)) {
    if (key === raw || members.includes(raw)) {
      out.add(key);
      for (const m of members) out.add(m);
    }
  }
  return Array.from(out).filter(Boolean);
}
