import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const CHURCH_BATCH = 25;
const DOCS_PER_MODULE = 60;
const ORPHAN_DOC_AGE_MS = 3 * 24 * 60 * 60 * 1000;
const STORAGE_ORPHAN_AGE_MS = 7 * 24 * 60 * 60 * 1000;

const DRAFT_STATES = new Set([
  "draft",
  "rascunho",
  "uploading",
  "failed",
  "pending",
  "verifying",
]);

type OrphanStats = {
  churchesScanned: number;
  firestorePathsCleared: number;
  storageFilesDeleted: number;
  docsMarkedOrphan: number;
};

function storagePathFields(data: Record<string, unknown>): string[] {
  const out = new Set<string>();
  const singles = [
    "storagePath",
    "logoPath",
    "coverStoragePath",
    "photoStoragePath",
    "pdfPath",
    "videoStoragePath",
  ];
  for (const k of singles) {
    const v = String(data[k] ?? "").trim();
    if (v.startsWith("igrejas/")) out.add(v);
  }
  for (const k of ["mediaPaths", "storagePaths", "imagePaths", "fotoPaths"]) {
    const v = data[k];
    if (Array.isArray(v)) {
      for (const item of v) {
        const p = String(item ?? "").trim();
        if (p.startsWith("igrejas/")) out.add(p);
      }
    }
  }
  return Array.from(out);
}

async function storageExists(path: string): Promise<boolean> {
  const p = path.trim();
  if (!p.startsWith("igrejas/")) return false;
  try {
    const [exists] = await admin.storage().bucket().file(p).exists();
    return exists;
  } catch {
    return false;
  }
}

async function deleteStoragePath(path: string): Promise<boolean> {
  const p = path.trim();
  if (!p.startsWith("igrejas/")) return false;
  try {
    await admin.storage().bucket().file(p).delete({ ignoreNotFound: true });
    return true;
  } catch {
    return false;
  }
}

function docAgeMs(data: Record<string, unknown>): number {
  for (const k of ["updatedAt", "createdAt", "dataEmissao"]) {
    const v = data[k];
    if (v instanceof admin.firestore.Timestamp) return v.toMillis();
  }
  return 0;
}

/**
 * Remove referências Firestore a ficheiros inexistentes e ficheiros Storage
 * sem documento correspondente (avisos/eventos/chat rascunho antigos).
 */
