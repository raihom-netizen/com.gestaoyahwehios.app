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
exports.stampIgrejaChatMessageTenantFields = exports.stampIgrejaSubdocTenantFields = exports.backfillChurchTenantFields = void 0;
exports.backfillChurchTenantFieldsForChurch = backfillChurchTenantFieldsForChurch;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const churchTenantFields_1 = require("./churchTenantFields");
const churchTenantProvisioning_1 = require("./churchTenantProvisioning");
const BATCH_LIMIT = 400;
const DOC_PAGE = 200;
function isMasterCaller(context) {
    const email = String(context.auth?.token?.email ?? "").toLowerCase();
    if (email === "raihom@gmail.com")
        return true;
    const role = String(context.auth?.token?.role ?? "").toUpperCase();
    return role === "MASTER" || role === "ADM" || role === "ADMIN";
}
async function flushBatch(batch, counters) {
    if (counters.batchOps <= 0) {
        return batch;
    }
    await batch.commit();
    counters.batchesCommitted += 1;
    counters.batchOps = 0;
    return admin.firestore().batch();
}
async function queueStamp(ref, churchId, data, batch, counters) {
    counters.scanned += 1;
    if (!(0, churchTenantFields_1.needsTenantFieldsStamp)(data, churchId)) {
        counters.skipped += 1;
        return batch;
    }
    batch.set(ref, (0, churchTenantFields_1.tenantFieldsPatch)(churchId), { merge: true });
    counters.stamped += 1;
    counters.batchOps += 1;
    if (counters.batchOps >= BATCH_LIMIT) {
        return flushBatch(batch, counters);
    }
    return batch;
}
async function stampDocumentTree(firestore, docRef, churchId, counters, batch, maxDocs) {
    if (counters.scanned >= maxDocs)
        return batch;
    const snap = await docRef.get();
    if (snap.exists) {
        batch = await queueStamp(docRef, churchId, (snap.data() ?? {}), batch, counters);
    }
    if (counters.scanned >= maxDocs)
        return batch;
    let subcols;
    try {
        subcols = await docRef.listCollections();
    }
    catch {
        counters.errors += 1;
        return batch;
    }
    for (const col of subcols) {
        let last;
        for (;;) {
            if (counters.scanned >= maxDocs)
                break;
            let q = col.orderBy(admin.firestore.FieldPath.documentId()).limit(DOC_PAGE);
            if (last)
                q = q.startAfter(last);
            const page = await q.get();
            if (page.empty)
                break;
            for (const child of page.docs) {
                batch = await stampDocumentTree(firestore, child.ref, churchId, counters, batch, maxDocs);
                if (counters.scanned >= maxDocs)
                    break;
            }
            last = page.docs[page.docs.length - 1];
            if (page.size < DOC_PAGE)
                break;
        }
        if (counters.scanned >= maxDocs)
            break;
    }
    return batch;
}
/** Percorre recursivamente `igrejas/{churchId}/**` e grava churchId + tenantId. */
async function backfillChurchTenantFieldsForChurch(firestore, churchId, options = {}) {
    const id = String(churchId || "").trim();
    const maxDocs = Math.min(25000, Math.max(100, Number(options.maxDocs) || 8000));
    const counters = {
        stamped: 0,
        skipped: 0,
        scanned: 0,
        batchOps: 0,
        batchesCommitted: 0,
        errors: 0,
    };
    if (!id) {
        return {
            churchId: "",
            rootStamped: false,
            docsStamped: 0,
            docsSkipped: 0,
            docsScanned: 0,
            batchesCommitted: 0,
            errors: 1,
        };
    }
    let rootStamped = false;
    if (!options.skipRootProvision) {
        try {
            const provision = await (0, churchTenantProvisioning_1.provisionChurchTenant)(id, {
                source: "backfillChurchTenantFields",
                skipStorage: true,
            });
            rootStamped = provision.rootPatched;
        }
        catch (e) {
            functions.logger.warn("backfillChurchTenantFields provisionChurchTenant", {
                churchId: id,
                e,
            });
            counters.errors += 1;
        }
    }
    const churchRef = firestore.collection("igrejas").doc(id);
    let batch = firestore.batch();
    batch = await stampDocumentTree(firestore, churchRef, id, counters, batch, maxDocs);
    if (counters.batchOps > 0) {
        batch = await flushBatch(batch, counters);
    }
    return {
        churchId: id,
        rootStamped,
        docsStamped: counters.stamped,
        docsSkipped: counters.skipped,
        docsScanned: counters.scanned,
        batchesCommitted: counters.batchesCommitted,
        errors: counters.errors,
    };
}
/** Callable master — uma igreja ou todas (paginado por igreja). */
exports.backfillChurchTenantFields = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    if (!isMasterCaller(context)) {
        throw new functions.https.HttpsError("permission-denied", "Somente operador master.");
    }
    const db = admin.firestore();
    const one = String(data?.tenantId
        ?? data?.churchId
        ?? "").trim();
    const maxDocs = Number(data?.maxDocs) || 8000;
    if (one) {
        const stats = await backfillChurchTenantFieldsForChurch(db, one, { maxDocs });
        return { ok: true, churches: 1, stats: [stats] };
    }
    const statsList = [];
    let last;
    const page = 40;
    for (;;) {
        let q = db
            .collection("igrejas")
            .orderBy(admin.firestore.FieldPath.documentId())
            .limit(page);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            statsList.push(await backfillChurchTenantFieldsForChurch(db, doc.id, { maxDocs }));
        }
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < page)
            break;
    }
    return {
        ok: true,
        churches: statsList.length,
        totalStamped: statsList.reduce((n, s) => n + s.docsStamped, 0),
        stats: statsList,
    };
});
/** Auto-stamp em subcoleções directas (nível 1). */
exports.stampIgrejaSubdocTenantFields = functions
    .region("us-central1")
    .firestore.document("igrejas/{churchId}/{collectionId}/{docId}")
    .onWrite(async (change, context) => {
    if (!change.after.exists)
        return;
    const churchId = String(context.params.churchId).trim();
    const data = change.after.data();
    if (!(0, churchTenantFields_1.needsTenantFieldsStamp)(data, churchId))
        return;
    await change.after.ref.set((0, churchTenantFields_1.tenantFieldsPatch)(churchId, false), { merge: true });
});
/** Auto-stamp em mensagens de chat (nível 2). */
exports.stampIgrejaChatMessageTenantFields = functions
    .region("us-central1")
    .firestore.document("igrejas/{churchId}/chats/{chatId}/messages/{messageId}")
    .onWrite(async (change, context) => {
    if (!change.after.exists)
        return;
    const churchId = String(context.params.churchId).trim();
    const data = change.after.data();
    if (!(0, churchTenantFields_1.needsTenantFieldsStamp)(data, churchId))
        return;
    await change.after.ref.set((0, churchTenantFields_1.tenantFieldsPatch)(churchId, false), { merge: true });
});
//# sourceMappingURL=churchTenantFieldsBackfill.js.map