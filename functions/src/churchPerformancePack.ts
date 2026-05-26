/**
 * Pacote definitivo de performance — Gestão YAHWEH
 * (índices Firestore + processamento Storage + caches agendados)
 *
 * Modelo real: `igrejas/{tenant}/avisos|noticias|membros|chat_media/…`
 * (não `posts` / `members` genéricos da spec de referência).
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import sharp from "sharp";

const db = admin.firestore();
const bucket = admin.storage().bucket();

const WEBP_Q = 70;
const TIERS = [
  { key: "thumb_200", edge: 200 },
  { key: "medium_800", edge: 800 },
  { key: "full_1920", edge: 1920 },
] as const;

function isImageContentType(ct?: string): boolean {
  return !!ct && ct.startsWith("image/");
}

function isVariantPath(name: string): boolean {
  return (
    /_(thumb_200|medium_800|full_1920)\.webp$/i.test(name) ||
    /profile_(thumb|medium)\.webp$/i.test(name) ||
    /_thumb\.webp$/i.test(name) ||
    name.includes("/thumbs/")
  );
}

async function saveWebp(destPath: string, buffer: Buffer): Promise<string> {
  const file = bucket.file(destPath);
  const token = admin.firestore().collection("_meta").doc().id;
  await file.save(buffer, {
    metadata: {
      contentType: "image/webp",
      cacheControl: "public,max-age=31536000",
      metadata: { firebaseStorageDownloadTokens: token },
    },
    resumable: false,
  });
  const encoded = encodeURIComponent(destPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
}

async function processMemberProfile(
  tenantId: string,
  memberId: string,
  srcPath: string,
): Promise<void> {
  const [buf] = await bucket.file(srcPath).download();
  if (!buf || buf.length < 32) return;

  const base = `igrejas/${tenantId}/membros/${memberId}`;
  const [thumbBuf, mediumBuf] = await Promise.all([
    sharp(buf).rotate().resize(200, 200, { fit: "inside", withoutEnlargement: true }).webp({ quality: WEBP_Q }).toBuffer(),
    sharp(buf).rotate().resize(500, 500, { fit: "inside", withoutEnlargement: true }).webp({ quality: WEBP_Q }).toBuffer(),
  ]);
  const [thumbUrl, mediumUrl] = await Promise.all([
    saveWebp(`${base}/profile_thumb.webp`, thumbBuf),
    saveWebp(`${base}/profile_medium.webp`, mediumBuf),
  ]);
  await db
    .collection("igrejas")
    .doc(tenantId)
    .collection("membros")
    .doc(memberId)
    .set(
      {
        photoThumb: thumbUrl,
        photoMedium: mediumUrl,
        photoVariantsGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function processFeedImage(
  tenantId: string,
  collection: "avisos" | "eventos",
  postId: string,
  baseName: string,
  srcPath: string,
): Promise<void> {
  const [buf] = await bucket.file(srcPath).download();
  if (!buf || buf.length < 32) return;

  const folder = collection === "avisos" ? "avisos" : "eventos";
  const root = `igrejas/${tenantId}/${folder}/${postId}`;
  const variants: Record<string, { url: string; storagePath: string; contentType: string }> = {};

  for (const tier of TIERS) {
    const out = await sharp(buf)
      .rotate()
      .resize(tier.edge, tier.edge, { fit: "inside", withoutEnlargement: true })
      .webp({ quality: WEBP_Q })
      .toBuffer();
    const dest = `${root}/${baseName}_${tier.key}.webp`;
    const url = await saveWebp(dest, out);
    variants[tier.key] = { url, storagePath: dest, contentType: "image/webp" };
  }

  const col = collection === "avisos" ? "avisos" : "noticias";
  const ref = db.collection("igrejas").doc(tenantId).collection(col).doc(postId);
  const snap = await ref.get();
  if (!snap.exists) return;

  const primary = variants.full_1920?.url ?? variants.medium_800?.url ?? "";
  await ref.set(
    {
      imageVariants: variants,
      imagem_url: primary || admin.firestore.FieldValue.delete(),
      imageUrl: primary || admin.firestore.FieldValue.delete(),
      serverVariantsGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function parseUpload(name: string):
  | { kind: "member"; tenantId: string; memberId: string }
  | { kind: "feed"; tenantId: string; collection: "avisos" | "eventos"; postId: string; baseName: string }
  | null {
  let m = name.match(
    /^igrejas\/([^/]+)\/membros\/([^/]+)\/foto_perfil\.(jpg|jpeg|png|webp)$/i,
  );
  if (m) return { kind: "member", tenantId: m[1], memberId: m[2] };

  m = name.match(
    /^igrejas\/([^/]+)\/avisos\/([^/]+)\/(capa_aviso|galeria_\d+)\.(jpg|jpeg|png)$/i,
  );
  if (m) {
    return {
      kind: "feed",
      tenantId: m[1],
      collection: "avisos",
      postId: m[2],
      baseName: m[3],
    };
  }

  m = name.match(
    /^igrejas\/([^/]+)\/eventos\/([^/]+)\/(banner_evento|galeria_\d+)\.(jpg|jpeg|png)$/i,
  );
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
export const optimizeImage = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 180, memory: "1GB" })
  .storage.object()
  .onFinalize(async (object) => {
    const name = object.name || "";
    if (!name || object.size === "0") return null;
    if (isVariantPath(name)) return null;

    const ct = object.contentType || "";
    if (!isImageContentType(ct) && !/\.(jpe?g|png)$/i.test(name)) {
      return null;
    }

    try {
      const parsed = parseUpload(name);
      if (!parsed) return null;

      if (parsed.kind === "member") {
        await processMemberProfile(parsed.tenantId, parsed.memberId, name);
        functions.logger.info("optimizeImage: perfil", parsed);
        return true;
      }

      await processFeedImage(
        parsed.tenantId,
        parsed.collection,
        parsed.postId,
        parsed.baseName,
        name,
      );
      functions.logger.info("optimizeImage: feed", parsed);
      return true;
    } catch (e) {
      functions.logger.error("optimizeImage", { name, e });
      return null;
    }
  });

/**
 * Vídeo recebido no Storage — marca processamento e regista thumb esperada.
 * Compressão H264 pesada fica no cliente; aqui evita reprocessar o original em loop.
 */