async function cleanupChurchOrphans(
  churchId: string,
  stats: OrphanStats,
): Promise<void> {
  const db = admin.firestore();
  const churchRef = db.collection("igrejas").doc(churchId);
  const cutoff = Date.now() - ORPHAN_DOC_AGE_MS;

  const modules: Array<{
    col: string;
    idFromPath: (path: string) => string | null;
  }> = [
    {
      col: "avisos",
      idFromPath: (p) => {
        const m = p.match(/\/avisos\/([^/]+)\//);
        return m?.[1] ?? null;
      },
    },
    {
      col: "eventos",
      idFromPath: (p) => {
        const m = p.match(/\/eventos\/([^/]+)\//);
        return m?.[1] ?? null;
      },
    },
    {
      col: "noticias",
      idFromPath: (p) => {
        const m = p.match(/\/eventos\/([^/]+)\//) ?? p.match(/\/noticias\/([^/]+)\//);
        return m?.[1] ?? null;
      },
    },
  ];

  for (const mod of modules) {
    const snap = await churchRef
      .collection(mod.col)
      .orderBy("updatedAt", "desc")
      .limit(DOCS_PER_MODULE)
      .get()
      .catch(async () =>
        churchRef.collection(mod.col).limit(DOCS_PER_MODULE).get(),
      );

    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const state = String(data.publishState ?? data.status ?? "").toLowerCase();
      const age = docAgeMs(data);
      const paths = storagePathFields(data);
      if (paths.length === 0) continue;

      let cleared = false;
      for (const path of paths) {
        const exists = await storageExists(path);
        if (!exists) {
          cleared = true;
          if (
            DRAFT_STATES.has(state) ||
            (age > 0 && age < cutoff) ||
            state === ""
          ) {
            await doc.ref.set(
              {
                publishState: "orphan_cleared",
                orphanClearedAt: admin.firestore.FieldValue.serverTimestamp(),
                storagePath: admin.firestore.FieldValue.delete(),
                mediaPaths: admin.firestore.FieldValue.delete(),
              },
              { merge: true },
            );
            stats.firestorePathsCleared++;
            stats.docsMarkedOrphan++;
          }
        }
      }

      if (
        !cleared &&
        DRAFT_STATES.has(state) &&
        age > 0 &&
        age < cutoff &&
        paths.every((p) => !p)
      ) {
        stats.docsMarkedOrphan++;
      }
    }
  }

  // Chat: mensagens com storagePath sem ficheiro
  const chatsSnap = await churchRef.collection("chats").limit(15).get();
  for (const chat of chatsSnap.docs) {
    let msgs: admin.firestore.QuerySnapshot;
    try {
      msgs = await chat.ref
        .collection("messages")
        .orderBy("createdAt", "desc")
        .limit(40)
        .get();
    } catch {
      continue;
    }
    for (const msg of msgs.docs) {
      const data = msg.data() as Record<string, unknown>;
      const path = String(data.storagePath ?? "").trim();
      if (!path.startsWith("igrejas/")) continue;
      const exists = await storageExists(path);
      if (!exists) {
        await msg.ref.set(
          {
            storagePath: admin.firestore.FieldValue.delete(),
            deliveryStatus: "orphan_cleared",
            orphanClearedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        stats.firestorePathsCleared++;
      }
    }
  }

  // Storage órfão: pastas avisos/eventos com doc ausente (>7 dias)
  const storageCutoff = Date.now() - STORAGE_ORPHAN_AGE_MS;
  const bucket = admin.storage().bucket();
  for (const prefix of [`igrejas/${churchId}/avisos/`, `igrejas/${churchId}/eventos/`]) {
    try {
      const [files] = await bucket.getFiles({ prefix, maxResults: 40 });
      for (const file of files) {
        const meta = await file.getMetadata().catch(() => [{ updated: "" }]);
        const updated = new Date(String(meta[0]?.updated ?? "")).getTime();
        if (updated > storageCutoff) continue;
        const name = file.name;
        const postMatch = name.match(/\/(?:avisos|eventos)\/([^/]+)\//);
        const postId = postMatch?.[1];
        if (!postId) continue;
        const col = name.includes("/avisos/") ? "avisos" : "eventos";
        const docSnap = await churchRef.collection(col).doc(postId).get();
        if (!docSnap.exists) {
          await file.delete({ ignoreNotFound: true });
          stats.storageFilesDeleted++;
        }
      }
    } catch (e) {
      functions.logger.warn("cleanupOrphanFiles: storage scan", { churchId, prefix, e });
    }
  }
}

/** Limpeza diária — gravações órfãs Storage ↔ Firestore. */
export const scheduledCleanupOrphanFiles = functions
  .region("southamerica-east1")
  .pubsub.schedule("every 24 hours")
  .onRun(async () => {
    const db = admin.firestore();
    const stats: OrphanStats = {
      churchesScanned: 0,
      firestorePathsCleared: 0,
      storageFilesDeleted: 0,
      docsMarkedOrphan: 0,
    };

    let lastId: string | undefined;
    for (let page = 0; page < 8; page++) {
      let q = db.collection("igrejas").orderBy(admin.firestore.FieldPath.documentId()).limit(CHURCH_BATCH);
      if (lastId) q = q.startAfter(lastId);
      const snap = await q.get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        stats.churchesScanned++;
        await cleanupChurchOrphans(doc.id, stats);
      }
      lastId = snap.docs[snap.docs.length - 1].id;
      if (snap.size < CHURCH_BATCH) break;
    }

    functions.logger.info("scheduledCleanupOrphanFiles", stats);
    return stats;
  });
