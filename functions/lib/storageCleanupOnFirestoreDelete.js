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
exports.onIgrejaPatrimonioDeleteCleanupStorage = exports.onIgrejaNoticiaDeleteCleanupStorage = exports.onIgrejaMembroDeleteCleanupStorage = void 0;
/**
 * Remove objetos do Storage quando o documento Firestore correspondente é apagado.
 * Complementa o cliente (ex.: deleteMemberRelatedFiles): reforço no servidor.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
function safeSeg(s) {
    return String(s || "")
        .trim()
        .replace(/[^a-zA-Z0-9_-]/g, "_");
}
async function deleteByPrefix(prefix) {
    const p = prefix.replace(/\/+$/, "");
    if (!p)
        return;
    const bucket = admin.storage().bucket();
    try {
        await bucket.deleteFiles({ prefix: `${p}/` });
    }
    catch (e) {
        functions.logger.warn(`storageCleanup: prefix ${p}/`, e);
    }
}
async function deleteIfExists(path) {
    if (!path)
        return;
    try {
        await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
    }
    catch (e) {
        functions.logger.warn(`storageCleanup: file ${path}`, e);
    }
}
/** Pasta por membro + ficheiros planos legados `{id}.jpg`. */
exports.onIgrejaMembroDeleteCleanupStorage = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/membros/{memberId}")
    .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId);
    const memberId = safeSeg(ctx.params.memberId);
    if (!tenantId || !memberId)
        return;
    const base = `igrejas/${tenantId}/membros/${memberId}`;
    await deleteByPrefix(base);
    for (const ext of ["jpg", "jpeg", "png", "webp"]) {
        await deleteIfExists(`${base}.${ext}`);
    }
    for (const suf of ["_thumb", "_card", "_full", "_gestor"]) {
        await deleteIfExists(`${base}${suf}.jpg`);
    }
    await deleteIfExists(`${base}_assinatura.png`);
    await deleteIfExists(`${base}_digital.png`);
});
/** Post do mural (evento ou aviso): pastas canónicas + prefixo legado noticias/. */
exports.onIgrejaNoticiaDeleteCleanupStorage = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/noticias/{postId}")
    .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId);
    const postId = safeSeg(ctx.params.postId);
    if (!tenantId || !postId)
        return;
    await deleteByPrefix(`igrejas/${tenantId}/eventos/${postId}`);
    await deleteByPrefix(`igrejas/${tenantId}/avisos/${postId}`);
    await deleteByPrefix(`igrejas/${tenantId}/noticias/${postId}`);
});
/** Património: pasta `patrimonio/{id}/` + ficheiros planos `{id}_{slot}.jpg` (legado). */
exports.onIgrejaPatrimonioDeleteCleanupStorage = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/patrimonio/{itemId}")
    .onDelete(async (_snap, ctx) => {
    const tenantId = safeSeg(ctx.params.tenantId);
    const itemId = safeSeg(ctx.params.itemId);
    if (!tenantId || !itemId)
        return;
    await deleteByPrefix(`igrejas/${tenantId}/patrimonio/${itemId}`);
    for (let slot = 0; slot <= 4; slot++) {
        const base = `igrejas/${tenantId}/patrimonio/${itemId}_${slot}`;
        await deleteIfExists(`${base}.jpg`);
        for (const suf of ["_thumb", "_card", "_full"]) {
            await deleteIfExists(`${base}${suf}.jpg`);
        }
    }
});
//# sourceMappingURL=storageCleanupOnFirestoreDelete.js.map