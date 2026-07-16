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
exports.buildRootDocPatch = buildRootDocPatch;
exports.upsertChurchAliases = upsertChurchAliases;
exports.provisionChurchTenant = provisionChurchTenant;
exports.listAllIgrejaDocIds = listAllIgrejaDocIds;
exports.migrateAllChurchTenants = migrateAllChurchTenants;
/**
 * Alinha doc raiz `igrejas/{id}` e pastas Storage `igrejas/{id}/…` (SaaS directo).
 * Sem `church_aliases` — cada igreja isolada pelo doc ID.
 */
const admin = __importStar(require("firebase-admin"));
const churchStorageStructure_1 = require("./churchStorageStructure");
const forbiddenTestChurchIds_1 = require("./forbiddenTestChurchIds");
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
/** Preenche campos mínimos do doc raiz (inclui «fantasma» só com subcoleções). */
function buildRootDocPatch(docId, data) {
    const id = str(docId);
    const d = data ?? {};
    const patch = {};
    const nome = str(d["nome"]) ||
        str(d["name"]) ||
        id.replace(/^igreja_/, "").replace(/_/g, " ").trim() ||
        id;
    if (!str(d["nome"]))
        patch.nome = nome;
    if (!str(d["name"]))
        patch.name = nome;
    if (!str(d["tenantId"]))
        patch.tenantId = id;
    if (!str(d["igrejaId"]))
        patch.igrejaId = id;
    if (!str(d["churchId"]))
        patch.churchId = id;
    if (!str(d["canonicalTenantId"]))
        patch.canonicalTenantId = id;
    if (!str(d["churchCanonicalId"]))
        patch.churchCanonicalId = id;
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
async function upsertChurchAliases(_canonicalId, _aliases, _source) {
    return 0;
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
    // IDs de teste — nunca provisionar / recriar (voltam sozinhas após delete incompleto).
    if ((0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(rawId)) {
        console.warn(`provisionChurchTenant: ignorado id de teste reservado «${rawId}» (source=${source})`);
        return {
            ok: false,
            canonicalId: rawId,
            docId: rawId,
            rootPatched: false,
            aliasesUpserted: 0,
            storageConfigCreated: false,
            storageFinanceiroCreated: false,
            source,
        };
    }
    const canonical = rawId;
    const churchRef = db().collection("igrejas").doc(rawId);
    const snap = await churchRef.get();
    let data = options.data;
    if (!data) {
        data = snap.exists ? (snap.data() ?? {}) : {};
    }
    // Doc fantasma (só subcoleções): NÃO recriar raiz — era o bug das igrejas teste.
    if (!snap.exists && !options.allowCreateRoot) {
        console.warn(`provisionChurchTenant: skip create fantasma «${rawId}» (source=${source})`);
        return {
            ok: true,
            canonicalId: canonical,
            docId: rawId,
            rootPatched: false,
            aliasesUpserted: 0,
            storageConfigCreated: false,
            storageFinanceiroCreated: false,
            source,
        };
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
        if ((0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(id)) {
            console.warn(`migrateAllChurchTenants: skip teste «${id}»`);
            continue;
        }
        try {
            // Nunca allowCreateRoot aqui — evita ressuscitar docs fantasma.
            const r = await provisionChurchTenant(id, {
                source,
                allowCreateRoot: false,
            });
            results.push(r);
        }
        catch (e) {
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
//# sourceMappingURL=churchTenantProvisioning.js.map