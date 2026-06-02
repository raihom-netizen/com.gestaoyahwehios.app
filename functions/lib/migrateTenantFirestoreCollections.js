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
exports.migrateAllTenantsFirestoreCollections = exports.migrateTenantFirestoreCollections = void 0;
exports.runTenantFirestoreCollectionMigration = runTenantFirestoreCollectionMigration;
/**
 * Migração automática por igreja:
 * - `igrejas/{tenantId}/noticias` → `eventos` (+ subcoleções)
 * - `igrejas/{tenantId}/chat_threads` → `chats` (+ messages, typing, …)
 *
 * Idempotente: documentos já existentes no destino são atualizados com merge.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const META_DOC = "firestore_collection_migration_v1";
const BATCH_LIMIT = 400;
async function copyDocRecursive(source, dest) {
    const snap = await source.get();
    if (!snap.exists)
        return 0;
    await dest.set(snap.data() ?? {}, { merge: true });
    let n = 1;
    const subcols = await source.listCollections();
    for (const sub of subcols) {
        const destSub = dest.collection(sub.id);
        const docs = await sub.get();
        for (const d of docs.docs) {
            n += await copyDocRecursive(d.ref, destSub.doc(d.id));
        }
    }
    return n;
}
async function migrateTopLevelCollection(tenantRef, fromId, toId, deleteSource) {
    const stats = { copied: 0, deleted: 0, skipped: 0 };
    const sourceCol = tenantRef.collection(fromId);
    const destCol = tenantRef.collection(toId);
    let last;
    // eslint-disable-next-line no-constant-condition
    while (true) {
        let q = sourceCol.orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_LIMIT);
        if (last)
            q = q.startAfter(last.id);
        const page = await q.get();
        if (page.empty)
            break;
        for (const doc of page.docs) {
            const destRef = destCol.doc(doc.id);
            stats.copied += await copyDocRecursive(doc.ref, destRef);
            if (deleteSource) {
                await deleteDocRecursive(doc.ref);
                stats.deleted += 1;
            }
        }
        last = page.docs[page.docs.length - 1];
        if (page.size < BATCH_LIMIT)
            break;
    }
    return stats;
}
async function deleteDocRecursive(ref) {
    const subcols = await ref.listCollections();
    for (const sub of subcols) {
        const docs = await sub.get();
        for (const d of docs.docs) {
            await deleteDocRecursive(d.ref);
        }
    }
    await ref.delete();
}
async function runTenantFirestoreCollectionMigration(tenantId, options) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");
    const db = admin.firestore();
    const tenantRef = db.collection("igrejas").doc(tid);
    const metaRef = tenantRef.collection("_meta").doc(META_DOC);
    const existing = await metaRef.get();
    if (existing.exists && existing.data()?.status === "completed") {
        return { tenantId: tid, alreadyCompleted: true, ...(existing.data() ?? {}) };
    }
    await metaRef.set({ status: "running", startedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const deleteSource = options?.deleteSource !== false;
    try {
        const noticias = await migrateTopLevelCollection(tenantRef, "noticias", "eventos", deleteSource);
        const chats = await migrateTopLevelCollection(tenantRef, "chat_threads", "chats", deleteSource);
        const result = {
            tenantId: tid,
            status: "completed",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            noticiasToEventos: noticias,
            chatThreadsToChats: chats,
            deleteSource,
        };
        await metaRef.set(result, { merge: true });
        return result;
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await metaRef.set({
            status: "error",
            error: msg.slice(0, 500),
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw e;
    }
}
/** Callable: migra a igreja do utilizador (ou master com tenantId no body). */
exports.migrateTenantFirestoreCollections = functions
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
    const token = await admin.auth().getUser(context.auth.uid);
    const claims = (context.auth.token ?? {});
    const claimTenant = String(claims.igrejaId ?? claims.tenantId ?? "").trim();
    const isMaster = claims.admin === true ||
        claims.role === "master" ||
        (token.email ?? "").toLowerCase() === "raihom@gmail.com";
    if (!isMaster && claimTenant !== tenantId) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja.");
    }
    const deleteSource = data?.deleteSource !== false;
    return runTenantFirestoreCollectionMigration(tenantId, { deleteSource });
});
/** Master: migra todas as igrejas (batch sequencial). */
exports.migrateAllTenantsFirestoreCollections = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "2GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const email = (token.email ?? "").toLowerCase();
    const claims = (context.auth.token ?? {});
    const isMaster = claims.admin === true || claims.role === "master" || email === "raihom@gmail.com";
    if (!isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Apenas master.");
    }
    const limit = Math.min(500, Math.max(1, parseInt(String(data?.limit ?? 200), 10) || 200));
    const snap = await admin.firestore().collection("igrejas").limit(limit).get();
    const results = [];
    for (const doc of snap.docs) {
        try {
            results.push(await runTenantFirestoreCollectionMigration(doc.id));
        }
        catch (e) {
            results.push({
                tenantId: doc.id,
                status: "error",
                error: e instanceof Error ? e.message : String(e),
            });
        }
    }
    return { processed: results.length, results };
});
//# sourceMappingURL=migrateTenantFirestoreCollections.js.map