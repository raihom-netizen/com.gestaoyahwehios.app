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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.processChurchStorageMedia = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const sharp_1 = __importDefault(require("sharp"));
const db = admin.firestore();
const bucket = admin.storage().bucket();
const WEBP_QUALITY = 70;
function parseMemberProfileUpload(name) {
    // igrejas/{tenant}/membros/{memberId}/foto_perfil.jpg|webp|...
    const m = name.match(/^igrejas\/([^/]+)\/membros\/([^/]+)\/foto_perfil\.(jpg|jpeg|png|webp)$/i);
    if (!m)
        return null;
    return { tenantId: m[1], memberId: m[2] };
}
async function uploadVariant(destPath, buffer) {
    const file = bucket.file(destPath);
    await file.save(buffer, {
        metadata: { contentType: "image/webp", cacheControl: "public,max-age=31536000" },
        resumable: false,
    });
    const [meta] = await file.getMetadata();
    const token = meta.metadata?.firebaseStorageDownloadTokens;
    const encoded = encodeURIComponent(destPath);
    if (typeof token === "string" && token.length > 0) {
        return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token.split(",")[0]}`;
    }
    const [signed] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    return signed;
}
/**
 * Processamento server-side (V4): gera `profile_thumb.webp` + `profile_medium.webp`
 * quando o cliente envia só `foto_perfil` — reduz CPU em aparelhos fracos.
 */
exports.processChurchStorageMedia = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .storage.object()
    .onFinalize(async (object) => {
    const name = object.name || "";
    if (!name || object.size === "0")
        return null;
    const member = parseMemberProfileUpload(name);
    if (!member)
        return null;
    const { tenantId, memberId } = member;
    const src = bucket.file(name);
    const [buf] = await src.download();
    if (!buf || buf.length < 32)
        return null;
    const thumbBuf = await (0, sharp_1.default)(buf)
        .rotate()
        .resize(200, 200, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: WEBP_QUALITY })
        .toBuffer();
    const mediumBuf = await (0, sharp_1.default)(buf)
        .rotate()
        .resize(500, 500, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: WEBP_QUALITY })
        .toBuffer();
    const base = `igrejas/${tenantId}/membros/${memberId}`;
    const thumbPath = `${base}/profile_thumb.webp`;
    const mediumPath = `${base}/profile_medium.webp`;
    const [thumbUrl, mediumUrl] = await Promise.all([
        uploadVariant(thumbPath, thumbBuf),
        uploadVariant(mediumPath, mediumBuf),
    ]);
    const membroRef = db
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .doc(memberId);
    await membroRef.set({
        photoThumb: thumbUrl,
        photoMedium: mediumUrl,
        photoVariantsGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    functions.logger.info("processChurchStorageMedia: variantes perfil", {
        tenantId,
        memberId,
    });
    return null;
});
//# sourceMappingURL=processChurchStorageMedia.js.map