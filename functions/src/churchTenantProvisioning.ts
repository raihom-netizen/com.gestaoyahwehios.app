/**
 * Alinha doc raiz `igrejas/{id}`, `church_aliases` e pastas Storage `igrejas/{id}/…`.
 * Usado no cadastro da igreja, signup de gestor e migração em lote.
 */
import * as admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";
import {
  BPC_CANONICAL_IGREJA_ID,
  BPC_PUBLIC_SLUG,
  resolveAnchoredCanonicalTenantId,
} from "./churchClusterAnchors";
import {
  ensureConfiguracoesStorageFolder,
  ensureFinanceiroStorageFolder,
} from "./churchStorageStructure";

const MIN_PLACEHOLDER_PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
  0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
  0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
  0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

export type ProvisionChurchTenantResult = {
  ok: boolean;
  canonicalId: string;
  docId: string;
  rootPatched: boolean;
  aliasesUpserted: number;
  storageConfigCreated: boolean;
  storageFinanceiroCreated: boolean;
  source: string;
};

function db(): Firestore {
  return admin.firestore();
}

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** Slug público sugerido a partir do id do doc (quando o gestor ainda não definiu slug). */
export function slugHintFromDocId(docId: string): string {
  const id = str(docId);
  if (!id) return "";
  let s = id;
  if (s.startsWith("igreja_")) s = s.slice("igreja_".length);
  return s.replace(/_/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
}

/** Candidatos a alias → doc canónico (exclui o próprio canónico). */
export function collectAliasCandidates(
  docId: string,
  data: Record<string, unknown> | undefined,
): string[] {
  const canonical = resolveAnchoredCanonicalTenantId(docId);
  const out = new Set<string>();
  const add = (raw: string) => {
    const t = str(raw);
    if (!t || t === canonical) return;
    out.add(t);
  };

  if (data) {
    for (const k of ["slug", "slugId", "alias", "churchId"]) {
      add(str(data[k]));
    }
    add(str(data["igrejaId"]));
    add(str(data["tenantId"]));
  }
  add(docId);

  const hinted = slugHintFromDocId(docId);
  if (hinted) add(hinted);

  return Array.from(out);
}

/** Preenche campos mínimos do doc raiz (inclui «fantasma» só com subcoleções). */
export function buildRootDocPatch(
  docId: string,
  data: Record<string, unknown> | undefined,
): Record<string, unknown> {
  const canonical = resolveAnchoredCanonicalTenantId(docId);
  const d = data ?? {};
  const patch: Record<string, unknown> = {};

  const nome =
    str(d["nome"]) ||
    str(d["name"]) ||
    docId.replace(/^igreja_/, "").replace(/_/g, " ").trim() ||
    docId;

  if (!str(d["nome"])) patch.nome = nome;
  if (!str(d["name"])) patch.name = nome;
  if (!str(d["tenantId"])) patch.tenantId = canonical;
  if (!str(d["igrejaId"])) patch.igrejaId = canonical;
  if (!str(d["churchId"])) patch.churchId = canonical;
  if (!str(d["canonicalTenantId"])) patch.canonicalTenantId = canonical;

  const isBpcCanonical = canonical === BPC_CANONICAL_IGREJA_ID;
  const slug = isBpcCanonical
    ? BPC_PUBLIC_SLUG
    : str(d["slug"]) || str(d["slugId"]) || str(d["alias"]) || slugHintFromDocId(docId);
  if (slug) {
    if (isBpcCanonical || !str(d["slug"])) patch.slug = slug;
    if (isBpcCanonical || !str(d["slugId"])) patch.slugId = slug;
    if (isBpcCanonical || !str(d["alias"])) patch.alias = slug;
  }
  if (isBpcCanonical) {
    patch.tenantId = BPC_CANONICAL_IGREJA_ID;
    patch.igrejaId = BPC_CANONICAL_IGREJA_ID;
    patch.churchId = BPC_CANONICAL_IGREJA_ID;
    patch.canonicalTenantId = BPC_CANONICAL_IGREJA_ID;
  }

  if (d["ativa"] === undefined && d["active"] === undefined) {
    patch.ativa = true;
  }
  if (d["status"] === undefined) {
    patch.status = "ativa";
  }

  patch.tenantProvisionedAt = admin.firestore.FieldValue.serverTimestamp();
  patch.tenantProvisionSource = str(d["tenantProvisionSource"]) || "churchTenantProvisioning";

  return patch;
}

export async function upsertChurchAliases(
  canonicalId: string,
  aliases: string[],
  source: string,
): Promise<number> {
  const canonical = resolveAnchoredCanonicalTenantId(canonicalId);
  if (!canonical) return 0;

  let count = 0;
  const batchSize = 400;
  let batch = db().batch();
  let inBatch = 0;

  for (const alias of aliases) {
    const a = str(alias);
    if (!a || a === canonical) continue;
    const ref = db().collection("church_aliases").doc(a);
    batch.set(
      ref,
      {
        canonicalId: canonical,
        alias: a,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source,
      },
      { merge: true },
    );
    count += 1;
    inBatch += 1;
    if (inBatch >= batchSize) {
      await batch.commit();
      batch = db().batch();
      inBatch = 0;
    }
  }
  if (inBatch > 0) await batch.commit();
  return count;
}

export async function provisionChurchTenant(
  docId: string,
  options: {
    source?: string;
    data?: Record<string, unknown>;
    skipRootPatch?: boolean;
    skipAliases?: boolean;
    skipStorage?: boolean;
  } = {},
): Promise<ProvisionChurchTenantResult> {
  const source = str(options.source) || "provisionChurchTenant";
  const rawId = str(docId);
  if (!rawId) {
    return {
      ok: false,
      canonicalId: "",
      docId: "",
      rootPatched: false,
      aliasesUpserted: 0,
      storageConfigCreated: false,
      storageFinanceiroCreated: false,
      source,
    };
  }

  const canonical = resolveAnchoredCanonicalTenantId(rawId);
  const churchRef = db().collection("igrejas").doc(rawId);

  let data = options.data;
  if (!data) {
    const snap = await churchRef.get();
    data = snap.exists ? ((snap.data() ?? {}) as Record<string, unknown>) : {};
  }

  let rootPatched = false;
  if (!options.skipRootPatch) {
    const patch = buildRootDocPatch(rawId, data);
    patch.tenantProvisionSource = source;
    if (Object.keys(patch).length > 0) {
      await churchRef.set(patch, { merge: true });
      rootPatched = true;
      data = { ...data, ...patch };
    }
  }

  let aliasesUpserted = 0;
  if (!options.skipAliases) {
    const aliases = collectAliasCandidates(rawId, data);
    aliasesUpserted = await upsertChurchAliases(canonical, aliases, source);
  }

  let storageConfigCreated = false;
  let storageFinanceiroCreated = false;
  if (!options.skipStorage) {
    const cfg = await ensureConfiguracoesStorageFolder(canonical);
    storageConfigCreated = cfg.created;
    const fin = await ensureFinanceiroStorageFolder(canonical);
    storageFinanceiroCreated = fin.created;
  }

  return {
    ok: true,
    canonicalId: canonical,
    docId: rawId,
    rootPatched,
    aliasesUpserted,
    storageConfigCreated,
    storageFinanceiroCreated,
    source,
  };
}

/** Lista todos os ids em `igrejas/` (inclui docs «fantasma» com subcoleções). */
export async function listAllIgrejaDocIds(firestore: Firestore): Promise<string[]> {
  const refs = await firestore.collection("igrejas").listDocuments();
  return refs.map((r) => r.id).filter(Boolean);
}

/** Migração em lote — todas as igrejas do projeto. */
export async function migrateAllChurchTenants(
  source = "migrate_church_roots_and_aliases.mjs",
): Promise<{
  total: number;
  ok: number;
  results: ProvisionChurchTenantResult[];
}> {
  const ids = await listAllIgrejaDocIds(db());
  const results: ProvisionChurchTenantResult[] = [];
  for (const id of ids) {
    try {
      const r = await provisionChurchTenant(id, { source });
      results.push(r);
    } catch (e) {
      console.error(`migrateAllChurchTenants ${id}:`, e);
      results.push({
        ok: false,
        canonicalId: resolveAnchoredCanonicalTenantId(id),
        docId: id,
        rootPatched: false,
        aliasesUpserted: 0,
        storageConfigCreated: false,
        storageFinanceiroCreated: false,
        source,
      });
    }
  }
  return {
    total: ids.length,
    ok: results.filter((r) => r.ok).length,
    results,
  };
}

export { MIN_PLACEHOLDER_PNG };
