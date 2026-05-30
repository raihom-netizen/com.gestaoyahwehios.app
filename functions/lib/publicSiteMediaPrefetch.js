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
exports.warmPublicSiteFeedCache = void 0;
exports.recomputePublicSiteMediaPrefetch = recomputePublicSiteMediaPrefetch;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const panelMediaPrefetch_1 = require("./panelMediaPrefetch");
const MAX_POSTS = 30;
const MAX_PHOTOS_PER_POST = 6;
const MAX_PREFETCH_URLS = 96;
const RESOLVE_BATCH = 12;
function pickHttp(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http"))
            return v.trim();
    }
    return "";
}
function looksLikeVideoFile(url) {
    const low = url.toLowerCase().split("?")[0].split("#")[0];
    if (/\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?)/i.test(low))
        return false;
    return /\.(mp4|webm|mov|m4v|m3u8)(\?|$|\/)/i.test(low)
        || (low.includes("/videos/") && !/\.(jpg|jpeg|png|webp)/i.test(low));
}
function isYoutubeVimeo(url) {
    const low = url.toLowerCase();
    return low.includes("youtube.com") || low.includes("youtu.be") || low.includes("vimeo.com");
}
function collectHttpPhotoUrls(data) {
    const out = [];
    const seen = new Set();
    function push(raw) {
        if (typeof raw !== "string")
            return;
        const s = raw.trim().replace(/&amp;/g, "&");
        if (!s.startsWith("http") || seen.has(s))
            return;
        if (isYoutubeVimeo(s))
            return;
        if (looksLikeVideoFile(s))
            return;
        seen.add(s);
        out.push(s);
    }
    function fromMap(m) {
        for (const k of [
            "url",
            "downloadUrl",
            "downloadURL",
            "imageUrl",
            "image_url",
            "imagem_url",
            "imagemUrl",
            "fotoUrl",
            "thumbUrl",
            "thumb_url",
            "thumbnailUrl",
        ]) {
            push(m[k]);
        }
    }
    function fromList(raw) {
        if (!Array.isArray(raw))
            return;
        for (const e of raw) {
            if (typeof e === "string")
                push(e);
            else if (e && typeof e === "object")
                fromMap(e);
        }
    }
    for (const k of [
        "imagem_url",
        "imagemUrl",
        "imageUrl",
        "defaultImageUrl",
        "fotoUrl",
        "foto_url",
        "thumbUrl",
        "videoThumbUrl",
    ]) {
        push(data[k]);
    }
    const media = data.media;
    if (media && typeof media === "object" && !Array.isArray(media)) {
        fromMap(media);
    }
    else if (Array.isArray(media)) {
        fromList(media);
    }
    for (const k of [
        "photos",
        "imageUrls",
        "fotoUrls",
        "fotos",
        "attachments",
        "attachmentsUrls",
        "attachmentUrls",
    ]) {
        fromList(data[k]);
    }
    const iv = data.imageVariants;
    if (iv && typeof iv === "object") {
        for (const key of ["full_1920", "full", "medium_800", "medium", "thumb_200"]) {
            const e = iv[key];
            if (e && typeof e === "object")
                push(e.url);
            else
                push(e);
        }
    }
    const videos = data.videos;
    if (Array.isArray(videos)) {
        for (const e of videos) {
            if (!e || typeof e !== "object")
                continue;
            const m = e;
            push(m.thumbUrl);
            push(m.thumb_url);
            push(m.thumbnailUrl);
        }
    }
    return out;
}
function collectStoragePaths(tenantId, collection, postId, data) {
    const tid = tenantId.trim();
    const paths = [];
    const folder = collection === "avisos" ? "avisos" : "eventos";
    function add(raw) {
        if (typeof raw !== "string")
            return;
        const p = raw.trim().replace(/\\/g, "/").replace(/^\/+/, "");
        if (p.length > 4 && !p.includes(".."))
            paths.push(p);
    }
    add(data.imageStoragePath);
    add(data.thumbStoragePath);
    add(data.videoThumbStoragePath);
    for (const k of ["imageStoragePaths", "fotoStoragePaths"]) {
        const list = data[k];
        if (!Array.isArray(list))
            continue;
        for (const e of list)
            add(e);
    }
    if (paths.length === 0) {
        paths.push(`igrejas/${tid}/${folder}/${postId}/banner_evento.jpg`, `igrejas/${tid}/${folder}/${postId}/capa_aviso.jpg`, `igrejas/${tid}/${folder}/${postId}/galeria_0.jpg`, `igrejas/${tid}/${folder}/${postId}/galeria_1.jpg`);
    }
    const videos = data.videos;
    if (Array.isArray(videos)) {
        for (const e of videos) {
            if (!e || typeof e !== "object")
                continue;
            const m = e;
            add(m.storagePath);
            add(m.storage_path);
            add(m.videoStoragePath);
            add(m.thumbStoragePath);
        }
    }
    add(data.videoStoragePath);
    return paths;
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
        functions.logger.debug("publicSiteMediaPrefetch: path miss", { path, e });
        return null;
    }
}
async function resolveFirstPath(paths) {
    for (const p of paths) {
        const url = await firebaseDownloadUrlForPath(p);
        if (url)
            return url;
    }
    return null;
}
async function enrichPostMedia(tenantId, collection, postId, data) {
    const httpPhotos = collectHttpPhotoUrls(data);
    const paths = collectStoragePaths(tenantId, collection, postId, data);
    const resolved = [...httpPhotos];
    for (let i = 0; i < paths.length && resolved.length < MAX_PHOTOS_PER_POST; i++) {
        const url = await firebaseDownloadUrlForPath(paths[i]);
        if (url && !resolved.includes(url))
            resolved.push(url);
    }
    const feedCoverUrl = resolved[0] ?? null;
    let videoThumbUrl = pickHttp(data, ["videoThumbUrl", "thumbUrl", "thumb_url"]) || null;
    if (!videoThumbUrl) {
        for (const m of data.videos || []) {
            if (!m || typeof m !== "object")
                continue;
            const t = pickHttp(m, ["thumbUrl", "thumb_url"]);
            if (t) {
                videoThumbUrl = t;
                break;
            }
        }
    }
    if (!videoThumbUrl && paths.length > 0) {
        const thumbPath = paths.find((p) => p.includes("_thumb") || p.includes("/thumbs/"));
        if (thumbPath)
            videoThumbUrl = await firebaseDownloadUrlForPath(thumbPath);
    }
    let hostedVideoUrl = pickHttp(data, ["hostedVideoUrl", "videoUrl", "video_url"]);
    if (hostedVideoUrl && (!looksLikeVideoFile(hostedVideoUrl) || isYoutubeVimeo(hostedVideoUrl))) {
        hostedVideoUrl = "";
    }
    if (!hostedVideoUrl) {
        for (const m of data.videos || []) {
            if (!m || typeof m !== "object")
                continue;
            const v = pickHttp(m, ["videoUrl", "video_url", "url"]);
            if (v && looksLikeVideoFile(v) && !isYoutubeVimeo(v)) {
                hostedVideoUrl = v;
                break;
            }
        }
    }
    if (!hostedVideoUrl) {
        const vPath = paths.find((p) => looksLikeVideoFile(p) || p.includes("/videos/"));
        if (vPath)
            hostedVideoUrl = (await firebaseDownloadUrlForPath(vPath)) ?? "";
    }
    return {
        feedCoverUrl,
        photoUrls: resolved.slice(0, MAX_PHOTOS_PER_POST),
        videoThumbUrl,
        hostedVideoUrl: hostedVideoUrl || null,
    };
}
/**
 * Enriquece `public_feed` com URLs resolvidas (logo + capas + vídeos) para o site público
 * abrir fotos/vídeos sem rajada de getDownloadURL no cliente.
 */
