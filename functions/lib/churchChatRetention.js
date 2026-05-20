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
exports.pruneExpiredChurchChatMessages = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
/**
 * Remove mensagens de chat expiradas (texto ~30d, mídia ~3d — campo expiresAt)
 * e apaga o ficheiro no Storage quando existir storagePath.
 */
exports.pruneExpiredChurchChatMessages = functions
    .region("us-central1")
    .pubsub.schedule("every 6 hours")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const now = admin.firestore.Timestamp.now();
    let deleted = 0;
    const maxRounds = 20;
    for (let round = 0; round < maxRounds; round++) {
        let snap;
        try {
            snap = await db
                .collectionGroup("messages")
                .where("expiresAt", "<", now)
                .limit(500)
                .get();
        }
        catch (e) {
            functions.logger.warn("churchChatRetention: query falhou (índice?)", e);
            break;
        }
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            const d = doc.data();
            const path = String(d.storagePath || "").trim();
            if (path) {
                try {
                    await bucket.file(path).delete({ ignoreNotFound: true });
                }
                catch (e) {
                    functions.logger.warn("churchChatRetention: storage delete", { path, e });
                }
            }
            try {
                await doc.ref.delete();
                deleted++;
            }
            catch (e) {
                functions.logger.warn("churchChatRetention: firestore delete", { id: doc.id, e });
            }
        }
        if (snap.size < 500)
            break;
    }
    if (deleted === 0) {
        functions.logger.info("churchChatRetention: nada a expirar");
    }
    else {
        functions.logger.info(`churchChatRetention: removidas ${deleted} mensagens`);
    }
    return null;
});
//# sourceMappingURL=churchChatRetention.js.map