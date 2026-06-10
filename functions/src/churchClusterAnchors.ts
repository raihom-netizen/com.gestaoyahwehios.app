/**
 * SaaS multi-tenant — cada igreja isolada em `igrejas/{churchId}/…`.
 * Sem `church_aliases`, cluster ou docs irmãos.
 */

/** Legado BPC — só referência em scripts de migração one-shot (não usar em runtime). */
export const BPC_CANONICAL_IGREJA_ID = "igreja_o_brasil_para_cristo_jardim_goiano";
export const BPC_PUBLIC_SLUG = "o-brasil-cristo-jardim-goiano";
export const BPC_LEGACY_TENANT_IDS = [
  "brasilparacristo",
  "brasilparacristo_sistema",
  "iobpc-jardim-goiano",
  "o-brasil-cristo-jardim-goiano",
] as const;

export const ANCHORED_CLUSTERS: Record<string, string[]> = {};

/** ID directo do doc `igrejas/{churchId}`. */
export function resolveAnchoredCanonicalTenantId(seed: string): string {
  return String(seed || "").trim();
}

export function addAnchoredCluster(seed: string, out: Set<string>) {
  const t = String(seed || "").trim();
  if (t) out.add(t);
}

/** FCM — um tópico por igreja: `gypush_{churchId}_{kind}`. */
export function tenantIdsForPushTopic(rawTenantId: string): string[] {
  const t = String(rawTenantId || "").trim();
  return t ? [t] : [];
}
