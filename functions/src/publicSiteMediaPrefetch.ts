import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import { randomUUID } from "crypto";
import { resolveChurchLogoUrl } from "./panelMediaPrefetch";

const MAX_POSTS = 30;
const MAX_PHOTOS_PER_POST = 6;
const MAX_PREFETCH_URLS = 96;
const RESOLVE_BATCH = 12;

function pickHttp(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim().startsWith("http")) return v.trim();
  }
  return "";
}

function looksLikeVideoFile(url: string): boolean {
  const low = url.toLowerCase().split("?")[0].split("#")[0];
  if (/\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?)/i.test(low)) return false;
  return /\.(mp4|webm|mov|m4v|m3u8)(\?|$|\/)/i.test(low)
    || (low.includes("/videos/") && !/\.(jpg|jpeg|png|webp)/i.test(low));
}

function isYoutubeVimeo(url: string): boolean {
  const low = url.toLowerCase();
  return low.includes("youtube.com") || low.includes("youtu.be") || low.includes("vimeo.com");
}

export function collectHttpPhotoUrls(data: Record<string, unknown>): string[] {
  const out: string[] = [];
  const seen = new Set<string>();

  function push(raw: unknown) {
    if (typeof raw !== "string") return;
    const s = raw.trim().replace(/&amp;/g, "&");
    if (!s.startsWith("http") || seen.has(s)) return;
    if (isYoutubeVimeo(s)) return;
    if (looksLikeVideoFile(s)) return;
    seen.add(s);
    out.push(s);
  }

  function fromMap(m: Record<string, unknown>) {
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

  function fromList(raw: unknown) {
    if (!Array.isArray(raw)) return;
    for (const e of raw) {
      if (typeof e === "string") push(e);
      else if (e && typeof e === "object") fromMap(e as Record<string, unknown>);
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
    fromMap(media as Record<string, unknown>);
  } else if (Array.isArray(media)) {
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
      const e = (iv as Record<string, unknown>)[key];
      if (e && typeof e === "object") push((e as Record<string, unknown>).url);
      else push(e);
    }
  }

  const videos = data.videos;
  if (Array.isArray(videos)) {
    for (const e of videos) {
      if (!e || typeof e !== "object") continue;
      const m = e as Record<string, unknown>;
      push(m.thumbUrl);
      push(m.thumb_url);
      push(m.thumbnailUrl);
    }
  }

  return out;
}

/** URL https de vídeo hospedado no doc (sem listar Storage) — partilha Instagram-fast. */
export function collectHostedVideoUrl(data: Record<string, unknown>): string | null {
  let hosted = pickHttp(data, ["hostedVideoUrl", "videoUrl", "video_url"]);
  if (hosted && (!looksLikeVideoFile(hosted) || isYoutubeVimeo(hosted))) {
    hosted = "";
  }
  if (!hosted) {
    const videos = data.videos;
    if (Array.isArray(videos)) {
      for (const e of videos) {
        if (!e || typeof e !== "object") continue;
        const v = pickHttp(e as Record<string, unknown>, [
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
export function collectVideoThumbUrl(data: Record<string, unknown>): string | null {
  const direct = pickHttp(data, [
    "videoThumbUrl",
    "video_thumb_url",
    "videoThumbnailUrl",
  ]);
  if (direct) return direct;
  const videos = data.videos;
  if (Array.isArray(videos)) {
    for (const e of videos) {
      if (!e || typeof e !== "object") continue;
      const t = pickHttp(e as Record<string, unknown>, [
        "thumbUrl",
        "thumb_url",
        "thumbnailUrl",
      ]);
      if (t) return t;
    }
  }
  return null;
}

function collectStoragePaths(
  tenantId: string,
  collection: string,
  postId: string,
  data: Record<string, unknown>,
): string[] {
  const tid = tenantId.trim();
  const paths: string[] = [];
  const folder = collection === "avisos" ? "avisos" : "eventos";

  function add(raw: unknown) {
    if (typeof raw !== "string") return;
    const p = raw.trim().replace(/\\/g, "/").replace(/^\/+/, "");
    if (p.length > 4 && !p.includes("..")) paths.push(p);
  }

  add(data.imageStoragePath);
  add(data.thumbStoragePath);
  add(data.videoThumbStoragePath);

  for (const k of ["imageStoragePaths", "fotoStoragePaths"]) {
    const list = data[k];
    if (!Array.isArray(list)) continue;
    for (const e of list) add(e);
  }

  if (paths.length === 0) {
    paths.push(
      `igrejas/${tid}/${folder}/${postId}/banner_evento.jpg`,
      `igrejas/${tid}/${folder}/${postId}/capa_aviso.jpg`,
      `igrejas/${tid}/${folder}/${postId}/galeria_0.jpg`,
      `igrejas/${tid}/${folder}/${postId}/galeria_1.jpg`,
    );
  }

  const videos = data.videos;
  if (Array.isArray(videos)) {
    for (const e of videos) {
      if (!e || typeof e !== "object") continue;
      const m = e as Record<string, unknown>;
      add(m.storagePath);
      add(m.storage_path);
      add(m.videoStoragePath);
      add(m.thumbStoragePath);
    }
  }

  add(data.videoStoragePath);
  return paths;
}

async function firebaseDownloadUrlForPath(objectPath: string): Promise<string | null> {
  const path = objectPath.replace(/^\/+/, "").trim();
  if (!path) return null;
  try {
    const bucket = admin.storage().bucket();
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (!exists) return null;
    const [meta] = await file.getMetadata();
    let token = meta.metadata?.firebaseStorageDownloadTokens;
    if (typeof token === "string" && token.includes(",")) {
      token = token.split(",")[0]?.trim();
    }
    if (!token || typeof token !== "string") {
      token = randomUUID();
      await file.setMetadata({
        metadata: { firebaseStorageDownloadTokens: token },
      });
    }
    const encoded = encodeURIComponent(path);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
  } catch (e) {
    functions.logger.debug("publicSiteMediaPrefetch: path miss", { path, e });
    return null;
  }
}

async function resolveFirstPath(paths: string[]): Promise<string | null> {
  for (const p of paths) {
    const url = await firebaseDownloadUrlForPath(p);
    if (url) return url;
  }
  return null;
}

export async function enrichPostMedia(
  tenantId: string,
  collection: string,
  postId: string,
  data: Record<string, unknown>,
): Promise<{
  feedCoverUrl: string | null;
  photoUrls: string[];
  videoThumbUrl: string | null;
  hostedVideoUrl: string | null;
}> {
  const httpPhotos = collectHttpPhotoUrls(data);
  const paths = collectStoragePaths(tenantId, collection, postId, data);
  const resolved: string[] = [...httpPhotos];

  for (let i = 0; i < paths.length && resolved.length < MAX_PHOTOS_PER_POST; i++) {
    const url = await firebaseDownloadUrlForPath(paths[i]);
    if (url && !resolved.includes(url)) resolved.push(url);
  }

  const feedCoverUrl = resolved[0] ?? null;

  let videoThumbUrl =
    pickHttp(data, ["videoThumbUrl", "thumbUrl", "thumb_url"]) || null;
  if (!videoThumbUrl) {
    for (const m of (data.videos as unknown[]) || []) {
      if (!m || typeof m !== "object") continue;
      const t = pickHttp(m as Record<string, unknown>, ["thumbUrl", "thumb_url"]);
      if (t) {
        videoThumbUrl = t;
        break;
      }
    }
  }
  if (!videoThumbUrl && paths.length > 0) {
    const thumbPath = paths.find((p) => p.includes("_thumb") || p.includes("/thumbs/"));
    if (thumbPath) videoThumbUrl = await firebaseDownloadUrlForPath(thumbPath);
  }

  let hostedVideoUrl = pickHttp(data, ["hostedVideoUrl", "videoUrl", "video_url"]);
  if (hostedVideoUrl && (!looksLikeVideoFile(hostedVideoUrl) || isYoutubeVimeo(hostedVideoUrl))) {
    hostedVideoUrl = "";
  }
  if (!hostedVideoUrl) {
    for (const m of (data.videos as unknown[]) || []) {
      if (!m || typeof m !== "object") continue;
      const v = pickHttp(m as Record<string, unknown>, ["videoUrl", "video_url", "url"]);
      if (v && looksLikeVideoFile(v) && !isYoutubeVimeo(v)) {
        hostedVideoUrl = v;
        break;
      }
    }
  }
  if (!hostedVideoUrl) {
    const vPath = paths.find((p) => looksLikeVideoFile(p) || p.includes("/videos/"));
    if (vPath) hostedVideoUrl = (await firebaseDownloadUrlForPath(vPath)) ?? "";
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
export async function recomputePublicSiteMediaPrefetch(tenantId: string): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const db = admin.firestore();
  const churchRef = db.collection("igrejas").doc(tid);
  const cacheRef = churchRef.collection("_performance_cache").doc("public_feed");

  const [churchSnap, cacheSnap] = await Promise.all([
    churchRef.get(),
    cacheRef.get(),
  ]);

  const churchData = (churchSnap.data() ?? {}) as Record<string, unknown>;
  const churchLogoUrl = await resolveChurchLogoUrl(tid, churchData);

  const rawFeed = cacheSnap.data()?.data;
  if (!Array.isArray(rawFeed) || rawFeed.length === 0) {
    await cacheRef.set(
      {
        churchLogoUrl: churchLogoUrl ?? null,
        prefetchUrls: churchLogoUrl ? [churchLogoUrl] : [],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const prefetchUrls: string[] = [];
  const seenPrefetch = new Set<string>();

  function addPrefetch(url: string | null | undefined) {
    const u = (url ?? "").trim();
    if (!u.startsWith("http") || seenPrefetch.has(u)) return;
    if (prefetchUrls.length >= MAX_PREFETCH_URLS) return;
    seenPrefetch.add(u);
    prefetchUrls.push(u);
  }

  addPrefetch(churchLogoUrl);

  const enriched: Record<string, unknown>[] = [];

  for (let i = 0; i < rawFeed.length && i < MAX_POSTS; i++) {
    const row = rawFeed[i];
    if (!row || typeof row !== "object") continue;
    const base = row as Record<string, unknown>;
    const postId = String(base.id ?? "").trim();
    const collection = String(base.collection ?? "avisos").trim();
    if (!postId) {
      enriched.push(base);
      continue;
    }

    const churchRefPosts = churchRef.collection(
      collection === "avisos" ? "avisos" : "eventos",
    );
    const postSnap = await churchRefPosts.doc(postId).get();
    const postData = (postSnap.data() ?? base) as Record<string, unknown>;

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
    for (const p of media.photoUrls) addPrefetch(p);
    addPrefetch(media.videoThumbUrl);
    if (media.hostedVideoUrl && !looksLikeVideoFile(media.hostedVideoUrl)) {
      addPrefetch(media.hostedVideoUrl);
    } else if (media.hostedVideoUrl) {
      addPrefetch(media.videoThumbUrl);
    }
  }

  for (let i = MAX_POSTS; i < rawFeed.length; i++) {
    const row = rawFeed[i];
    if (row && typeof row === "object") enriched.push(row as Record<string, unknown>);
  }

  await cacheRef.set(
    {
      data: enriched,
      churchLogoUrl: churchLogoUrl ?? null,
      prefetchUrls,
      mediaPrefetchAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  functions.logger.info("publicSiteMediaPrefetch: ok", {
    tenantId: tid,
    posts: enriched.length,
    prefetch: prefetchUrls.length,
    logo: !!churchLogoUrl,
  });
}

/** Visitante (incl. anónimo): aquece cache público se a igreja existir. */
export const warmPublicSiteFeedCache = functions
  .region("us-central1")
  .https.onCall(async (request, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Sessão necessária.");
    }
    const body = (request || {}) as Record<string, unknown>;
    const tenantId = String(body.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError("invalid-argument", "tenantId ausente");
    }
    const ig = await admin.firestore().collection("igrejas").doc(tenantId).get();
    if (!ig.exists) {
      throw new functions.https.HttpsError("not-found", "Igreja não encontrada");
    }
    const { refreshPublicFeedCacheForTenant } = await import("./churchPerformancePack");
    await refreshPublicFeedCacheForTenant(tenantId);
    const { mirrorPublicSitePanelCache } = await import("./panelPublicSiteCache");
    await mirrorPublicSitePanelCache(tenantId);
    return { ok: true, tenantId, warmed: true };
  });
