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
exports.shareEvento = void 0;
/**
 * Página leve para rastreadores (WhatsApp, Telegram, etc.): Open Graph com capa do evento/aviso.
 * O app compartilha só /s/evento?c=&e= — sem URLs longas do Firebase Storage na mensagem.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const BASE = "https://gestaoyahweh.com.br";
const DEFAULT_OG_IMAGE = `${BASE}/icons/Icon-512.png`;
function getStorageBucket() {
    try {
        const opts = admin.app().options;
        return String(opts?.storageBucket || process.env.FIREBASE_STORAGE_BUCKET || "").trim();
    }
    catch (_) {
        return "";
    }
}
function isYoutubeVimeo(raw) {
    const low = raw.toLowerCase();
    return low.includes("youtube.com") || low.includes("youtu.be") || low.includes("vimeo.com");
}
function normalizeStorageMediaUrl(raw) {
    if (typeof raw !== "string")
        return "";
    let t = raw.trim();
    if (!t)
        return "";
    if (/^https?:\/\//i.test(t))
        return t;
    const low = t.toLowerCase();
    if (!low.includes("://") && low.includes(".firebasestorage.app")) {
        return `https://${t}`;
    }
    if (low.startsWith("firebasestorage.googleapis.com")) {
        return `https://${t}`;
    }
    const bucket = getStorageBucket();
    /** Fotos e vídeos: Firestore às vezes grava só o caminho do objeto (sem token). */
    const looksLikePath = (low.includes("igrejas/") ||
        low.includes("membros/") ||
        low.includes("members/") ||
        low.includes("patrimonio/") ||
        low.includes("certificado_logos/") ||
        low.includes("carteira_logos/") ||
        low.includes("cartao_membro/") ||
        low.includes("noticias/") ||
        low.includes("avisos/") ||
        low.includes("eventos/") ||
        low.includes("videos/") ||
        low.includes("videos%2f") ||
        low.includes("departamentos/")) &&
        (low.includes("/") || low.includes("%2f")) &&
        !low.includes("firebasestorage.googleapis.com");
    if (looksLikePath && bucket) {
        const pathPart = t.replace(/^\/+/, "").replace(/\\/g, "/");
        const encoded = pathPart.includes("%") ? pathPart : encodeURIComponent(pathPart);
        return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encoded}?alt=media`;
    }
    return t;
}
/** Caminho do objeto no bucket a partir de URL HTTP do Storage (googleapis ou *.firebasestorage.app). */
function firebaseStorageObjectPathFromHttpUrl(raw) {
    const t = raw.trim();
    if (!t)
        return null;
    try {
        const withProto = /^https?:\/\//i.test(t) ? t : `https://${t}`;
        const uri = new URL(withProto);
        const host = uri.hostname.toLowerCase();
        const segs = uri.pathname.split("/").filter(Boolean);
        if (host.includes("firebasestorage.googleapis.com")) {
            if (segs.length >= 5 && segs[0] === "v0" && segs[1] === "b" && segs[3] === "o") {
                const enc = segs.slice(4).join("/");
                if (!enc)
                    return null;
                return decodeURIComponent(enc.replace(/\+/g, " "));
            }
        }
        if (host.includes("firebasestorage.app") && segs[0] === "o" && segs.length >= 2) {
            const enc = segs.slice(1).join("/");
            if (!enc)
                return null;
            return decodeURIComponent(enc.replace(/\+/g, " "));
        }
    }
    catch {
        return null;
    }
    return null;
}
function objectPathFromGsOrPlain(raw) {
    const t = raw.trim();
    if (!t)
        return null;
    const low = t.toLowerCase();
    if (low.startsWith("gs://")) {
        const noProto = t.substring(5);
        const slash = noProto.indexOf("/");
        if (slash > 0 && slash < noProto.length - 1) {
            return noProto.substring(slash + 1).replace(/\\/g, "/");
        }
        return null;
    }
    const plainPath = low.includes("igrejas/") ||
        low.includes("patrimonio/") ||
        low.includes("noticias/") ||
        low.includes("avisos/") ||
        low.includes("eventos/") ||
        low.includes("departamentos/") ||
        low.includes("certificado_logos/") ||
        low.includes("carteira_logos/") ||
        low.includes("cartao_membro/");
    if (plainPath &&
        (low.includes("/") || low.includes("%2f")) &&
        !low.includes("://") &&
        !low.includes("firebasestorage.")) {
        return t.replace(/^\/+/, "").replace(/\\/g, "/");
    }
    return null;
}
/**
 * WhatsApp/Telegram precisam de URL que o crawler consiga baixar.
 * URLs `?alt=media` sem token costumam dar 403; assinatura do bucket resolve.
 */
