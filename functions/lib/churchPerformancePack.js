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
exports.warmChurchPublicFeedCache = exports.getNoticiaSharePack = exports.refreshPublicFeedCacheOnNoticiaWrite = exports.refreshPublicFeedCacheOnAvisoWrite = exports.generatePublicFeedCache = exports.generateBirthdayCache = exports.compressVideo = exports.optimizeImage = void 0;
exports.refreshPublicFeedCacheForTenant = refreshPublicFeedCacheForTenant;
/**
 * Pacote definitivo de performance — Gestão YAHWEH
 * (índices Firestore + processamento Storage + caches agendados)
 *
 * Modelo real: `igrejas/{tenant}/avisos|noticias|membros|chat_media/…`
 * (não `posts` / `members` genéricos da spec de referência).
 */
const functions = __importStar(require("firebase-functions/v1"));
const sharp_1 = __importDefault(require("sharp"));
const adminDb_1 = require("./adminDb");
const tenantCallableResolve_1 = require("./tenantCallableResolve");
const WEBP_Q = 70;
const TIERS = [
    { key: "thumb_200", edge: 200 },
    { key: "medium_800", edge: 800 },
    { key: "full_1920", edge: 1920 },
];
function isImageContentType(ct) {
    return !!ct && ct.startsWith("image/");
}
function isVariantPath(name) {
    return (/_(thumb_200|medium_800|full_1920)\.webp$/i.test(name) ||
        /profile_(thumb|medium)\.webp$/i.test(name) ||
        /_thumb\.webp$/i.test(name) ||
        name.includes("/thumbs/"));
}
async function saveWebp(destPath, buffer) {
    const file = (0, adminDb_1.storageBucket)().file(destPath);
    const token = adminDb_1.admin.firestore().collection("_meta").doc().id;
    await file.save(buffer, {
        metadata: {
            contentType: "image/webp",
            cacheControl: "public,max-age=31536000",
            metadata: { firebaseStorageDownloadTokens: token },
        },
        resumable: false,
    });
    const encoded = encodeURIComponent(destPath);
    return `https://firebasestorage.googleapis.com/v0/b/${(0, adminDb_1.storageBucket)().name}/o/${encoded}?alt=media&token=${token}`;
}
async function processMemberProfile(tenantId, memberId, srcPath) {
    const [buf] = await (0, adminDb_1.storageBucket)().file(srcPath).download();
    if (!buf || buf.length < 32)
        return;
    const fullPath = `igrejas/${tenantId}/membros/fotos/${memberId}.webp`;
    const thumbPath = `igrejas/${tenantId}/membros/thumbs/${memberId}.webp`;
    const [fullBuf, thumbBuf] = await Promise.all([
        (0, sharp_1.default)(buf).rotate().resize(1024, 1024, { fit: "cover" }).webp({ quality: 80 }).toBuffer(),
        (0, sharp_1.default)(buf).rotate().resize(200, 200, { fit: "cover" }).webp({ quality: 70 }).toBuffer(),
    ]);
    const [fotoUrl, fotoThumbUrl] = await Promise.all([
        saveWebp(fullPath, fullBuf),
        saveWebp(thumbPath, thumbBuf),
    ]);
    await (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .doc(memberId)
        .set({
        fotoUrl,
        fotoThumbUrl,
        FOTO_URL_OU_ID: fotoUrl,
        photoThumb: fotoThumbUrl,
        photoStoragePath: fullPath,
        photoThumbStoragePath: thumbPath,
        photoMedium: adminDb_1.admin.firestore.FieldValue.delete(),
        photoVariantsGeneratedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function processFeedImage(tenantId, collection, postId, baseName, srcPath) {
    const [buf] = await (0, adminDb_1.storageBucket)().file(srcPath).download();
    if (!buf || buf.length < 32)
        return;
    const folder = collection === "avisos" ? "avisos" : "eventos";
    const fileStem = baseName === "capa_aviso"
        ? `${postId}_capa`
        : baseName === "banner_evento"
            ? `${postId}_banner`
            : `${postId}_${baseName}`;
    const dest = `igrejas/${tenantId}/${folder}/imagens/${fileStem}.webp`;
    const out = await (0, sharp_1.default)(buf)
        .rotate()
        .resize(1920, 1920, { fit: "inside", withoutEnlargement: true })
        .webp({ quality: 78 })
        .toBuffer();
    const primary = await saveWebp(dest, out);
    const col = collection === "avisos" ? "avisos" : "eventos";
    const ref = (0, adminDb_1.fs)().collection("igrejas").doc(tenantId).collection(col).doc(postId);
    const snap = await ref.get();
    if (!snap.exists)
        return;
    await ref.set({
        imagem_url: primary,
        imageUrl: primary,
        serverVariantsGeneratedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
function parseUpload(name) {
    let m = name.match(/^igrejas\/([^/]+)\/membros\/fotos\/([^/]+)\.webp$/i);
    if (m)
        return { kind: "member", tenantId: m[1], memberId: m[2] };
    m = name.match(/^igrejas\/([^/]+)\/membros\/([^/]+)\/foto_perfil\.(jpg|jpeg|png|webp)$/i);
    if (m)
        return { kind: "member", tenantId: m[1], memberId: m[2] };
    m = name.match(/^igrejas\/([^/]+)\/avisos\/imagens\/([^_]+)_capa\.webp$/i);
    if (m) {
        return {
            kind: "feed",
            tenantId: m[1],
            collection: "avisos",
            postId: m[2],
            baseName: "capa_aviso",
        };
    }
    m = name.match(/^igrejas\/([^/]+)\/avisos\/([^/]+)\/(capa_aviso|galeria_\d+)\.(jpg|jpeg|png)$/i);
    if (m) {
        return {
            kind: "feed",
            tenantId: m[1],
            collection: "avisos",
            postId: m[2],
            baseName: m[3],
        };
    }
    m = name.match(/^igrejas\/([^/]+)\/eventos\/imagens\/([^_]+)_banner\.webp$/i);
    if (m) {
        return {
            kind: "feed",
            tenantId: m[1],
            collection: "eventos",
            postId: m[2],
            baseName: "banner_evento",
        };
    }
    m = name.match(/^igrejas\/([^/]+)\/eventos\/([^/]+)\/(banner_evento|galeria_\d+)\.(jpg|jpeg|png)$/i);
    if (m) {
        return {
            kind: "feed",
            tenantId: m[1],
            collection: "eventos",
            postId: m[2],
            baseName: m[3],
        };
    }
    return null;
}
/**
 * Gera WebP/thumbnails no servidor (perfil + avisos + eventos).
 * Equivalente à spec `optimizeImage`, adaptado ao Storage canónico YAHWEH.
 */
exports.optimizeImage = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 180, memory: "1GB" })
    .storage.object()
    .onFinalize(async (object) => {
    const name = object.name || "";
    if (!name || object.size === "0")
        return null;
    if (isVariantPath(name))
        return null;
    const ct = object.contentType || "";
    if (!isImageContentType(ct) && !/\.(jpe?g|png)$/i.test(name)) {
        return null;
    }
    try {
        const parsed = parseUpload(name);
        if (!parsed)
            return null;
        if (parsed.kind === "member") {
            await processMemberProfile(parsed.tenantId, parsed.memberId, name);
            functions.logger.info("optimizeImage: perfil", parsed);
            return true;
        }
        await processFeedImage(parsed.tenantId, parsed.collection, parsed.postId, parsed.baseName, name);
        functions.logger.info("optimizeImage: feed", parsed);
        return true;
    }
    catch (e) {
        functions.logger.error("optimizeImage", { name, e });
        return null;
    }
});
/**
 * Vídeo recebido no Storage — marca processamento e regista thumb esperada.
 * Compressão H264 pesada fica no cliente; aqui evita reprocessar o original em loop.
 */
exports.compressVideo = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .storage.object()
    .onFinalize(async (object) => {
    const ct = object.contentType || "";
    if (!ct.includes("video") && !/\.mp4$/i.test(object.name || "")) {
        return null;
    }
    const name = object.name || "";
    functions.logger.info("compressVideo: recebido", { name, ct });
    const m = name.match(/^igrejas\/([^/]+)\/eventos\/videos\/([^_]+)_v(\d)\.mp4$/i);
    if (!m)
        return true;
    const tenantId = m[1];
    const postId = m[2];
    const slot = Number(m[3]);
    const thumbPath = `igrejas/${tenantId}/eventos/thumbs/${postId}_v${slot}.webp`;
    await (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(tenantId)
        .collection("eventos")
        .doc(postId)
        .set({
        videoServerProcessedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
        videoThumbStoragePath: thumbPath,
    }, { merge: true });
    return true;
});
async function listActiveTenantIds(limit = 40) {
    try {
        const snap = await (0, adminDb_1.fs)()
            .collection("igrejas")
            .orderBy("updatedAt", "desc")
            .limit(limit)
            .get();
        if (!snap.empty)
            return snap.docs.map((d) => d.id);
    }
    catch (_) {
        /* índice updatedAt pode não existir em todas as bases */
    }
    const fallback = await (0, adminDb_1.fs)().collection("igrejas").limit(limit).get();
    return fallback.docs.map((d) => d.id);
}
function parseBirthMd(data) {
    const keys = ["DATA_NASCIMENTO", "dataNascimento", "birthDate", "nascimento"];
    for (const k of keys) {
        const raw = data[k];
        if (raw instanceof adminDb_1.admin.firestore.Timestamp) {
            const dt = raw.toDate();
            return { month: dt.getMonth() + 1, day: dt.getDate() };
        }
    }
    const bm = data.birthMonth;
    const bd = data.birthDay;
    if (typeof bm === "number" && typeof bd === "number") {
        return { month: bm, day: bd };
    }
    return null;
}
/**
 * Cache diário de aniversariantes por igreja (`_performance_cache/birthdays`).
 */
exports.generateBirthdayCache = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .pubsub.schedule("every 24 hours")
    .onRun(async () => {
    const month = new Date().getMonth() + 1;
    const tenantIds = await listActiveTenantIds(60);
    let written = 0;
    for (const tenantId of tenantIds) {
        try {
            const snap = await (0, adminDb_1.fs)()
                .collection("igrejas")
                .doc(tenantId)
                .collection("membros")
                .where("birthMonth", "==", month)
                .limit(80)
                .get();
            const birthdays = [];
            for (const doc of snap.docs) {
                const d = doc.data();
                const birth = parseBirthMd(d);
                if (!birth)
                    continue;
                birthdays.push({
                    memberDocId: doc.id,
                    displayName: String(d.NOME_COMPLETO ?? d.nome ?? "Membro"),
                    photoThumb: d.fotoThumbUrl ?? d.photoThumb ?? d.fotoUrl ?? null,
                    birthMonth: birth.month,
                    birthDay: birth.day,
                });
            }
            await (0, adminDb_1.fs)()
                .collection("igrejas")
                .doc(tenantId)
                .collection("_performance_cache")
                .doc("birthdays")
                .set({
                month,
                data: birthdays,
                updatedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
            });
            written += 1;
        }
        catch (e) {
            functions.logger.warn("generateBirthdayCache", { tenantId, e });
        }
    }
    functions.logger.info("generateBirthdayCache: fim", { month, churches: written });
    return true;
});
function lightPublicPost(id, collection, data) {
    return {
        id,
        collection,
        postId: id,
        docId: id,
        title: data.title ?? data.titulo ?? "",
        titulo: data.titulo ?? data.title ?? "",
        texto: data.texto ?? data.body ?? data.descricao ?? "",
        createdAt: data.createdAt ?? null,
        startAt: data.startAt ?? null,
        type: data.type ?? (collection === "avisos" ? "aviso" : "evento"),
        publishState: data.publishState ?? "published",
        publicSite: data.publicSite !== false,
        location: data.location ?? "",
        locationLat: data.locationLat ?? null,
        locationLng: data.locationLng ?? null,
        imageVariants: data.imageVariants ?? null,
        imagem_url: data.imagem_url ?? data.imageUrl ?? null,
        photoUrls: Array.isArray(data.photoUrls) ? data.photoUrls : null,
        feedCoverUrl: data.feedCoverUrl ?? null,
        hostedVideoUrl: data.hostedVideoUrl ?? null,
        videoThumbUrl: data.videoThumbUrl ?? null,
    };
}
/** Atualiza `public_feed` para uma igreja (reutilizado por cron e triggers). */
async function refreshPublicFeedCacheForTenant(tenantId) {
    const churchRef = (0, adminDb_1.fs)().collection("igrejas").doc(tenantId);
    const [avisosSnap, noticiasSnap] = await Promise.all([
        churchRef
            .collection("avisos")
            .where("publicSite", "==", true)
            .orderBy("createdAt", "desc")
            .limit(30)
            .get(),
        churchRef
            .collection("eventos")
            .where("publicSite", "==", true)
            .orderBy("createdAt", "desc")
            .limit(30)
            .get(),
    ]);
    const feed = [];
    for (const d of avisosSnap.docs) {
        feed.push(lightPublicPost(d.id, "avisos", d.data()));
    }
    for (const d of noticiasSnap.docs) {
        const data = d.data();
        if (String(data.type ?? "") !== "evento")
            continue;
        feed.push(lightPublicPost(d.id, "eventos", data));
    }
    feed.sort((a, b) => {
        const ta = a.createdAt?.toMillis?.() ?? 0;
        const tb = b.createdAt?.toMillis?.() ?? 0;
        return tb - ta;
    });
    await churchRef.collection("_performance_cache").doc("public_feed").set({
        data: feed.slice(0, 50),
        updatedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
        const { recomputePublicSiteMediaPrefetch } = await Promise.resolve().then(() => __importStar(require("./publicSiteMediaPrefetch")));
        await recomputePublicSiteMediaPrefetch(tenantId);
    }
    catch (e) {
        functions.logger.warn("refreshPublicFeedCache: media prefetch", {
            tenantId,
            e,
        });
    }
    try {
        const { mirrorPublicSitePanelCache } = await Promise.resolve().then(() => __importStar(require("./panelPublicSiteCache")));
        await mirrorPublicSitePanelCache(tenantId);
    }
    catch (e) {
        functions.logger.warn("refreshPublicFeedCache: panel public_site", {
            tenantId,
            e,
        });
    }
}
/**
 * Cache do feed público por igreja (avisos + eventos publicSite) — leitura instantânea no site.
 */
exports.generatePublicFeedCache = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .pubsub.schedule("every 10 minutes")
    .onRun(async () => {
    const tenantIds = await listActiveTenantIds(40);
    let written = 0;
    for (const tenantId of tenantIds) {
        try {
            await refreshPublicFeedCacheForTenant(tenantId);
            written += 1;
        }
        catch (e) {
            functions.logger.warn("generatePublicFeedCache", { tenantId, e });
        }
    }
    functions.logger.info("generatePublicFeedCache: fim", { churches: written });
    return true;
});
/** Novo aviso/evento público → atualiza cache do site sem esperar o cron de 10 min. */
async function onPublicPostWrite(tenantId, after) {
    if (!after?.exists)
        return;
    const d = after.data();
    if (d.publicSite === false)
        return;
    const st = String(d.publishState ?? "published");
    if (st === "failed")
        return;
    try {
        await refreshPublicFeedCacheForTenant(tenantId);
    }
    catch (e) {
        functions.logger.warn("refreshPublicFeedCacheOnPost", { tenantId, e });
    }
}
exports.refreshPublicFeedCacheOnAvisoWrite = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{postId}")
    .onWrite((change, ctx) => onPublicPostWrite(ctx.params.tenantId, change.after));
exports.refreshPublicFeedCacheOnNoticiaWrite = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{postId}")
    .onWrite((change, ctx) => onPublicPostWrite(ctx.params.tenantId, change.after));
/** Warmup explícito pós-publicação: atualiza cache público imediatamente. */
/**
 * Pacote de mídia para partilha instantânea (URLs https já resolvidas no servidor).
 * Evita rajada de getDownloadURL / Storage no cliente ao compartilhar aviso/evento.
 */
exports.getNoticiaSharePack = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 25, memory: "256MB" })
    .https.onCall(async (request, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {});
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(body.tenantId || body.churchId || ""));
    const postId = String(body.postId || body.noticiaId || body.id || "").trim();
    const collectionRaw = String(body.collection || body.kind || "eventos").trim();
    const collection = collectionRaw === "avisos" ? "avisos" : "eventos";
    if (!tenantId || !postId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e postId obrigatorios");
    }
    const db = (0, adminDb_1.fs)();
    const postSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection(collection)
        .doc(postId)
        .get();
    if (!postSnap.exists) {
        throw new functions.https.HttpsError("not-found", "publicacao nao encontrada");
    }
    const postData = (postSnap.data() ?? {});
    // Atalho rápido: https no doc (fotos + vídeo) sem listar Storage — estilo Instagram.
    const { collectHttpPhotoUrls, collectHostedVideoUrl, collectVideoThumbUrl, enrichPostMedia, } = await Promise.resolve().then(() => __importStar(require("./publicSiteMediaPrefetch")));
    const postRec = postData;
    const quickPhotos = collectHttpPhotoUrls(postRec);
    const quickVideo = collectHostedVideoUrl(postRec);
    const quickThumb = collectVideoThumbUrl(postRec);
    if (quickPhotos.length > 0 || quickVideo) {
        return {
            ok: true,
            tenantId,
            postId,
            collection,
            photoUrls: quickPhotos.slice(0, 6),
            feedCoverUrl: quickPhotos[0] ?? quickThumb ?? null,
            videoThumbUrl: quickThumb,
            hostedVideoUrl: quickVideo,
            fastPath: true,
        };
    }
    const media = await enrichPostMedia(tenantId, collection, postId, postData);
    return {
        ok: true,
        tenantId,
        postId,
        collection,
        photoUrls: media.photoUrls,
        feedCoverUrl: media.feedCoverUrl,
        videoThumbUrl: media.videoThumbUrl,
        hostedVideoUrl: media.hostedVideoUrl,
    };
});
exports.warmChurchPublicFeedCache = functions
    .region("us-central1")
    .https.onCall(async (request, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {});
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(body.tenantId || ""));
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    await refreshPublicFeedCacheForTenant(tenantId);
    return { ok: true, tenantId, warmed: true };
});
// release 2124 share video fast-path 2026-07-22T09:28:22.6247507-03:00
//# sourceMappingURL=churchPerformancePack.js.map