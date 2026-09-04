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
exports.scheduledCleanupExpiredTemporaryEvents = void 0;
/**
 * Retencao de eventos temporarios.
 *
 * Eventos com validade nunca entram na Galeria. Depois de 24 horas da
 * validade, remove documento, subcolecoes e a pasta canonica no Storage.
 * Eventos permanentes (sem validUntil ou galleryPermanent=true) sao preservados.
 */
const functions = __importStar(require("firebase-functions/v1"));
const adminDb_1 = require("./adminDb");
const PAGE_SIZE = 200;
function safeSegment(value) {
    return String(value ?? "")
        .trim()
        .replace(/[^a-zA-Z0-9_-]/g, "_");
}
exports.scheduledCleanupExpiredTemporaryEvents = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .pubsub.schedule("every 6 hours")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const cutoff = adminDb_1.admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
    const snap = await (0, adminDb_1.fs)()
        .collectionGroup("eventos")
        .where("validUntil", "<=", cutoff)
        .limit(PAGE_SIZE)
        .get();
    let deleted = 0;
    let skipped = 0;
    for (const doc of snap.docs) {
        const data = doc.data();
        if (String(data.type ?? "") !== "evento" || data.galleryPermanent === true) {
            skipped += 1;
            continue;
        }
        const tenantId = safeSegment(doc.ref.parent.parent?.id);
        const eventId = safeSegment(doc.id);
        if (!tenantId || !eventId) {
            skipped += 1;
            continue;
        }
        // Apaga primeiro a pasta para a limpeza nao depender apenas do trigger
        // onDelete. ignoreNotFound torna a operacao idempotente.
        await (0, adminDb_1.storageBucket)()
            .deleteFiles({ prefix: `igrejas/${tenantId}/eventos/${eventId}/` })
            .catch((error) => {
            functions.logger.warn("eventExpirationCleanup storage", {
                tenantId,
                eventId,
                error,
            });
        });
        await (0, adminDb_1.fs)().recursiveDelete(doc.ref);
        deleted += 1;
    }
    functions.logger.info("scheduledCleanupExpiredTemporaryEvents done", {
        cutoff: cutoff.toDate().toISOString(),
        found: snap.size,
        deleted,
        skipped,
    });
});
//# sourceMappingURL=eventExpirationCleanup.js.map