async function toSignedReadUrlIfStorage(url) {
    const u = (url || "").trim();
    if (!u || u === DEFAULT_OG_IMAGE)
        return u;
    const low = u.toLowerCase();
    const isFb = low.includes("firebasestorage.googleapis.com") ||
        low.includes(".firebasestorage.app");
    if (!isFb)
        return u;
    let objectPath = firebaseStorageObjectPathFromHttpUrl(u);
    if (!objectPath)
        objectPath = objectPathFromGsOrPlain(u);
    if (!objectPath)
        return u;
    try {
        const bucket = admin.storage().bucket();
        const [signed] = await bucket.file(objectPath).getSignedUrl({
            action: "read",
            expires: new Date(Date.now() + 1000 * 60 * 60 * 24 * 7),
        });
        return signed;
    }
    catch (e) {
        functions.logger.warn("toSignedReadUrlIfStorage", objectPath, e);
        return u;
    }
}
function pickHostedVideoUrl(d) {
    const videos = d.videos;
    if (Array.isArray(videos)) {
        for (const v of videos) {
            if (!v || typeof v !== "object")
                continue;
            const rec = v;
            const raw = String(rec["videoUrl"] ?? rec["video_url"] ?? rec["url"] ?? "").trim();
            if (!raw)
                continue;
            if (isYoutubeVimeo(raw))
                continue;
            return normalizeStorageMediaUrl(raw);
        }
    }
    let legacyRaw = String(d.videoUrl || "").trim();
    if (!legacyRaw) {
        for (const k of ["videoStoragePath", "video_storage_path"]) {
            const p = String(d[k] || "").trim();
            if (p) {
                legacyRaw = p;
                break;
            }
        }
    }
    if (!legacyRaw)
        return "";
    if (isYoutubeVimeo(legacyRaw))
        return "";
    return normalizeStorageMediaUrl(legacyRaw);
}
function escAttr(s) {
    return String(s || "")
        .replace(/\r\n|\n|\r/g, " ")
        .replace(/&/g, "&amp;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}
function isHttpUrl(t) {
    return /^https?:\/\//i.test(t.trim());
}
function looksLikeVideoFileUrl(u) {
    const low = u.toLowerCase();
    if (low.includes("youtube") || low.includes("youtu.be") || low.includes("vimeo"))
        return false;
    if (low.includes("%2fvideos%2f") || low.includes("/videos/"))
        return true;
    const base = low.split("?")[0].split("#")[0];
    return /\.(mp4|webm|mov)(\s|$)/.test(base);
}
function youtubeIdFromUrl(raw) {
    const u = raw.trim();
    if (!u)
        return null;
    const withProto = /^https?:\/\//i.test(u) ? u : `https://${u}`;
    try {
        const uri = new URL(withProto);
        const host = uri.hostname.toLowerCase();
        if (host === "youtu.be" || host.endsWith(".youtu.be")) {
            const p = uri.pathname.split("/").filter(Boolean)[0];
            return p || null;
        }
        if (host.includes("youtube.com")) {
            const v = uri.searchParams.get("v");
            if (v)
                return v;
            const parts = uri.pathname.split("/").filter(Boolean);
            const idx = parts.findIndex((x) => ["embed", "shorts", "live", "v"].includes(x.toLowerCase()));
            if (idx >= 0 && parts[idx + 1])
                return parts[idx + 1];
        }
    }
    catch {
        return null;
    }
    return null;
}
function tryPushUrl(raw, out) {
    if (typeof raw !== "string")
        return;
    const normalized = normalizeStorageMediaUrl(raw.trim());
    const t = normalized.trim();
    if (!t || !isHttpUrl(t) || looksLikeVideoFileUrl(t))
        return;
    out.push(t);
}
function pickOgImage(d, church) {
    const candidates = [];
    const imageUrls = d.imageUrls;
    if (Array.isArray(imageUrls)) {
        for (const x of imageUrls) {
            if (typeof x === "string")
                tryPushUrl(x, candidates);
            else if (x && typeof x === "object") {
                tryPushUrl(x.url, candidates);
                tryPushUrl(x.imageUrl, candidates);
                tryPushUrl(x.downloadUrl, candidates);
            }
        }
    }
    tryPushUrl(d.imageUrl, candidates);
    tryPushUrl(d.defaultImageUrl, candidates);
    /** Avisos: paths no Storage e chaves em português (alinhado ao app / Firestore). */
    for (const k of ["imageStoragePaths", "fotoStoragePaths", "fotos", "imagens"]) {
        const arr = d[k];
        if (Array.isArray(arr)) {
            for (const x of arr)
                tryPushUrl(x, candidates);
        }
    }
    for (const k of ["foto", "photo", "imagem"]) {
        tryPushUrl(d[k], candidates);
    }
    for (const k of [
        "posterUrl",
        "videoPosterUrl",
        "coverUrl",
        "capaUrl",
        "previewImageUrl",
        "thumbStoragePath",
        "thumb_storage_path",
        "videoThumbUrl",
        "thumbnailUrl",
    ]) {
        tryPushUrl(d[k], candidates);
    }
    const videos = d.videos;
    if (Array.isArray(videos)) {
        for (const v of videos) {
            if (v && typeof v === "object") {
                tryPushUrl(v.thumbUrl, candidates);
                tryPushUrl(v.thumb_url, candidates);
            }
        }
    }
    tryPushUrl(d.thumbUrl, candidates);
    const legacyVid = String(d.videoUrl || "").trim();
    if (legacyVid) {
        const yid = youtubeIdFromUrl(legacyVid);
        if (yid)
            candidates.push(`https://img.youtube.com/vi/${yid}/hqdefault.jpg`);
    }
    if (candidates.length > 0)
        return candidates[0];
    if (church) {
        tryPushUrl(church.logoProcessedUrl, candidates);
        tryPushUrl(church.logoProcessed, candidates);
        tryPushUrl(church.logoUrl, candidates);
        tryPushUrl(church.logo_url, candidates);
        tryPushUrl(church.logo, candidates);
        if (candidates.length > 0)
            return candidates[0];
    }
    return DEFAULT_OG_IMAGE;
}
function buildDescription(d) {
    const isEvento = String(d.type || "aviso") === "evento";
    const parts = [];
    const startAt = d.startAt;
    if (startAt instanceof admin.firestore.Timestamp) {
        try {
            const dt = startAt.toDate();
            const dias = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
            const pad = (n) => (n < 10 ? `0${n}` : `${n}`);
            parts.push(`📅 ${dias[dt.getDay()]}, ${pad(dt.getDate())}/${pad(dt.getMonth() + 1)}/${dt.getFullYear()} às ${pad(dt.getHours())}:${pad(dt.getMinutes())}`);
        }
        catch {
            /* ignore */
        }
    }
    const loc = String(d.location || "").trim();
    if (loc)
        parts.push(`📍 ${loc}`);
    const text = String(d.text || d.body || "").trim().replace(/\s+/g, " ");
    if (text)
        parts.push(text.length > 240 ? `${text.slice(0, 237)}…` : text);
    const prefix = isEvento ? "🗓️" : "📢";
    if (parts.length === 0) {
        return `${prefix} Toque para ver a capa e os detalhes — compartilhado pelo Gestão YAHWEH.`;
    }
    return `${prefix} ${parts.join(" · ")}`;
}
function isoStartDate(d) {
    const startAt = d.startAt;
    if (!(startAt instanceof admin.firestore.Timestamp))
        return null;
    try {
        return startAt.toDate().toISOString();
    }
    catch {
        return null;
    }
}
function ogImageDimensions(ogImage) {
    if (ogImage === DEFAULT_OG_IMAGE || ogImage.includes("/icons/Icon-512")) {
        return { w: "512", h: "512" };
    }
    return { w: "1200", h: "630" };
}
/** `/igreja/{slug}/evento/{noticiaId}` — rewrite do Hosting para esta function. */
function parseIgrejaEventoPath(pathname) {
    const p = (pathname || "").split("?")[0];
    const m = /^\/igreja\/([^/]+)\/evento\/([^/]+)\/?$/.exec(p);
    if (!m)
        return { slug: "", eventId: "" };
    try {
        return { slug: decodeURIComponent(m[1]), eventId: decodeURIComponent(m[2]) };
    }
    catch {
        return { slug: m[1], eventId: m[2] };
    }
}
/**
 * Com rewrite do Hosting para Cloud Function, `req.path` costuma vir vazio ou `/`;
 * o caminho real está em `req.url` (path + query) ou em cabeçalhos de proxy.
 */
function requestPathname(req) {
    const rawUrl = String(req.originalUrl || req.url || "").trim();
    const rawPath = String(req.path || "").trim();
    const fromString = (s) => {
        const t = s.trim();
        if (!t)
            return "";
        if (/^https?:\/\//i.test(t)) {
            try {
                return new URL(t).pathname || "";
            }
            catch {
                return t.split("?")[0] || "";
            }
        }
        return t.split("?")[0] || "";
    };
    let pathname = fromString(rawUrl);
    if (!pathname || pathname === "/") {
        pathname = fromString(rawPath);
    }
    if (!pathname || pathname === "/") {
        for (const h of ["x-forwarded-uri", "x-forwarded-url", "x-original-url"]) {
            const v = req.headers[h];
            if (typeof v === "string" && v) {
                pathname = fromString(v);
                if (pathname && pathname !== "/")
                    break;
            }
        }
    }
    if (pathname && !pathname.startsWith("/")) {
        pathname = `/${pathname}`;
    }
    return pathname;
}
exports.shareEvento = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    res.set("Cache-Control", "public, max-age=120, s-maxage=300");
    const pathParts = parseIgrejaEventoPath(requestPathname(req));
    const c = String(req.query.c || "").trim();
    let s = String(req.query.s || "").trim();
    let e = String(req.query.e || "").trim();
    if (!s && pathParts.slug)
        s = pathParts.slug;
    if (!e && pathParts.eventId)
        e = pathParts.eventId;
    if ((!c && !s) || !e || c.length > 200 || s.length > 120 || e.length > 200) {
        res.status(400).set("Content-Type", "text/html; charset=utf-8");
        res.send(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>Convite</title></head><body><p>Link inválido.</p><p><a href="${BASE}">${BASE}</a></p></body></html>`);
        return;
    }
    const db = admin.firestore();
    let tenantId = c;
    if (!tenantId && s) {
        try {
            const q = await db.collection("igrejas").where("slug", "==", s).limit(1).get();
            if (q.empty) {
                res.status(404).set("Content-Type", "text/html; charset=utf-8");
                res.send(`<!DOCTYPE html><html><body><p>Igreja não encontrada.</p><p><a href="${BASE}">Gestão YAHWEH</a></p></body></html>`);
                return;
            }
            tenantId = q.docs[0].id;
        }
        catch (err) {
            functions.logger.error("shareEvento slug lookup", err);
            res.status(500).set("Content-Type", "text/html; charset=utf-8");
            res.send("<!DOCTYPE html><html><body>Erro ao carregar.</body></html>");
            return;
        }
    }
    let snap;
    try {
        snap = await db.doc(`igrejas/${tenantId}/noticias/${e}`).get();
        if (!snap.exists) {
            snap = await db.doc(`igrejas/${tenantId}/avisos/${e}`).get();
        }
    }
    catch (err) {
        functions.logger.error("shareEvento firestore", err);
        res.status(500).set("Content-Type", "text/html; charset=utf-8");
        res.send("<!DOCTYPE html><html><body>Erro ao carregar.</body></html>");
        return;
    }
    if (!snap.exists) {
        res.status(404).set("Content-Type", "text/html; charset=utf-8");
        res.send(`<!DOCTYPE html><html><body><p>Publicação não encontrada.</p><p><a href="${BASE}">Gestão YAHWEH</a></p></body></html>`);
        return;
    }
    const d = snap.data();
    const churchSnap = await db.doc(`igrejas/${tenantId}`).get();
    const church = churchSnap.exists ? churchSnap.data() : undefined;
    const titleRaw = String(d.title || (String(d.type || "") === "evento" ? "Evento" : "Aviso")).trim();
    const churchName = String(church?.name || church?.nome || "Igreja").trim();
    const slug = String(church?.slug || church?.slugId || tenantId).trim();
    const redirectPublic = `${BASE}/${encodeURIComponent(slug)}/${encodeURIComponent(e)}`;
    const redirectApp = `${BASE}/igreja/login`;
    const isEvento = String(d.type || "") === "evento";
    const ogTitle = `${titleRaw} — ${churchName}`;
    const ogDesc = buildDescription(d);
    const ogImageRaw = pickOgImage(d, church);
    const ogImage = await toSignedReadUrlIfStorage(ogImageRaw);
    const canonical = s && e
        ? `${BASE}/igreja/${encodeURIComponent(s)}/evento/${encodeURIComponent(e)}`
        : `${BASE}/s/evento?c=${encodeURIComponent(tenantId)}&e=${encodeURIComponent(e)}`;
    const imgDim = ogImageDimensions(ogImage);
    const isoPublished = isoStartDate(d);
    const articleTimeMeta = isoPublished !== null
        ? `\n  <meta property="article:published_time" content="${escAttr(isoPublished)}">`
        : "";
    // Player (para "abrir o link e ver" estilo YouTube)
    let youtubeId = null;
    const videos = d.videos;
    if (Array.isArray(videos)) {
        for (const v of videos) {
            if (!v || typeof v !== "object")
                continue;
            const rec = v;
            const raw = String(rec["videoUrl"] ?? rec["video_url"] ?? rec["url"] ?? "").trim();
            const id = youtubeIdFromUrl(raw);
            if (id) {
                youtubeId = id;
                break;
            }
        }
    }
    youtubeId = youtubeId ?? youtubeIdFromUrl(String(d.videoUrl || "").trim());
    const hostedVideoRaw = youtubeId ? "" : pickHostedVideoUrl(d);
    const hostedVideo = hostedVideoRaw.trim().length > 0
        ? await toSignedReadUrlIfStorage(hostedVideoRaw)
        : "";
    const ytWatch = youtubeId ? `https://www.youtube.com/watch?v=${youtubeId}` : "";
    let ogVideoMeta = "";
    if (youtubeId) {
        ogVideoMeta = `
  <meta property="og:video" content="${escAttr(ytWatch)}">
  <meta property="og:video:secure_url" content="${escAttr(ytWatch)}">
  <meta property="og:video:type" content="text/html">
  <meta property="og:video:width" content="1280">
  <meta property="og:video:height" content="720">`;
    }
    else if (hostedVideo) {
        ogVideoMeta = `
  <meta property="og:video" content="${escAttr(hostedVideo)}">
  <meta property="og:video:secure_url" content="${escAttr(hostedVideo)}">
  <meta property="og:video:type" content="video/mp4">`;
    }
    const ogType = youtubeId || hostedVideo ? "video.other" : isEvento ? "article" : "article";
    const publisher = {
        "@type": "Organization",
        name: churchName,
        url: redirectPublic,
    };
    let jsonLd;
    if (isEvento) {
        jsonLd = {
            "@context": "https://schema.org",
            "@type": "Event",
            name: titleRaw,
            description: ogDesc,
            image: ogImage,
            url: canonical,
            organizer: publisher,
        };
        if (isoPublished)
            jsonLd.startDate = isoPublished;
        const locName = String(d.location || "").trim();
        if (locName)
            jsonLd.location = { "@type": "Place", name: locName };
    }
    else {
        jsonLd = {
            "@context": "https://schema.org",
            "@type": "Article",
            headline: titleRaw,
            description: ogDesc,
            image: ogImage,
            url: canonical,
            publisher,
        };
    }
    const jsonLdStr = JSON.stringify(jsonLd).replace(/</g, "\\u003c");
    const html = `<!DOCTYPE html>
<html lang="pt-BR" prefix="og: http://ogp.me/ns# article: http://ogp.me/ns/article#">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#0C3B8A">
  <title>${escAttr(ogTitle)}</title>
  <meta name="description" content="${escAttr(ogDesc)}">
  <link rel="canonical" href="${escAttr(canonical)}">
  <meta property="og:type" content="${escAttr(ogType)}">
  <meta property="og:site_name" content="Gestão YAHWEH">
  <meta property="og:title" content="${escAttr(ogTitle)}">
  <meta property="og:description" content="${escAttr(ogDesc)}">
  <meta property="og:image" content="${escAttr(ogImage)}">
  <meta property="og:image:secure_url" content="${escAttr(ogImage)}">
  <meta property="og:image:width" content="${imgDim.w}">
  <meta property="og:image:height" content="${imgDim.h}">
  <meta property="og:image:alt" content="${escAttr(`${titleRaw} — ${churchName}`)}">
  <meta property="og:url" content="${escAttr(canonical)}">
  <meta property="og:locale" content="pt_BR">${articleTimeMeta}${ogVideoMeta}
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escAttr(ogTitle)}">
  <meta name="twitter:description" content="${escAttr(ogDesc)}">
  <meta name="twitter:image" content="${escAttr(ogImage)}">
  <script type="application/ld+json">${jsonLdStr}</script>
  <style>
    body{font-family:system-ui,sans-serif;background:#f8fafc;color:#0f172a;padding:2rem;text-align:center}
    a{color:#0c3b8a;font-weight:600}
    .wrap{max-width:920px;margin:0 auto}
    .player{margin:1.25rem 0}
    img{max-width:100%;height:auto;border-radius:16px}
    iframe{width:100%;aspect-ratio:16/9;border:0;border-radius:16px}
    video{width:100%;max-height:64vh;border-radius:16px;background:#000}
    .meta{margin-top:1rem;font-size:.95rem;color:#334155}
    .cta{margin-top:1rem}
  </style>
</head>
<body>
  <div class="wrap">
    <p style="margin:0"><strong style="font-size:1.25rem">${escAttr(titleRaw)}</strong></p>
    <p style="margin:.4rem 0 0">${escAttr(churchName)}</p>

    <div class="player">
      ${youtubeId
        ? `<iframe src="https://www.youtube.com/embed/${escAttr(youtubeId)}?autoplay=1&rel=0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>`
        : hostedVideo
            ? `<video controls playsinline autoplay muted preload="metadata"><source src="${escAttr(hostedVideo)}" /></video>`
            : `<img src="${escAttr(ogImage)}" alt="Capa" />`}
    </div>

    <div class="meta">${escAttr(ogDesc)}</div>

    <div class="cta">
      <p><a href="${escAttr(redirectPublic)}">Abrir site da igreja</a></p>
      <p><a href="${escAttr(redirectApp)}">Entrar no app (membros)</a></p>
    </div>
  </div>
</body>
</html>`;
    res.status(200).set("Content-Type", "text/html; charset=utf-8");
    res.send(html);
});
//# sourceMappingURL=shareEvento.js.map