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
exports.onIgrejaMembroWriteChatPeerProfile = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim())
            return v.trim();
    }
    return "";
}
function pickPhotoUrl(data) {
    const keys = [
        "imagem_url",
        "imagemUrl",
        "fotoUrl",
        "fotoURL",
        "FOTO_URL",
        "imageUrl",
        "imageURL",
        "photoUrl",
        "photoURL",
        "urlFoto",
        "foto",
        "FOTO",
        "avatarUrl",
        "profilePhotoUrl",
        "logoProcessedUrl",
        "logoUrl",
        "photoMedium",
        "photoThumb",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http")) {
            return v.trim();
        }
    }
    return "";
}
function pickDisplayName(data) {
    const n = pickString(data, [
        "NOME_COMPLETO",
        "nome",
        "name",
        "displayName",
        "NOME",
    ]);
    if (n)
        return n.length > 120 ? n.substring(0, 120) : n;
    return "Membro";
}
/**
 * Denormaliza foto/nome do membro para leitura rápida no Chat Igreja
 * (`igrejas/{tenantId}/chat_peer_profiles/{authUid}`).
 */
exports.onIgrejaMembroWriteChatPeerProfile = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/membros/{membroId}")
    .onWrite(async (change, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    const membroId = String(context.params.membroId || "").trim();
    if (!tenantId || !membroId)
        return null;
    const after = change.after.exists ? change.after.data() : null;
    const authUid = after
        ? pickString(after, ["authUid", "firebaseUid", "uid", "userId"])
        : pickString((change.before.data() || {}), ["authUid", "firebaseUid", "uid", "userId"]);
    if (!authUid)
        return null;
    const profileRef = admin
        .firestore()
        .collection("igrejas")
        .doc(tenantId)
        .collection("chat_peer_profiles")
        .doc(authUid);
    if (!after) {
        try {
            await profileRef.delete();
        }
        catch (e) {
            functions.logger.warn("chatPeerProfile: delete", { tenantId, authUid, e });
        }
        return null;
    }
    const st = pickString(after, ["STATUS", "status"]).toLowerCase();
    if (st && st !== "ativo") {
        try {
            await profileRef.delete();
        }
        catch (_) { }
        return null;
    }
    const photoUrl = pickPhotoUrl(after);
    const displayName = pickDisplayName(after);
    const revRaw = after.fotoUrlCacheRevision ?? after.photoCacheRevision;
    const fotoUrlCacheRevision = typeof revRaw === "number" && Number.isFinite(revRaw)
        ? Math.floor(revRaw)
        : typeof revRaw === "string" && revRaw.trim()
            ? parseInt(revRaw, 10) || 0
            : 0;
    await profileRef.set({
        authUid,
        memberDocId: membroId,
        displayName,
        photoUrl: photoUrl || null,
        fotoUrlCacheRevision,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return null;
});
//# sourceMappingURL=churchChatPeerProfileSync.js.map