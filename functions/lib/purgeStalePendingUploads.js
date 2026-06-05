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
exports.scheduledPurgeStalePendingUploads = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const OPEN_STATUSES = ["pending", "failed", "uploading", "queued"];
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const CHURCH_BATCH = 40;
const DOCS_PER_CHURCH = 80;
const LEGACY_ROOT_BATCH = 200;
/**
 * Remove jobs antigos em `igrejas/{id}/pending_uploads` (fila descontinuada no cliente).
 * Apaga também restos da coleção raiz legada `pendingUploads` (sem espelho global).
 */
exports.scheduledPurgeStalePendingUploads = functions
    .region("southamerica-east1")
    .pubsub.schedule("every 24 hours")
    .onRun(async () => {
    const db = admin.firestore();
    const cutoff = Date.now() - MAX_AGE_MS;
    let deleted = 0;
    let churches = 0;
    let legacyRootDeleted = 0;
    const snap = await db.collection("igrejas").limit(CHURCH_BATCH).get();
    for (const church of snap.docs) {
        churches++;
        const col = church.ref.collection("pending_uploads");
        const q = await col
            .where("status", "in", OPEN_STATUSES)
            .limit(DOCS_PER_CHURCH)
            .get();
        if (q.empty)
            continue;
        const batch = db.batch();
        let ops = 0;
        for (const doc of q.docs) {
            const d = doc.data();
            const updated = d.updatedAt;
            const ts = updated?.toMillis() ?? 0;
            if (ts > 0 && ts > cutoff)
                continue;
            batch.delete(doc.ref);
            ops++;
            deleted++;
            if (ops >= 400)
                break;
        }
        if (ops > 0)
            await batch.commit();
    }
    // Coleção raiz legada — remover tudo (dados isolados ficam só em igrejas/{id}/pending_uploads).
    let legacySnap = await db
        .collection("pendingUploads")
        .limit(LEGACY_ROOT_BATCH)
        .get();
    while (!legacySnap.empty) {
        const batch = db.batch();
        for (const doc of legacySnap.docs) {
            batch.delete(doc.ref);
            legacyRootDeleted++;
        }
        await batch.commit();
        legacySnap = await db
            .collection("pendingUploads")
            .limit(LEGACY_ROOT_BATCH)
            .get();
    }
    functions.logger.info("scheduledPurgeStalePendingUploads", {
        churches,
        deleted,
        legacyRootDeleted,
    });
    return null;
});
//# sourceMappingURL=purgeStalePendingUploads.js.map