export const compressVideo = functions
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

    const m = name.match(
      /^igrejas\/([^/]+)\/eventos\/videos\/([^_]+)_v(\d)\.mp4$/i,
    );
    if (!m) return true;

    const tenantId = m[1];
    const postId = m[2];
    const slot = Number(m[3]);
    const thumbPath = `igrejas/${tenantId}/eventos/videos/${postId}_v${slot}_thumb.jpg`;

    await db
      .collection("igrejas")
      .doc(tenantId)
      .collection("noticias")
      .doc(postId)
      .set(
        {
          videoServerProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
          videoThumbStoragePath: thumbPath,
        },
        { merge: true },
      );

    return true;
  });

async function listActiveTenantIds(limit = 40): Promise<string[]> {
  try {
    const snap = await db
      .collection("igrejas")
      .orderBy("updatedAt", "desc")
      .limit(limit)
      .get();
    if (!snap.empty) return snap.docs.map((d) => d.id);
  } catch (_) {
    /* índice updatedAt pode não existir em todas as bases */
  }
  const fallback = await db.collection("igrejas").limit(limit).get();
  return fallback.docs.map((d) => d.id);
}

function parseBirthMd(data: admin.firestore.DocumentData): { month: number; day: number } | null {
  const keys = ["DATA_NASCIMENTO", "dataNascimento", "birthDate", "nascimento"];
  for (const k of keys) {
    const raw = data[k];
    if (raw instanceof admin.firestore.Timestamp) {
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
export const generateBirthdayCache = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub.schedule("every 24 hours")
  .onRun(async () => {
    const month = new Date().getMonth() + 1;
    const tenantIds = await listActiveTenantIds(60);
    let written = 0;

    for (const tenantId of tenantIds) {
      try {
        const snap = await db
          .collection("igrejas")
          .doc(tenantId)
          .collection("membros")
          .where("birthMonth", "==", month)
          .limit(80)
          .get();

        const birthdays: Record<string, unknown>[] = [];
        for (const doc of snap.docs) {
          const d = doc.data();
          const birth = parseBirthMd(d);
          if (!birth) continue;
          birthdays.push({
            memberDocId: doc.id,
            displayName: String(d.NOME_COMPLETO ?? d.nome ?? "Membro"),
            photoThumb: d.photoThumb ?? d.fotoUrl ?? null,
            birthMonth: birth.month,
            birthDay: birth.day,
          });
        }

        await db
          .collection("igrejas")
          .doc(tenantId)
          .collection("_performance_cache")
          .doc("birthdays")
          .set({
            month,
            data: birthdays,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        written += 1;
      } catch (e) {
        functions.logger.warn("generateBirthdayCache", { tenantId, e });
      }
    }

    functions.logger.info("generateBirthdayCache: fim", { month, churches: written });
    return true;
  });

function lightPublicPost(
  id: string,
  collection: string,
  data: admin.firestore.DocumentData,
): Record<string, unknown> {
  return {
    id,
    collection,
    title: data.title ?? data.titulo ?? "",
    createdAt: data.createdAt ?? null,
    startAt: data.startAt ?? null,
    type: data.type ?? "",
    publishState: data.publishState ?? "published",
    imageVariants: data.imageVariants ?? null,
    imagem_url: data.imagem_url ?? data.imageUrl ?? null,
  };
}

/** Atualiza `public_feed` para uma igreja (reutilizado por cron e triggers). */
export async function refreshPublicFeedCacheForTenant(
  tenantId: string,
): Promise<void> {
  const churchRef = db.collection("igrejas").doc(tenantId);
  const [avisosSnap, noticiasSnap] = await Promise.all([
    churchRef
      .collection("avisos")
      .where("publicSite", "==", true)
      .orderBy("createdAt", "desc")
      .limit(30)
      .get(),
    churchRef
      .collection("noticias")
      .where("publicSite", "==", true)
      .orderBy("createdAt", "desc")
      .limit(30)
      .get(),
  ]);

  const feed: Record<string, unknown>[] = [];
  for (const d of avisosSnap.docs) {
    feed.push(lightPublicPost(d.id, "avisos", d.data()));
  }
  for (const d of noticiasSnap.docs) {
    const data = d.data();
    if (String(data.type ?? "") !== "evento") continue;
    feed.push(lightPublicPost(d.id, "noticias", data));
  }

  feed.sort((a, b) => {
    const ta = (a.createdAt as admin.firestore.Timestamp | undefined)?.toMillis?.() ?? 0;
    const tb = (b.createdAt as admin.firestore.Timestamp | undefined)?.toMillis?.() ?? 0;
    return tb - ta;
  });

  await churchRef.collection("_performance_cache").doc("public_feed").set({
    data: feed.slice(0, 50),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Cache do feed público por igreja (avisos + eventos publicSite) — leitura instantânea no site.
 */
export const generatePublicFeedCache = functions
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
      } catch (e) {
        functions.logger.warn("generatePublicFeedCache", { tenantId, e });
      }
    }

    functions.logger.info("generatePublicFeedCache: fim", { churches: written });
    return true;
  });

/** Novo aviso/evento público → atualiza cache do site sem esperar o cron de 10 min. */
async function onPublicPostWrite(
  tenantId: string,
  after: admin.firestore.DocumentSnapshot | undefined,
): Promise<void> {
  if (!after?.exists) return;
  const d = after.data() as Record<string, unknown>;
  if (d.publicSite === false) return;
  const st = String(d.publishState ?? "published");
  if (st === "failed") return;
  try {
    await refreshPublicFeedCacheForTenant(tenantId);
  } catch (e) {
    functions.logger.warn("refreshPublicFeedCacheOnPost", { tenantId, e });
  }
}

export const refreshPublicFeedCacheOnAvisoWrite = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{postId}")
  .onWrite((change, ctx) =>
    onPublicPostWrite(ctx.params.tenantId as string, change.after),
  );

export const refreshPublicFeedCacheOnNoticiaWrite = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/noticias/{postId}")
  .onWrite((change, ctx) =>
    onPublicPostWrite(ctx.params.tenantId as string, change.after),
  );
