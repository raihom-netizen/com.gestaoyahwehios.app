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
exports.resolveChurchLogoUrl = resolveChurchLogoUrl;
exports.recomputePanelMediaPrefetch = recomputePanelMediaPrefetch;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const MAX_MEMBERS = 120;
const RESOLVE_BATCH = 16;
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim())
            return v.trim();
    }
    return "";
}
function pickHttpPhoto(data) {
    const keys = [
        "fotoUrl",
        "FOTO_URL_OU_ID",
        "photoUrl",
        "photoMedium",
        "photoThumb",
        "foto_url",
        "avatarUrl",
        "profilePhotoUrl",
        "logoProcessedUrl",
        "logoUrl",
        "logo_url",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http"))
            return v.trim();
    }
    return "";
}
function pickChurchLogoHttp(data) {
    const keys = [
        "logoProcessedUrl",
        "logoUrl",
        "logo_url",
        "brandLogoUrl",
        "churchLogoUrl",
        "tenantLogoUrl",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http"))
            return v.trim();
    }
    return "";
}
async function firebaseDownloadUrlForPath(objectPath) {
    const path = objectPath.replace(/^\/+/, "").trim();
    if (!path)
        return null;
    try {
        const bucket = admin.storage().bucket();
        const file = bucket.file(path);
        const [exists] = await file.exists();
        if (!exists)
            return null;
        const [meta] = await file.getMetadata();
        let token = meta.metadata?.firebaseStorageDownloadTokens;
        if (typeof token === "string" && token.includes(",")) {
            token = token.split(",")[0]?.trim();
        }
        if (!token || typeof token !== "string") {
            token = (0, crypto_1.randomUUID)();
            await file.setMetadata({
                metadata: { firebaseStorageDownloadTokens: token },
            });
        }
        const encoded = encodeURIComponent(path);
        return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
    }
    catch (e) {
        functions.logger.debug("panelMediaPrefetch: path miss", { path, e });
        return null;
    }
}
function memberStoragePaths(tenantId, memberDocId, cpfDigits, authUid) {
    const tid = tenantId.trim();
    const mid = memberDocId.trim();
    if (!tid || !mid)
        return [];
    const cpf = String(cpfDigits ?? "").replace(/\D/g, "");
    const uid = String(authUid ?? "").trim();
    const stems = new Set([mid]);
    if (cpf.length === 11)
        stems.add(cpf);
    if (uid && uid !== mid)
        stems.add(uid);
    const paths = [];
    for (const stem of stems) {
        paths.push(`igrejas/${tid}/membros/${stem}/thumb_foto_perfil.jpg`, `igrejas/${tid}/membros/${stem}/foto_perfil_thumb.jpg`, `igrejas/${tid}/membros/${stem}/foto_perfil.jpg`, `igrejas/${tid}/membros/${stem}/foto_perfil.webp`);
    }
    return paths;
}
async function resolveFirstPath(paths) {
    for (const p of paths) {
        const url = await firebaseDownloadUrlForPath(p);
        if (url)
            return url;
    }
    return null;
}
function collectMemberRefs(summary, directory) {
    const out = [];
    const seen = new Set();
    function add(raw) {
        const id = String(raw.memberDocId ?? "").trim();
        if (!id || seen.has(id))
            return;
        seen.add(id);
        out.push({
            memberDocId: id,
            photoUrl: raw.photoUrl ?? null,
            cpfDigits: raw.cpfDigits ?? null,
            authUid: raw.authUid ?? null,
        });
    }
    const lists = [
        "birthdaysToday",
        "birthdaysWeek",
        "birthdaysMonth",
        "homeLeaders",
        "homeCorpoAdmin",
    ];
    for (const key of lists) {
        const arr = summary?.[key];
        if (!Array.isArray(arr))
            continue;
        for (const e of arr) {
            if (e && typeof e === "object")
                add(e);
        }
    }
    const entries = directory?.entries;
    if (Array.isArray(entries)) {
        for (const e of entries) {
            if (e && typeof e === "object")
                add(e);
            if (out.length >= MAX_MEMBERS)
                break;
        }
    }
    return out.slice(0, MAX_MEMBERS);
}
async function resolveChurchLogoUrl(tenantId, churchData) {
    const http = pickChurchLogoHttp(churchData);
    if (http)
        return http;
    const tid = tenantId.trim();
    const custom = pickString(churchData, ["logoPath", "logoStoragePath"]);
    const paths = [];
    if (custom) {
        paths.push(custom.replace(/\\/g, "/").replace(/^\/+/, ""));
    }
    paths.push(`igrejas/${tid}/configuracoes/logo_igreja.png`, `igrejas/${tid}/configuracoes/logo_igreja.jpg`, `igrejas/${tid}/gestor/foto_perfil.jpg`, `igrejas/${tid}/logo/logo.jpg`, `igrejas/${tid}/branding/logo.png`);
    return resolveFirstPath(paths);
}
/**
 * `_panel_cache/media_prefetch` — URLs prontas (logo + fotos do painel) para o app
 * não disparar dezenas de `getDownloadURL` no cliente.
 */
async function recomputePanelMediaPrefetch(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tid);
    const cacheCol = churchRef.collection("_panel_cache");
    const [churchSnap, summarySnap, dirSnap] = await Promise.all([
        churchRef.get(),
        cacheCol.doc("dashboard_summary").get(),
        cacheCol.doc("members_directory").get(),
    ]);
    const churchData = (churchSnap.data() ?? {});
    const summary = (summarySnap.data() ?? {});
    const directory = (dirSnap.data() ?? {});
    const [churchLogoUrl, memberRefs] = await Promise.all([
        resolveChurchLogoUrl(tid, churchData),
        Promise.resolve(collectMemberRefs(summary, directory)),
    ]);
    const memberPhotoUrls = {};
    for (let i = 0; i < memberRefs.length; i += RESOLVE_BATCH) {
        const batch = memberRefs.slice(i, i + RESOLVE_BATCH);
        await Promise.all(batch.map(async (m) => {
            const http = (m.photoUrl ?? "").trim();
            if (http.startsWith("http")) {
                memberPhotoUrls[m.memberDocId] = http;
                return;
            }
            const fromDoc = pickHttpPhoto({
                photoUrl: m.photoUrl,
            });
            if (fromDoc) {
                memberPhotoUrls[m.memberDocId] = fromDoc;
                return;
            }
            const paths = memberStoragePaths(tid, m.memberDocId, m.cpfDigits, m.authUid);
            const url = await resolveFirstPath(paths);
            if (url)
                memberPhotoUrls[m.memberDocId] = url;
        }));
    }
    await cacheCol.doc("media_prefetch").set({
        schemaVersion: 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        churchLogoUrl: churchLogoUrl ?? null,
        memberPhotoUrls,
        memberCount: Object.keys(memberPhotoUrls).length,
    }, { merge: false });
    functions.logger.info("panelMediaPrefetch: ok", {
        tenantId: tid,
        logo: !!churchLogoUrl,
        members: Object.keys(memberPhotoUrls).length,
    });
}
//# sourceMappingURL=panelMediaPrefetch.js.map