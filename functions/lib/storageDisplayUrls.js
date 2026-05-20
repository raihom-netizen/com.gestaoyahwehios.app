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
exports.resolveStorageDisplayUrls = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const MAX_PATHS = 48;
const SIGNED_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/**
 * Renova URLs de leitura do Storage em lote (painel / site / chat).
 * Reduz dezenas de getDownloadURL no cliente quando o painel abre listas grandes.
 */
exports.resolveStorageDisplayUrls = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const raw = data?.paths;
    if (!Array.isArray(raw)) {
        throw new functions.https.HttpsError("invalid-argument", "paths deve ser um array de strings.");
    }
    const paths = raw
        .map((p) => String(p ?? "").trim().replace(/\\/g, "/"))
        .filter((p) => p.length > 4 && !p.includes(".."))
        .slice(0, MAX_PATHS);
    if (paths.length === 0) {
        return { urls: {} };
    }
    const bucket = admin.storage().bucket();
    const expires = Date.now() + SIGNED_TTL_MS;
    const urls = {};
    await Promise.all(paths.map(async (objectPath) => {
        try {
            const file = bucket.file(objectPath);
            const [signed] = await file.getSignedUrl({
                action: "read",
                expires,
            });
            if (signed)
                urls[objectPath] = signed;
        }
        catch (e) {
            functions.logger.warn("resolveStorageDisplayUrls: falha", {
                objectPath,
                e,
            });
        }
    }));
    return { urls };
});
//# sourceMappingURL=storageDisplayUrls.js.map