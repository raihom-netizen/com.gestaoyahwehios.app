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
exports.syncBpcMemberTenantLinkageHttp = exports.syncBpcMemberTenantLinkage = exports.BPC_PUBLIC_SLUG = exports.consolidateBpcChurchToCanonicalHttp = exports.consolidateBpcChurchToCanonical = void 0;
exports.bpcLegacyTenantIds = bpcLegacyTenantIds;
exports.runConsolidateBpcToCanonical = runConsolidateBpcToCanonical;
exports.runSyncBpcMemberTenantLinkage = runSyncBpcMemberTenantLinkage;
/**
 * Consolida Igreja Brasil para Cristo → único doc canónico Firestore.
 * Migra subcoleções dos IDs legados, reponta users/church_aliases e remove docs irmãos.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const churchClusterAnchors_1 = require("./churchClusterAnchors");
const META_DOC = "bpc_consolidation_v1";
const BATCH_LIMIT = 400;
function db() {
    return admin.firestore();
}
/** IDs legados BPC (exceto canónico) — removidos após migração. */
function bpcLegacyTenantIds() {
    return [...churchClusterAnchors_1.BPC_LEGACY_TENANT_IDS];
}
function normCpf(raw) {
    const d = String(raw ?? "").replace(/\D/g, "");
    if (!d)
        return "";
    if (d.length > 11)
        return d.substring(d.length - 11);
    if (d.length < 11)
        return d.padStart(11, "0");
    return d;
}
function docRichness(data) {
    if (!data)
        return 0;
    let score = Object.keys(data).length;
    for (const k of ["nome", "name", "slug", "slugId", "alias", "email", "telefone"]) {
        if (String(data[k] ?? "").trim())
            score += 5;
    }
    return score;
}
function pickRicherPatch(target, source) {
    const patch = {};
    const keys = new Set([...Object.keys(target), ...Object.keys(source)]);
    for (const k of keys) {
        if (k.startsWith("_"))
            continue;
        const tv = target[k];
        const sv = source[k];
        const tEmpty = tv === undefined ||
            tv === null ||
            (typeof tv === "string" && !tv.trim()) ||
            (Array.isArray(tv) && tv.length === 0);
        const sHas = sv !== undefined &&
            sv !== null &&
            !(typeof sv === "string" && !String(sv).trim()) &&
            !(Array.isArray(sv) && sv.length === 0);
        if (tEmpty && sHas)
            patch[k] = sv;
        else if (typeof tv === "object" &&
            tv !== null &&
            !Array.isArray(tv) &&
            typeof sv === "object" &&
            sv !== null &&
            !Array.isArray(sv) &&
            docRichness(sv) >
                docRichness(tv)) {
            patch[k] = sv;
        }
    }
    return patch;
}
async function mergeRootProfiles(canonical, legacyIds, dryRun) {
    const ref = db().collection("igrejas").doc(canonical);
    let merged = (await ref.get()).data() ?? {};
    const patches = [];
    for (const leg of legacyIds) {
        const snap = await db().collection("igrejas").doc(leg).get();
        if (!snap.exists)
            continue;
        const patch = pickRicherPatch(merged, snap.data() ?? {});
        if (Object.keys(patch).length === 0)
            continue;
        merged = { ...merged, ...patch };
        patches.push(leg);
    }
    const finalPatch = {
        tenantId: canonical,
        igrejaId: canonical,
        churchId: canonical,
        canonicalTenantId: canonical,
        consolidatedFrom: legacyIds,
    };
    if (!dryRun) {
        finalPatch.consolidatedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (!String(merged.slug ?? "").trim()) {
        finalPatch.slug = "o-brasil-cristo-jardim-goiano";
        finalPatch.slugId = "o-brasil-cristo-jardim-goiano";
        finalPatch.alias = "o-brasil-cristo-jardim-goiano";
    }
    if (!String(merged.nome ?? merged.name ?? "").trim()) {
        finalPatch.nome = "Igreja O Brasil Para Cristo";
        finalPatch.name = "Igreja O Brasil Para Cristo";
    }
    finalPatch.ativa = merged.ativa !== false;
    finalPatch.status = merged.status ?? "ativa";
    Object.assign(finalPatch, pickRicherPatch(merged, finalPatch));
    if (!dryRun) {
        await ref.set(finalPatch, { merge: true });
    }
    return { canonical, patchedFrom: patches, fields: Object.keys(finalPatch).length };
}
function memberMergeKey(docId, data) {
    const cpf = normCpf(data.CPF ?? data.cpf ?? docId);
    if (cpf.length === 11)
        return `cpf:${cpf}`;
    return `id:${docId}`;
}
async function copySubcollectionPage(sourceId, targetId, collectionId, dryRun) {
    if (sourceId === targetId)
        return 0;
    let copied = 0;
    const sourceCol = db().collection("igrejas").doc(sourceId).collection(collectionId);
    const targetCol = db().collection("igrejas").doc(targetId).collection(collectionId);
    const seenMemberKeys = new Map();
    if (collectionId === "membros") {
        const existing = await targetCol.limit(500).get();
        for (const d of existing.docs) {
            seenMemberKeys.set(memberMergeKey(d.id, d.data()), d.id);
        }
    }
    let last;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = sourceCol.orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_LIMIT);
        if (last)
            q = q.startAfter(last.id);
        const page = await q.get();
        if (page.empty)
            break;
        let batch = db().batch();
        let ops = 0;
        for (const doc of page.docs) {
            let destId = doc.id;
            if (collectionId === "membros") {
                const key = memberMergeKey(doc.id, doc.data());
                const existingId = seenMemberKeys.get(key);
                if (existingId && existingId !== doc.id) {
                    destId = existingId;
                }
                else {
                    seenMemberKeys.set(key, destId);
                }
            }
            const destRef = targetCol.doc(destId);
            if (dryRun) {
                copied += 1;
                continue;
            }
            const existing = await destRef.get();
            if (!existing.exists) {
                batch.set(destRef, doc.data(), { merge: true });
                copied += 1;
                ops += 1;
            }
            else {
                const patch = pickRicherPatch(existing.data() ?? {}, doc.data());
                if (Object.keys(patch).length > 0) {
                    batch.set(destRef, patch, { merge: true });
                    copied += 1;
                    ops += 1;
                }
            }
            if (ops >= 400) {
                await batch.commit();
                batch = db().batch();
                ops = 0;
            }
        }
        if (!dryRun && ops > 0)
            await batch.commit();
        last = page.docs[page.docs.length - 1];
        if (page.size < BATCH_LIMIT)
            break;
    }
    return copied;
}
async function migrateAllSubcollections(canonical, legacyIds, dryRun) {
    const perCol = {};
    const colNames = new Set();
    for (const leg of legacyIds) {
        const cols = await db().collection("igrejas").doc(leg).listCollections();
        for (const c of cols)
            colNames.add(c.id);
    }
    const canonicalCols = await db().collection("igrejas").doc(canonical).listCollections();
    for (const c of canonicalCols)
        colNames.add(c.id);
    for (const colId of colNames) {
        if (colId === "_archive")
            continue;
        let n = 0;
        for (const leg of legacyIds) {
            n += await copySubcollectionPage(leg, canonical, colId, dryRun);
        }
        if (n > 0)
            perCol[colId] = n;
    }
    return perCol;
}
async function writeChurchAliases(canonical, legacyIds, dryRun) {
    const aliases = new Set([...legacyIds]);
    aliases.add("brasilparacristo");
    aliases.add("brasilparacristo_sistema");
    aliases.add("iobpc-jardim-goiano");
    aliases.add("o-brasil-cristo-jardim-goiano");
    aliases.add("brasil-para-cristo");
    aliases.add("bpc_jd");
    aliases.delete(canonical);
    if (dryRun)
        return aliases.size;
    let batch = db().batch();
    let ops = 0;
    for (const alias of aliases) {
        batch.set(db().collection("church_aliases").doc(alias), {
            canonicalId: canonical,
            alias,
            redirectOnly: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "consolidateBpcCluster",
        }, { merge: true });
        ops += 1;
        if (ops >= 400) {
            await batch.commit();
            batch = db().batch();
            ops = 0;
        }
    }
    if (ops > 0)
        await batch.commit();
    return aliases.size;
}
async function repointUsers(canonical, legacyIds, dryRun) {
    let updated = 0;
    for (const leg of legacyIds) {
        for (const field of ["tenantId", "igrejaId"]) {
            const snap = await db().collection("users").where(field, "==", leg).limit(500).get();
            if (snap.empty)
                continue;
            if (dryRun) {
                updated += snap.size;
                continue;
            }
            let batch = db().batch();
            let ops = 0;
            for (const doc of snap.docs) {
                batch.update(doc.ref, {
                    tenantId: canonical,
                    igrejaId: canonical,
                    canonicalTenantId: canonical,
                    tenantConsolidatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                ops += 1;
                updated += 1;
                if (ops >= 400) {
                    await batch.commit();
                    batch = db().batch();
                    ops = 0;
                }
            }
            if (ops > 0)
                await batch.commit();
        }
    }
    return updated;
}
async function deleteLegacyChurches(legacyIds, dryRun) {
    const deleted = [];
    for (const leg of legacyIds) {
        const ref = db().collection("igrejas").doc(leg);
        const snap = await ref.get();
        if (!snap.exists)
            continue;
        if (dryRun) {
            deleted.push(leg);
            continue;
        }
        await db().recursiveDelete(ref);
        deleted.push(leg);
    }
    return deleted;
}
async function runConsolidateBpcToCanonical(options = {}) {
    const dryRun = options.dryRun === true;
    const skipDelete = options.skipDelete === true;
    const canonical = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
    const legacyIds = bpcLegacyTenantIds();
    const metaRef = db().collection("igrejas").doc(canonical).collection("_meta").doc(META_DOC);
    if (!dryRun) {
        await metaRef.set({
            status: "running",
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            legacyIds,
        }, { merge: true });
    }
    const rootMerge = await mergeRootProfiles(canonical, legacyIds, dryRun);
    const perCollection = await migrateAllSubcollections(canonical, legacyIds, dryRun);
    let mpSync = { skipped: dryRun };
    if (!dryRun) {
        try {
            const { runSyncChurchMercadoPagoFromCluster } = await Promise.resolve().then(() => __importStar(require("./syncChurchMercadoPagoCluster")));
            mpSync = await runSyncChurchMercadoPagoFromCluster(canonical);
        }
        catch (e) {
            mpSync = { error: String(e) };
        }
    }
    const aliasesWritten = await writeChurchAliases(canonical, legacyIds, dryRun);
    const usersUpdated = await repointUsers(canonical, legacyIds, dryRun);
    let deletedLegacy = [];
    if (!skipDelete) {
        deletedLegacy = await deleteLegacyChurches(legacyIds, dryRun);
    }
    if (!dryRun && !options.skipPanelRecompute) {
        try {
            const { recomputePanelDashboardSummary } = await Promise.resolve().then(() => __importStar(require("./panelDashboardCache")));
            await recomputePanelDashboardSummary(canonical);
        }
        catch (e) {
            functions.logger.warn("consolidateBpc: panel recompute", { e });
        }
    }
    const result = {
        ok: true,
        dryRun,
        canonical,
        legacyIds,
        rootMerge,
        perCollection,
        mpSync,
        aliasesWritten,
        usersUpdated,
        deletedLegacy,
        skipDelete,
        status: dryRun ? "dry_run" : "completed",
        completedAt: dryRun ? null : admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!dryRun) {
        await metaRef.set(result, { merge: true });
    }
    functions.logger.info("consolidateBpcCluster", result);
    return result;
}
/** MASTER — consolida BPC num único doc e remove legados. */
exports.consolidateBpcChurchToCanonical = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "2GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const claims = (context.auth.token ?? {});
    const role = String(claims.role ?? "").toLowerCase();
    const email = String(claims.email ?? "").toLowerCase();
    const isMaster = claims.admin === true || role === "master" || email === "raihom@gmail.com";
    if (!isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Apenas MASTER pode consolidar o cluster BPC.");
    }
    const body = (data ?? {});
    return runConsolidateBpcToCanonical({
        dryRun: body.dryRun === true,
        skipDelete: body.skipDelete === true,
        skipPanelRecompute: body.skipPanelRecompute === true,
    });
});
/** Execução HTTP (MASTER/ops) — header `x-consolidate-key` ou query `key`. */
exports.consolidateBpcChurchToCanonicalHttp = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "2GB" })
    .https.onRequest(async (req, res) => {
    if (req.method !== "POST" && req.method !== "GET") {
        res.status(405).send("Method not allowed");
        return;
    }
    const expected = String(process.env.CONSOLIDATE_BPC_KEY || "").trim() ||
        "bpc-consolidate-gestaoyahweh-2026";
    const key = String(req.get("x-consolidate-key") || req.query.key || "").trim();
    if (!key || key !== expected) {
        res.status(403).json({ ok: false, error: "forbidden" });
        return;
    }
    const dryRun = req.query.dryRun === "true" ||
        String(req.body?.dryRun ?? "") === "true";
    const skipDelete = req.query.skipDelete === "true" ||
        String(req.body?.skipDelete ?? "") === "true";
    try {
        const result = await runConsolidateBpcToCanonical({
            dryRun,
            skipDelete,
            skipPanelRecompute: dryRun,
        });
        res.status(200).json(result);
    }
    catch (e) {
        functions.logger.error("consolidateBpcChurchToCanonicalHttp", e);
        res.status(500).json({ ok: false, error: String(e) });
    }
});
var churchClusterAnchors_2 = require("./churchClusterAnchors");
Object.defineProperty(exports, "BPC_PUBLIC_SLUG", { enumerable: true, get: function () { return churchClusterAnchors_2.BPC_PUBLIC_SLUG; } });
/** Subcoleções cujo conteúdo deve referenciar o tenant canónico BPC. */
const BPC_TENANT_SUBCOLLECTIONS = [
    "membros",
    "avisos",
    "eventos",
    "noticias",
    "agenda",
    "cargos",
    "escalas",
    "escala_templates",
    "departamentos",
    "patrimonio",
    "contas",
    "event_templates",
    "visitantes",
    "fornecedores",
    "pedidosOracao",
];
function memberLinkageNeedsPatch(data, canonical, publicSlug) {
    const patch = {};
    const want = {
        tenantId: canonical,
        igrejaId: canonical,
        churchId: canonical,
        churchCanonicalId: canonical,
        alias: publicSlug,
        slug: publicSlug,
        slugId: publicSlug,
    };
    for (const [k, v] of Object.entries(want)) {
        const cur = String(data[k] ?? "").trim();
        if (cur !== v)
            patch[k] = v;
    }
    return Object.keys(patch).length > 0 ? patch : null;
}
function tenantDocNeedsCanonicalPatch(data, canonical, publicSlug, legacyIds) {
    const patch = {};
    const legacySet = new Set(legacyIds);
    for (const field of ["tenantId", "igrejaId", "churchId", "churchCanonicalId"]) {
        const cur = String(data[field] ?? "").trim();
        if (!cur)
            continue;
        if (cur !== canonical && (legacySet.has(cur) || cur === publicSlug)) {
            patch[field] = canonical;
        }
    }
    for (const field of ["alias", "slug", "slugId"]) {
        const cur = String(data[field] ?? "").trim();
        if (!cur)
            continue;
        if (cur !== publicSlug && (legacySet.has(cur) || cur === canonical)) {
            patch[field] = publicSlug;
        }
    }
    return Object.keys(patch).length > 0 ? patch : null;
}
async function patchSubcollectionTenantLinkage(churchRef, collectionId, canonical, publicSlug, legacyIds, dryRun) {
    let scanned = 0;
    let updated = 0;
    let batch = db().batch();
    let ops = 0;
    const col = churchRef.collection(collectionId);
    let last;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = col.orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_LIMIT);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            scanned += 1;
            const patch = tenantDocNeedsCanonicalPatch(doc.data(), canonical, publicSlug, legacyIds);
            if (!patch)
                continue;
            if (dryRun) {
                updated += 1;
                continue;
            }
            patch.tenantLinkageSyncedAt = admin.firestore.FieldValue.serverTimestamp();
            batch.update(doc.ref, patch);
            ops += 1;
            updated += 1;
            if (ops >= BATCH_LIMIT) {
                await batch.commit();
                batch = db().batch();
                ops = 0;
            }
        }
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < BATCH_LIMIT)
            break;
    }
    if (!dryRun && ops > 0)
        await batch.commit();
    return { scanned, updated };
}
/** Alinha `alias`/`slug`/`tenantId` da igreja canónica, membros e demais subcoleções BPC. */
async function runSyncBpcMemberTenantLinkage(options = {}) {
    const dryRun = options.dryRun === true;
    const recomputeDirectory = options.recomputeDirectory !== false;
    const canonical = churchClusterAnchors_1.BPC_CANONICAL_IGREJA_ID;
    const publicSlug = churchClusterAnchors_1.BPC_PUBLIC_SLUG;
    const legacyIds = bpcLegacyTenantIds();
    const churchRef = db().collection("igrejas").doc(canonical);
    const churchSnap = await churchRef.get();
    if (!churchSnap.exists) {
        return { ok: false, error: "canonical_church_missing", canonical };
    }
    const churchData = churchSnap.data() ?? {};
    const churchPatch = {
        tenantId: canonical,
        igrejaId: canonical,
        churchId: canonical,
        canonicalTenantId: canonical,
        alias: publicSlug,
        slug: publicSlug,
        slugId: publicSlug,
    };
    if (!dryRun) {
        churchPatch.memberLinkageSyncedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    const churchNeedsUpdate = memberLinkageNeedsPatch(churchData, canonical, publicSlug);
    if (!dryRun && (churchNeedsUpdate || Object.keys(churchPatch).length > 0)) {
        await churchRef.set({ ...churchPatch, ...(churchNeedsUpdate ?? {}) }, { merge: true });
    }
    let membersScanned = 0;
    let membersUpdated = 0;
    let batch = db().batch();
    let ops = 0;
    const membrosCol = churchRef.collection("membros");
    let last;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = membrosCol.orderBy(admin.firestore.FieldPath.documentId()).limit(400);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            membersScanned += 1;
            const patch = memberLinkageNeedsPatch(doc.data(), canonical, publicSlug);
            if (!patch)
                continue;
            if (dryRun) {
                membersUpdated += 1;
                continue;
            }
            patch.memberLinkageSyncedAt = admin.firestore.FieldValue.serverTimestamp();
            batch.update(doc.ref, patch);
            ops += 1;
            membersUpdated += 1;
            if (ops >= BATCH_LIMIT) {
                await batch.commit();
                batch = db().batch();
                ops = 0;
            }
        }
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < 400)
            break;
    }
    if (!dryRun && ops > 0)
        await batch.commit();
    const subcollections = {};
    for (const colId of BPC_TENANT_SUBCOLLECTIONS) {
        if (colId === "membros")
            continue;
        subcollections[colId] = await patchSubcollectionTenantLinkage(churchRef, colId, canonical, publicSlug, legacyIds, dryRun);
    }
    let aliasesWritten = 0;
    if (!dryRun) {
        aliasesWritten = await writeChurchAliases(canonical, legacyIds, false);
    }
    else {
        aliasesWritten = await writeChurchAliases(canonical, legacyIds, true);
    }
    let usersUpdated = 0;
    const userTargets = new Set([canonical, ...legacyIds]);
    for (const leg of userTargets) {
        for (const field of ["tenantId", "igrejaId"]) {
            const snap = await db().collection("users").where(field, "==", leg).limit(500).get();
            if (snap.empty)
                continue;
            if (dryRun) {
                usersUpdated += snap.docs.filter((d) => {
                    const data = d.data();
                    return (String(data.tenantId ?? "").trim() !== canonical ||
                        String(data.igrejaId ?? "").trim() !== canonical);
                }).length;
                continue;
            }
            let uBatch = db().batch();
            let uOps = 0;
            for (const doc of snap.docs) {
                const data = doc.data();
                if (String(data.tenantId ?? "").trim() === canonical &&
                    String(data.igrejaId ?? "").trim() === canonical &&
                    String(data.churchCanonicalId ?? "").trim() === canonical) {
                    continue;
                }
                uBatch.update(doc.ref, {
                    tenantId: canonical,
                    igrejaId: canonical,
                    churchCanonicalId: canonical,
                    memberLinkageSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                uOps += 1;
                usersUpdated += 1;
                if (uOps >= BATCH_LIMIT) {
                    await uBatch.commit();
                    uBatch = db().batch();
                    uOps = 0;
                }
            }
            if (uOps > 0)
                await uBatch.commit();
        }
    }
    let directoryRecomputed = false;
    if (!dryRun && recomputeDirectory && membersUpdated > 0) {
        try {
            const all = await membrosCol.get();
            const { recomputeMembersDirectoryFromDocs } = await Promise.resolve().then(() => __importStar(require("./membersDirectoryCache")));
            await recomputeMembersDirectoryFromDocs(canonical, all.docs, all.size);
            directoryRecomputed = true;
        }
        catch (e) {
            functions.logger.warn("runSyncBpcMemberTenantLinkage directory", e);
        }
    }
    const result = {
        ok: true,
        dryRun,
        canonical,
        publicSlug,
        unifiedPath: `igrejas/${canonical}/…`,
        churchPatched: !dryRun,
        membersScanned,
        membersUpdated,
        subcollections,
        aliasesWritten,
        usersUpdated,
        directoryRecomputed,
        completedAt: dryRun ? null : admin.firestore.FieldValue.serverTimestamp(),
    };
    functions.logger.info("syncBpcMemberTenantLinkage", result);
    return result;
}
/** MASTER — alinha alias/slug/tenantId em todos os membros BPC. */
exports.syncBpcMemberTenantLinkage = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const claims = (context.auth.token ?? {});
    const role = String(claims.role ?? "").toLowerCase();
    const email = String(claims.email ?? "").toLowerCase();
    const isMaster = claims.admin === true || role === "master" || email === "raihom@gmail.com";
    if (!isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Apenas MASTER pode sincronizar ligação de membros BPC.");
    }
    const body = (data ?? {});
    return runSyncBpcMemberTenantLinkage({
        dryRun: body.dryRun === true,
        recomputeDirectory: body.recomputeDirectory !== false,
    });
});
/** HTTP ops — header `x-consolidate-key` ou query `key` (mesma chave da consolidação). */
exports.syncBpcMemberTenantLinkageHttp = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onRequest(async (req, res) => {
    if (req.method !== "POST" && req.method !== "GET") {
        res.status(405).send("Method not allowed");
        return;
    }
    const expected = String(process.env.CONSOLIDATE_BPC_KEY || "").trim() ||
        "bpc-consolidate-gestaoyahweh-2026";
    const key = String(req.get("x-consolidate-key") || req.query.key || "").trim();
    if (!key || key !== expected) {
        res.status(403).json({ ok: false, error: "forbidden" });
        return;
    }
    const dryRun = req.query.dryRun === "true" ||
        String(req.body?.dryRun ?? "") === "true";
    try {
        const result = await runSyncBpcMemberTenantLinkage({
            dryRun,
            recomputeDirectory: true,
        });
        res.status(200).json(result);
    }
    catch (e) {
        functions.logger.error("syncBpcMemberTenantLinkageHttp", e);
        res.status(500).json({ ok: false, error: String(e) });
    }
});
//# sourceMappingURL=consolidateBpcCluster.js.map