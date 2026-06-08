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
exports.MIN_PLACEHOLDER_PNG = void 0;
exports.slugHintFromDocId = slugHintFromDocId;
exports.collectAliasCandidates = collectAliasCandidates;
exports.buildRootDocPatch = buildRootDocPatch;
exports.upsertChurchAliases = upsertChurchAliases;
exports.provisionChurchTenant = provisionChurchTenant;
exports.listAllIgrejaDocIds = listAllIgrejaDocIds;
exports.migrateAllChurchTenants = migrateAllChurchTenants;
/**
 * Alinha doc raiz `igrejas/{id}`, `church_aliases` e pastas Storage `igrejas/{id}/…`.
 * Usado no cadastro da igreja, signup de gestor e migração em lote.
 */
const admin = __importStar(require("firebase-admin"));
const churchClusterAnchors_1 = require("./churchClusterAnchors");
const churchStorageStructure_1 = require("./churchStorageStructure");
const MIN_PLACEHOLDER_PNG = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
    0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
    0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
    0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
exports.MIN_PLACEHOLDER_PNG = MIN_PLACEHOLDER_PNG;
function db() {
    return admin.firestore();
}
function str(v) {
    return String(v ?? "").trim();
}
/** Slug público sugerido a partir do id do doc (quando o gestor ainda não definiu slug). */
function slugHintFromDocId(docId) {
    const id = str(docId);
    if (!id)
        return "";
    let s = id;
    if (s.startsWith("igreja_"))
        s = s.slice("igreja_".length);
    return s.replace(/_/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
}
/** Candidatos a alias → doc canónico (exclui o próprio canónico). */
function collectAliasCandidates(docId, data) {
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(docId);
    const out = new Set();
    const add = (raw) => {
        const t = str(raw);
        if (!t || t === canonical)
            return;
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
    if (hinted)
        add(hinted);
    return Array.from(out);
}
/** Preenche campos mínimos do doc raiz (inclui «fantasma» só com subcoleções). */
function buildRootDocPatch(docId, data) {
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(docId);
    const d = data ?? {};
    const patch = {};
    const nome = str(d["nome"]) ||
        str(d["name"]) ||
        docId.replace(/^igreja_/, "").replace(/_/g, " ").trim() ||
        docId;
    if (!str(d["nome"]))
        patch.nome = nome;
    if (!str(d["name"]))
        patch.name = nome;
    if (!str(d["tenantId"]))
        patch.tenantId = canonical;
    if (!str(d["igrejaId"]))
        patch.igrejaId = canonical;
    if (!str(d["churchId"]))
        patch.churchId = canonical;
    const isBpcCanonical = canonical === churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
    const slug = isBpcCanonical
        ? churchClusterAnchors_1.BPC_PUBLIC_SLUG
        : str(d["slug"]) || str(d["slugId"]) || str(d["alias"]) || slugHintFromDocId(docId);
    if (slug) {
        if (isBpcCanonical || !str(d["slug"]))
            patch.slug = slug;
        if (isBpcCanonical || !str(d["slugId"]))
            patch.slugId = slug;
        if (isBpcCanonical || !str(d["alias"]))
            patch.alias = slug;
    }
    if (isBpcCanonical) {
        patch.tenantId = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
        patch.igrejaId = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
        patch.churchId = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
        patch.canonicalTenantId = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
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
async function upsertChurchAliases(canonicalId, aliases, source) {
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(canonicalId);
    if (!canonical)
        return 0;
    let count = 0;
    const batchSize = 400;
    let batch = db().batch();
    let inBatch = 0;
    for (const alias of aliases) {
        const a = str(alias);
        if (!a || a === canonical)
            continue;
        const ref = db().collection("church_aliases").doc(a);
        batch.set(ref, {
            canonicalId: canonical,
            alias: a,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            source,
        }, { merge: true });
        count += 1;
        inBatch += 1;
        if (inBatch >= batchSize) {
            await batch.commit();
            batch = db().batch();
            inBatch = 0;
        }
    }
    if (inBatch > 0)
        await batch.commit();
    return count;
}
async function provisionChurchTenant(docId, options = {}) {
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
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(rawId);
    const churchRef = db().collection("igrejas").doc(rawId);
    let data = options.data;
    if (!data) {
        const snap = await churchRef.get();
        data = snap.exists ? (snap.data() ?? {}) : {};
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
        const cfg = await (0, churchStorageStructure_1.ensureConfiguracoesStorageFolder)(canonical);
        storageConfigCreated = cfg.created;
        const fin = await (0, churchStorageStructure_1.ensureFinanceiroStorageFolder)(canonical);
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
async function listAllIgrejaDocIds(firestore) {
    const refs = await firestore.collection("igrejas").listDocuments();
    return refs.map((r) => r.id).filter(Boolean);
}
/** Migração em lote — todas as igrejas do projeto. */
async function migrateAllChurchTenants(source = "migrate_church_roots_and_aliases.mjs") {
    const ids = await listAllIgrejaDocIds(db());
    const results = [];
    for (const id of ids) {
        try {
            const r = await provisionChurchTenant(id, { source });
            results.push(r);
        }
        catch (e) {
            console.error(`migrateAllChurchTenants ${id}:`, e);
            results.push({
                ok: false,
                canonicalId: (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(id),
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
//# sourceMappingURL=churchTenantProvisioning.js.map