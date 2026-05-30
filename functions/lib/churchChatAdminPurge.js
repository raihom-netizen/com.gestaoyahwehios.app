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
exports.purgeChurchChatMessagesAdmin = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
function canManageChurchChatPurge(role) {
    const r = String(role || "").toUpperCase();
    return (r === "ADMIN" ||
        r === "ADM" ||
        r === "MASTER" ||
        r === "GESTOR" ||
        r === "PASTOR" ||
        r === "PASTOR_PRESIDENTE");
}
/**
 * Apaga todas as mensagens do chat da igreja (gestor/pastor/admin).
 * Mantém documentos `chat_threads`; limpa pré-visualização e filas auxiliares.
 */
exports.purgeChurchChatMessagesAdmin = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login no painel.");
    }
    const roleCaller = String(context.auth.token?.role || "").toUpperCase();
    if (!canManageChurchChatPurge(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Só gestor, pastor ou administrador pode limpar todo o chat.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const callerTenant = String(context.auth.token?.igrejaId || context.auth.token?.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId é obrigatório.");
    }
    if (callerTenant &&
        callerTenant !== tenantId &&
        roleCaller !== "ADMIN" &&
        roleCaller !== "ADM" &&
        roleCaller !== "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Igreja não autorizada.");
    }
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const threadsSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("chat_threads")
        .get();
    let deletedMessages = 0;
    let clearedThreads = 0;
    for (const threadDoc of threadsSnap.docs) {
        const messagesRef = threadDoc.ref.collection("messages");
        let hasMore = true;
        while (hasMore) {
            const batch = await messagesRef.limit(400).get();
            if (batch.empty) {
                hasMore = false;
                break;
            }
            const writeBatch = db.batch();
            let ops = 0;
            for (const msg of batch.docs) {
                const d = msg.data();
                const path = String(d.storagePath || "").trim();
                if (path) {
                    try {
                        await bucket.file(path).delete({ ignoreNotFound: true });
                    }
                    catch (_) {
                        /* ignore */
                    }
                }
                writeBatch.delete(msg.ref);
                ops++;
                deletedMessages++;
                if (ops >= 400)
                    break;
            }
            if (ops > 0)
                await writeBatch.commit();
            if (batch.size < 400)
                hasMore = false;
        }
        await threadDoc.ref.set({
            lastMessagePreview: "",
            lastMessageAt: admin.firestore.FieldValue.delete(),
            lastSenderUid: "",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        clearedThreads++;
    }
    let deletedUploads = 0;
    const uploadsSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("chat_uploads")
        .limit(500)
        .get();
    if (!uploadsSnap.empty) {
        const wb = db.batch();
        for (const u of uploadsSnap.docs) {
            wb.delete(u.ref);
            deletedUploads++;
        }
        await wb.commit();
    }
    let deletedPending = 0;
    const pendingSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("pending_uploads")
        .limit(500)
        .get();
    if (!pendingSnap.empty) {
        const wb = db.batch();
        for (const p of pendingSnap.docs) {
            wb.delete(p.ref);
            deletedPending++;
        }
        await wb.commit();
    }
    functions.logger.info("purgeChurchChatMessagesAdmin", {
        tenantId,
        deletedMessages,
        clearedThreads,
        deletedUploads,
        deletedPending,
        uid: context.auth.uid,
    });
    return {
        ok: true,
        deletedMessages,
        clearedThreads,
        deletedUploads,
        deletedPending,
    };
});
//# sourceMappingURL=churchChatAdminPurge.js.map