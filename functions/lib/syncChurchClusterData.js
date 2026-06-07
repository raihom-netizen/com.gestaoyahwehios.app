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
exports.syncChurchClusterDataFromRichest = void 0;
exports.collectRelatedIgrejaDocIds = collectRelatedIgrejaDocIds;
exports.runSyncChurchClusterDataFromRichest = runSyncChurchClusterDataFromRichest;
/**
 * Copia subcoleções do doc irmão mais rico → tenant operacional (canónico).
 * Caso BPC: dados em `igreja_o_brasil_...` → `brasilparacristo_sistema`.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const META_DOC = "cluster_data_sync_v1";
const BATCH_LIMIT = 350;
const ANCHORED_CLUSTERS = {
    brasilparacristo_sistema: [
        "brasilparacristo_sistema",
        "brasilparacristo",
        "igreja_o_brasil_para_cristo_jardim_goiano",
        "iobpc-jardim-goiano",
    ],
};
const MIGRATE_COLLECTIONS = [
    "membros",
    "finance",
    "contas",
    "patrimonio",
    "departamentos",
    "despesas_fixas",
    "receitas_recorrentes",
    "visitantes",
    "cargos",
    "fornecedores",
    "event_templates",
    "agenda",
    "escalas",
    "avisos",
    "eventos",
];
const CONFIG_DOCS = [
    "finance_settings",
    "patrimonio",
    "mercado_pago",
    "payment_receiving",
];
function db() {
    return admin.firestore();
}
function addAnchoredCluster(seed, out) {
    const t = String(seed || "").trim();
    if (!t)
        return;
    for (const [key, members] of Object.entries(ANCHORED_CLUSTERS)) {
        if (key === t || members.includes(t)) {
            out.add(key);
            for (const m of members)
                out.add(m);
        }
    }
}
async function collectRelatedIgrejaDocIds(seed) {
    const ids = new Set();
    const raw = String(seed || "").trim();
    if (!raw)
        return [];
    ids.add(raw);
    addAnchoredCluster(raw, ids);
    for (const suf of ["_sistema", "_bpc"]) {
        if (raw.endsWith(suf))
            ids.add(raw.slice(0, -suf.length));
        else
            ids.add(`${raw}${suf}`);
    }
    try {
        const doc = await db().collection("igrejas").doc(raw).get();
        if (doc.exists) {
            const d = doc.data() || {};
            for (const field of ["slug", "alias", "slugId", "churchId"]) {
                const v = String(d[field] || "").trim();
                if (!v)
                    continue;
                for (const f of ["slug", "alias", "slugId"]) {
                    try {
                        const q = await db().collection("igrejas").where(f, "==", v).limit(12).get();
                        for (const x of q.docs)
                            ids.add(x.id);
                    }
                    catch {
                        /* índice opcional */
                    }
                }
            }
        }
    }
    catch {
        /* ignore */
    }
    for (const id of Array.from(ids))
        addAnchoredCluster(id, ids);
    return Array.from(ids);
}
async function scoreTenantData(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return 0;
    let score = 0;
    const weights = {
        membros: 8,
        finance: 4,
        patrimonio: 4,
        contas: 3,
        departamentos: 3,
        escalas: 3,
        event_templates: 2,
        agenda: 2,
    };
    await Promise.all(MIGRATE_COLLECTIONS.map(async (col) => {
        const w = weights[col] ?? 1;
        try {
            const snap = await db()
                .collection("igrejas")
                .doc(tid)
                .collection(col)
                .limit(1)
                .get();
            if (!snap.empty)
                score += w;
        }
        catch {
            /* ignore */
        }
    }));
    return score;
}
async function copyCollectionIfMissing(sourceId, targetId, collectionId) {
    let copied = 0;
    const sourceCol = db().collection("igrejas").doc(sourceId).collection(collectionId);
    const targetCol = db().collection("igrejas").doc(targetId).collection(collectionId);
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
            const dest = targetCol.doc(doc.id);
            const existing = await dest.get();
            if (existing.exists)
                continue;
            batch.set(dest, doc.data(), { merge: true });
            copied += 1;
            ops += 1;
            if (ops >= 400) {
                await batch.commit();
                batch = db().batch();
                ops = 0;
            }
        }
        if (ops > 0)
            await batch.commit();
        last = page.docs[page.docs.length - 1];
        if (page.size < BATCH_LIMIT)
            break;
    }
    return copied;
}
async function copyConfigDocs(sourceId, targetId) {
    const copied = [];
    for (const docId of CONFIG_DOCS) {
        try {
            const from = await db()
                .collection("igrejas")
                .doc(sourceId)
                .collection("config")
                .doc(docId)
                .get();
            if (!from.exists || !from.data())
                continue;
            const dest = db()
                .collection("igrejas")
                .doc(targetId)
                .collection("config")
                .doc(docId);
            const existing = await dest.get();
            if (existing.exists && Object.keys(existing.data() || {}).length > 0)
                continue;
            await dest.set(from.data() || {}, { merge: true });
            copied.push(`config/${docId}`);
        }
        catch {
            /* ignore */
        }
    }
    return copied;
}
async function runSyncChurchClusterDataFromRichest(tenantId, options) {
    const target = String(tenantId || "").trim();
    if (!target) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");
    }
    const force = options?.force === true;
    const metaRef = db().collection("igrejas").doc(target).collection("_meta").doc(META_DOC);
    if (!force) {
        const meta = await metaRef.get();
        if (meta.exists && meta.data()?.status === "completed") {
            return { ok: true, tenantId: target, alreadyCompleted: true, ...(meta.data() ?? {}) };
        }
    }
    const candidates = await collectRelatedIgrejaDocIds(target);
    let bestSource = target;
    let bestScore = await scoreTenantData(target);
    for (const cid of candidates) {
        if (cid === target)
            continue;
        const s = await scoreTenantData(cid);
        if (s > bestScore) {
            bestScore = s;
            bestSource = cid;
        }
    }
    if (!bestSource || bestSource === target || bestScore < 2) {
        return {
            ok: true,
            tenantId: target,
            migrated: false,
            reason: "target_already_richest_or_no_source",
            candidates,
            targetScore: bestScore,
        };
    }
    await metaRef.set({ status: "running", sourceTenantId: bestSource, startedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const perCollection = {};
    for (const col of MIGRATE_COLLECTIONS) {
        try {
            perCollection[col] = await copyCollectionIfMissing(bestSource, target, col);
        }
        catch (e) {
            perCollection[col] = -1;
            console.warn("syncChurchClusterData", col, e);
        }
    }
    const configCopied = await copyConfigDocs(bestSource, target);
    const totalCopied = Object.values(perCollection).filter((n) => n > 0).reduce((a, b) => a + b, 0);
    const result = {
        ok: true,
        tenantId: target,
        migrated: totalCopied > 0 || configCopied.length > 0,
        sourceTenantId: bestSource,
        sourceScore: bestScore,
        perCollection,
        configCopied,
        candidates,
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await metaRef.set(result, { merge: true });
    return result;
}
exports.syncChurchClusterDataFromRichest = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const tenantId = String(data?.tenantId ?? "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const claims = (context.auth.token ?? {});
    const claimTenant = String(claims.igrejaId ?? claims.tenantId ?? "").trim();
    const email = String(claims.email ?? "").toLowerCase();
    const isMaster = claims.admin === true ||
        String(claims.role ?? "").toLowerCase() === "master" ||
        email === "raihom@gmail.com";
    if (!isMaster && claimTenant !== tenantId) {
        const u = await db().collection("users").doc(context.auth.uid).get();
        const userTenant = String(u.data()?.tenantId ?? u.data()?.igrejaId ?? "").trim();
        const related = await collectRelatedIgrejaDocIds(tenantId);
        const allowed = userTenant === tenantId ||
            related.includes(userTenant) ||
            (claimTenant && related.includes(claimTenant));
        if (!allowed) {
            throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja.");
        }
    }
    const force = data?.force === true;
    return runSyncChurchClusterDataFromRichest(tenantId, { force });
});
//# sourceMappingURL=syncChurchClusterData.js.map