/**
 * Alinha doc raiz `igrejas/{id}` e pastas Storage `igrejas/{id}/…` (SaaS directo).
 * Sem `church_aliases` — cada igreja isolada pelo doc ID.
 */
import * as admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";
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

/** Preenche campos mínimos do doc raiz (inclui «fantasma» só com subcoleções). */
export function buildRootDocPatch(
  docId: string,
  data: Record<string, unknown> | undefined,
): Record<string, unknown> {
  const id = str(docId);
  const d = data ?? {};
  const patch: Record<string, unknown> = {};

  const nome =
    str(d["nome"]) ||
    str(d["name"]) ||
    id.replace(/^igreja_/, "").replace(/_/g, " ").trim() ||
    id;

  if (!str(d["nome"])) patch.nome = nome;
  if (!str(d["name"])) patch.name = nome;
  if (!str(d["tenantId"])) patch.tenantId = id;
  if (!str(d["igrejaId"])) patch.igrejaId = id;
  if (!str(d["churchId"])) patch.churchId = id;
  if (!str(d["canonicalTenantId"])) patch.canonicalTenantId = id;
  if (!str(d["churchCanonicalId"])) patch.churchCanonicalId = id;

  // SaaS directo — sem alias/slug; paths Firestore/Storage usam só o doc ID.
  patch.alias = admin.firestore.FieldValue.delete();
  patch.slug = admin.firestore.FieldValue.delete();
  patch.slugId = admin.firestore.FieldValue.delete();

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

/** Legado — `church_aliases` removido; mantido só para compat de import. */
export async function upsertChurchAliases(
  _canonicalId: string,
  _aliases: string[],
  _source: string,
): Promise<number> {
  return 0;
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

  const canonical = rawId;
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

  const aliasesUpserted = 0;

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
        canonicalId: id,
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