async function recomputePublicSiteMediaPrefetch(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tid);
    const cacheRef = churchRef.collection("_performance_cache").doc("public_feed");
    const [churchSnap, cacheSnap] = await Promise.all([
        churchRef.get(),
        cacheRef.get(),
    ]);
    const churchData = (churchSnap.data() ?? {});
    const churchLogoUrl = await (0, panelMediaPrefetch_1.resolveChurchLogoUrl)(tid, churchData);
    const rawFeed = cacheSnap.data()?.data;
    if (!Array.isArray(rawFeed) || rawFeed.length === 0) {
        await cacheRef.set({
            churchLogoUrl: churchLogoUrl ?? null,
            prefetchUrls: churchLogoUrl ? [churchLogoUrl] : [],
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const prefetchUrls = [];
    const seenPrefetch = new Set();
    function addPrefetch(url) {
        const u = (url ?? "").trim();
        if (!u.startsWith("http") || seenPrefetch.has(u))
            return;
        if (prefetchUrls.length >= MAX_PREFETCH_URLS)
            return;
        seenPrefetch.add(u);
        prefetchUrls.push(u);
    }
    addPrefetch(churchLogoUrl);
    const enriched = [];
    for (let i = 0; i < rawFeed.length && i < MAX_POSTS; i++) {
        const row = rawFeed[i];
        if (!row || typeof row !== "object")
            continue;
        const base = row;
        const postId = String(base.id ?? "").trim();
        const collection = String(base.collection ?? "avisos").trim();
        if (!postId) {
            enriched.push(base);
            continue;
        }
        const churchRefPosts = churchRef.collection(collection === "avisos" ? "avisos" : "noticias");
        const postSnap = await churchRefPosts.doc(postId).get();
        const postData = (postSnap.data() ?? base);
        const media = await enrichPostMedia(tid, collection, postId, postData);
        const merged = {
            ...base,
            feedCoverUrl: media.feedCoverUrl,
            photoUrls: media.photoUrls,
            videoThumbUrl: media.videoThumbUrl,
            hostedVideoUrl: media.hostedVideoUrl,
        };
        enriched.push(merged);
        addPrefetch(media.feedCoverUrl);
        for (const p of media.photoUrls)
            addPrefetch(p);
        addPrefetch(media.videoThumbUrl);
        if (media.hostedVideoUrl && !looksLikeVideoFile(media.hostedVideoUrl)) {
            addPrefetch(media.hostedVideoUrl);
        }
        else if (media.hostedVideoUrl) {
            addPrefetch(media.videoThumbUrl);
        }
    }
    for (let i = MAX_POSTS; i < rawFeed.length; i++) {
        const row = rawFeed[i];
        if (row && typeof row === "object")
            enriched.push(row);
    }
    await cacheRef.set({
        data: enriched,
        churchLogoUrl: churchLogoUrl ?? null,
        prefetchUrls,
        mediaPrefetchAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    functions.logger.info("publicSiteMediaPrefetch: ok", {
        tenantId: tid,
        posts: enriched.length,
        prefetch: prefetchUrls.length,
        logo: !!churchLogoUrl,
    });
}
/** Visitante (incl. anónimo): aquece cache público se a igreja existir. */
exports.warmPublicSiteFeedCache = functions
    .region("us-central1")
    .https.onCall(async (request, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Sessão necessária.");
    }
    const body = (request || {});
    const tenantId = String(body.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId ausente");
    }
    const ig = await admin.firestore().collection("igrejas").doc(tenantId).get();
    if (!ig.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada");
    }
    const { refreshPublicFeedCacheForTenant } = await Promise.resolve().then(() => __importStar(require("./churchPerformancePack")));
    await refreshPublicFeedCacheForTenant(tenantId);
    return { ok: true, tenantId, warmed: true };
});
//# sourceMappingURL=publicSiteMediaPrefetch.js.map