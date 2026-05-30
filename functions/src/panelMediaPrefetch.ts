import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { randomUUID } from "crypto";

const MAX_MEMBERS = 120;
const RESOLVE_BATCH = 16;

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function pickHttpPhoto(data: Record<string, unknown>): string {
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
    if (typeof v === "string" && v.trim().startsWith("http")) return v.trim();
  }
  return "";
}

function pickChurchLogoHttp(data: Record<string, unknown>): string {
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
    if (typeof v === "string" && v.trim().startsWith("http")) return v.trim();
  }
  return "";
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
    functions.logger.debug("panelMediaPrefetch: path miss", { path, e });
    return null;
  }
}

function memberStoragePaths(
  tenantId: string,
  memberDocId: string,
  cpfDigits?: string | null,
  authUid?: string | null,
): string[] {
  const tid = tenantId.trim();
  const mid = memberDocId.trim();
  if (!tid || !mid) return [];
  const cpf = String(cpfDigits ?? "").replace(/\D/g, "");
  const uid = String(authUid ?? "").trim();
  const stems = new Set<string>([mid]);
  if (cpf.length === 11) stems.add(cpf);
  if (uid && uid !== mid) stems.add(uid);

  const paths: string[] = [];
  for (const stem of stems) {
    paths.push(
      `igrejas/${tid}/membros/${stem}/thumb_foto_perfil.jpg`,
      `igrejas/${tid}/membros/${stem}/foto_perfil_thumb.jpg`,
      `igrejas/${tid}/membros/${stem}/foto_perfil.jpg`,
      `igrejas/${tid}/membros/${stem}/foto_perfil.webp`,
    );
  }
  return paths;
}

async function resolveFirstPath(paths: string[]): Promise<string | null> {
  for (const p of paths) {
    const url = await firebaseDownloadUrlForPath(p);
    if (url) return url;
  }
  return null;
}

type MemberRef = {
  memberDocId: string;
  photoUrl?: string | null;
  cpfDigits?: string | null;
  authUid?: string | null;
};

function collectMemberRefs(
  summary: Record<string, unknown> | undefined,
  directory: Record<string, unknown> | undefined,
): MemberRef[] {
  const out: MemberRef[] = [];
  const seen = new Set<string>();

  function add(raw: Record<string, unknown>) {
    const id = String(raw.memberDocId ?? "").trim();
    if (!id || seen.has(id)) return;
    seen.add(id);
    out.push({
      memberDocId: id,
      photoUrl: (raw.photoUrl as string | null) ?? null,
      cpfDigits: (raw.cpfDigits as string | null) ?? null,
      authUid: (raw.authUid as string | null) ?? null,
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
    if (!Array.isArray(arr)) continue;
    for (const e of arr) {
      if (e && typeof e === "object") add(e as Record<string, unknown>);
    }
  }

  const entries = directory?.entries;
  if (Array.isArray(entries)) {
    for (const e of entries) {
      if (e && typeof e === "object") add(e as Record<string, unknown>);
      if (out.length >= MAX_MEMBERS) break;
    }
  }

  return out.slice(0, MAX_MEMBERS);
}

export async function resolveChurchLogoUrl(
  tenantId: string,
  churchData: Record<string, unknown>,
): Promise<string | null> {
  const http = pickChurchLogoHttp(churchData);
  if (http) return http;

  const tid = tenantId.trim();
  const custom = pickString(churchData, ["logoPath", "logoStoragePath"]);
  const paths: string[] = [];
  if (custom) {
    paths.push(custom.replace(/\\/g, "/").replace(/^\/+/, ""));
  }
  paths.push(
    `igrejas/${tid}/configuracoes/logo_igreja.png`,
    `igrejas/${tid}/configuracoes/logo_igreja.jpg`,
    `igrejas/${tid}/gestor/foto_perfil.jpg`,
    `igrejas/${tid}/logo/logo.jpg`,
    `igrejas/${tid}/branding/logo.png`,
  );
  return resolveFirstPath(paths);
}

/**
 * `_panel_cache/media_prefetch` — URLs prontas (logo + fotos do painel) para o app
 * não disparar dezenas de `getDownloadURL` no cliente.
 */
export async function recomputePanelMediaPrefetch(tenantId: string): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const db = admin.firestore();
  const churchRef = db.collection("igrejas").doc(tid);
  const cacheCol = churchRef.collection("_panel_cache");

  const [churchSnap, summarySnap, dirSnap] = await Promise.all([
    churchRef.get(),
    cacheCol.doc("dashboard_summary").get(),
    cacheCol.doc("members_directory").get(),
  ]);

  const churchData = (churchSnap.data() ?? {}) as Record<string, unknown>;
  const summary = (summarySnap.data() ?? {}) as Record<string, unknown>;
  const directory = (dirSnap.data() ?? {}) as Record<string, unknown>;

  const [churchLogoUrl, memberRefs] = await Promise.all([
    resolveChurchLogoUrl(tid, churchData),
    Promise.resolve(collectMemberRefs(summary, directory)),
  ]);

  const memberPhotoUrls: Record<string, string> = {};

  for (let i = 0; i < memberRefs.length; i += RESOLVE_BATCH) {
    const batch = memberRefs.slice(i, i + RESOLVE_BATCH);
    await Promise.all(
      batch.map(async (m) => {
        const http = (m.photoUrl ?? "").trim();
        if (http.startsWith("http")) {
          memberPhotoUrls[m.memberDocId] = http;
          return;
        }
        const fromDoc = pickHttpPhoto({
          photoUrl: m.photoUrl,
        } as Record<string, unknown>);
        if (fromDoc) {
          memberPhotoUrls[m.memberDocId] = fromDoc;
          return;
        }
        const paths = memberStoragePaths(tid, m.memberDocId, m.cpfDigits, m.authUid);
        const url = await resolveFirstPath(paths);
        if (url) memberPhotoUrls[m.memberDocId] = url;
      }),
    );
  }

  await cacheCol.doc("media_prefetch").set(
    {
      schemaVersion: 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      churchLogoUrl: churchLogoUrl ?? null,
      memberPhotoUrls,
      memberCount: Object.keys(memberPhotoUrls).length,
    },
    { merge: false },
  );

  functions.logger.info("panelMediaPrefetch: ok", {
    tenantId: tid,
    logo: !!churchLogoUrl,
    members: Object.keys(memberPhotoUrls).length,
  });
}
