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
exports.collectHttpPhotoUrls = collectHttpPhotoUrls;
exports.collectHostedVideoUrl = collectHostedVideoUrl;
exports.collectVideoThumbUrl = collectVideoThumbUrl;
exports.enrichPostMedia = enrichPostMedia;
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
        let s = raw.trim().replace(/&amp;/g, "&");
        if (!s.startsWith("http") || seen.has(s))
            return;
        if (isYoutubeVimeo(s))
            return;
        if (looksLikeVideoFile(s))
            return;
        // Share: preferir medium_800 (mais leve) quando o path for full_1920.
        s = s
            .replace(/_full_1920\.webp/gi, "_medium_800.webp")
            .replace(/_full_1920\.jpg/gi, "_medium_800.webp")
            .replace(/\/full_1920\./gi, "/medium_800.");
        if (seen.has(s))
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
        // Share / site: medium primeiro (rápido); full só se não houver medium.
        for (const key of ["medium_800", "medium", "full_1920", "full", "thumb_200"]) {
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
/** URL https de vídeo hospedado no doc (sem listar Storage) — partilha Instagram-fast. */
function collectHostedVideoUrl(data) {
    let hosted = pickHttp(data, ["hostedVideoUrl", "videoUrl", "video_url"]);
    if (hosted && (!looksLikeVideoFile(hosted) || isYoutubeVimeo(hosted))) {
        hosted = "";
    }
    if (!hosted) {
        const videos = data.videos;
        if (Array.isArray(videos)) {
            for (const e of videos) {
                if (!e || typeof e !== "object")
                    continue;
                const v = pickHttp(e, [
                    "videoUrl",
                    "video_url",
                    "url",
                    "downloadUrl",
                    "downloadURL",
                ]);
                if (v && looksLikeVideoFile(v) && !isYoutubeVimeo(v)) {
                    hosted = v;
                    break;
                }
            }
        }
    }
    return hosted || null;
}
/** Thumb do vídeo já em https no doc. */
function collectVideoThumbUrl(data) {
    const direct = pickHttp(data, [
        "videoThumbUrl",
        "video_thumb_url",
        "videoThumbnailUrl",
    ]);
    if (direct)
        return direct;
    const videos = data.videos;
    if (Array.isArray(videos)) {
        for (const e of videos) {
            if (!e || typeof e !== "object")
                continue;
            const t = pickHttp(e, [
                "thumbUrl",
                "thumb_url",
                "thumbnailUrl",
            ]);
            if (t)
                return t;
        }
    }
    return null;
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
function collectEventTemplateStoragePaths(tenantId, templateId) {
    return [
        `igrejas/${tenantId}/eventos/templates/${templateId}.jpg`,
        `igrejas/${tenantId}/event_templates/${templateId}.jpg`,
    ];
}
async function resolveEventTemplateCoverUrl(tenantId, templateId) {
    const urls = await Promise.all(collectEventTemplateStoragePaths(tenantId, templateId).map((p) => firebaseDownloadUrlForPath(p)));
    return urls.find((u) => u != null) ?? null;
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
    // Parallel: try all paths at once, pick first successful
    const results = await Promise.all(paths.map((p) => firebaseDownloadUrlForPath(p).then((url) => ({ p, url }))));
    for (const r of results) {
        if (r.url)
            return r.url;
    }
    return null;
}
async function enrichPostMedia(tenantId, collection, postId, data) {
    const httpPhotos = collectHttpPhotoUrls(data);
    const paths = collectStoragePaths(tenantId, collection, postId, data);
    // Parallel: resolve all storage paths at once (batch)
    const pathResults = await Promise.all(paths.slice(0, MAX_PHOTOS_PER_POST).map((p) => firebaseDownloadUrlForPath(p)));
    const resolved = [...httpPhotos];
    for (const url of pathResults) {
        if (url && resolved.length < MAX_PHOTOS_PER_POST && !resolved.includes(url)) {
            resolved.push(url);
        }
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
    // Parallel: resolve thumb and video paths together
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
    const extraPaths = [];
    if (!videoThumbUrl) {
        const thumbPath = paths.find((p) => p.includes("_thumb") || p.includes("/thumbs/"));
        if (thumbPath)
            extraPaths.push({ key: "thumb", path: thumbPath });
    }
    if (!hostedVideoUrl) {
        const vPath = paths.find((p) => looksLikeVideoFile(p) || p.includes("/videos/"));
        if (vPath)
            extraPaths.push({ key: "video", path: vPath });
    }
    if (extraPaths.length > 0) {
        const extraResults = await Promise.all(extraPaths.map((e) => firebaseDownloadUrlForPath(e.path).then((url) => ({ ...e, url }))));
        for (const r of extraResults) {
            if (r.key === "thumb" && r.url)
                videoThumbUrl = r.url;
            if (r.key === "video" && r.url)
                hostedVideoUrl = r.url;
        }
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
    // Prefetch fixed-event template covers used by the public site schedule.
    try {
        const templatesSnap = await churchRef
            .collection("event_templates")
            .where("active", "==", true)
            .limit(50)
            .get();
        const templateCoverResults = await Promise.all(templatesSnap.docs.map((d) => resolveEventTemplateCoverUrl(tid, d.id)));
        for (const url of templateCoverResults) {
            addPrefetch(url);
        }
    }
    catch (e) {
        functions.logger.warn("publicSiteMediaPrefetch: templates", { tenantId: tid, e });
    }
    const enriched = [];
    // Parallel: batch-fetch all post documents at once
    const postRefs = rawFeed.slice(0, MAX_POSTS).map((row) => {
        if (!row || typeof row !== "object")
            return null;
        const base = row;
        const postId = String(base.id ?? "").trim();
        const collection = String(base.collection ?? "avisos").trim();
        if (!postId)
            return null;
        const col = collection === "avisos" ? "avisos" : "eventos";
        return { postId, collection, base, ref: churchRef.collection(col).doc(postId) };
    });
    const postSnaps = await Promise.all(postRefs.map((r) => (r ? r.ref.get() : Promise.resolve(null))));
    // Parallel: enrich all post media at once
    const mediaResults = await Promise.all(postRefs.map((r, i) => {
        if (!r)
            return Promise.resolve(null);
        const snap = postSnaps[i];
        const postData = (snap?.data() ?? r.base);
        return enrichPostMedia(tid, r.collection, r.postId, postData);
    }));
    for (let i = 0; i < postRefs.length; i++) {
        const r = postRefs[i];
        if (!r) {
            const row = rawFeed[i];
            if (row && typeof row === "object")
                enriched.push(row);
            continue;
        }
        const media = mediaResults[i];
        if (!media) {
            enriched.push(r.base);
            continue;
        }
        const merged = {
            ...r.base,
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
    const { mirrorPublicSitePanelCache } = await Promise.resolve().then(() => __importStar(require("./panelPublicSiteCache")));
    await mirrorPublicSitePanelCache(tenantId);
    return { ok: true, tenantId, warmed: true };
});
//# sourceMappingURL=publicSiteMediaPrefetch.js.map