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
exports.getChurchStorageFootprint = void 0;
/**
 * Espaço REAL ocupado por uma igreja no Cloud Storage.
 *
 * A `getChurchStorageUsage` que já existia não mede o bucket: conta documentos
 * do Firestore e estima 1 KB por documento. Para responder «quanto esta igreja
 * ocupa em arquivos» é preciso listar `igrejas/{id}/` e somar os tamanhos —
 * só o Admin SDK consegue, e é o que esta função faz.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const tenantCallableResolve_1 = require("./tenantCallableResolve");
/** Agrupa por tipo a partir da extensão — o que o operador quer ver de relance. */
function groupOf(name) {
    const n = name.toLowerCase();
    if (/\.(jpg|jpeg|png|webp|gif|heic|bmp)$/.test(n))
        return "Imagens";
    if (/\.(mp4|mov|m4v|webm|avi|mkv)$/.test(n))
        return "Vídeos";
    if (/\.(pdf)$/.test(n))
        return "PDFs";
    if (/\.(mp3|m4a|aac|wav|ogg)$/.test(n))
        return "Áudio";
    return "Outros";
}
exports.getChurchStorageFootprint = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const uid = context.auth.uid;
    const email = String(context.auth.token?.email || "")
        .trim()
        .toLowerCase();
    const tenantId = String((data || {}).tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatorio");
    }
    const master = await (0, tenantCallableResolve_1.isMasterOperator)(uid, email, context.auth.token);
    if (!master && !(await (0, tenantCallableResolve_1.userCanAccessTenant)(uid, email, tenantId))) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissao para esta igreja");
    }
    const bucket = admin.storage().bucket();
    const prefix = `igrejas/${tenantId}/`;
    let totalBytes = 0;
    let totalFiles = 0;
    const groups = {};
    try {
        const [files] = await bucket.getFiles({ prefix });
        for (const f of files) {
            const size = Number(f.metadata?.size ?? 0) || 0;
            totalBytes += size;
            totalFiles++;
            const g = groupOf(f.name);
            if (!groups[g])
                groups[g] = { label: g, bytes: 0, files: 0 };
            groups[g].bytes += size;
            groups[g].files++;
        }
    }
    catch (e) {
        functions.logger.error("getChurchStorageFootprint", { tenantId, e });
        throw new functions.https.HttpsError("internal", "Falha ao medir o Storage da igreja.");
    }
    // Documentos do Firestore, para o cartão dar o quadro completo.
    let firestoreDocs = 0;
    try {
        const church = admin.firestore().collection("igrejas").doc(tenantId);
        const subs = ["membros", "eventos", "avisos", "financeiro", "patrimonio"];
        const counts = await Promise.all(subs.map((s) => church
            .collection(s)
            .count()
            .get()
            .then((r) => r.data().count ?? 0)
            .catch(() => 0)));
        firestoreDocs = counts.reduce((a, b) => a + b, 0);
    }
    catch (e) {
        functions.logger.warn("getChurchStorageFootprint: firestore", { e });
    }
    return {
        ok: true,
        tenantId,
        totalBytes,
        totalFiles,
        firestoreDocs,
        groups: Object.values(groups).sort((a, b) => b.bytes - a.bytes),
    };
});
//# sourceMappingURL=churchStorageFootprint.js.map