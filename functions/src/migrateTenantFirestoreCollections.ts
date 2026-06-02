/**
 * Migração automática por igreja:
 * - `igrejas/{tenantId}/noticias` → `eventos` (+ subcoleções)
 * - `igrejas/{tenantId}/chat_threads` → `chats` (+ messages, typing, …)
 *
 * Idempotente: documentos já existentes no destino são atualizados com merge.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const META_DOC = "firestore_collection_migration_v1";
const BATCH_LIMIT = 400;

type MigStats = {
  copied: number;
  deleted: number;
  skipped: number;
};

async function copyDocRecursive(
  source: admin.firestore.DocumentReference,
  dest: admin.firestore.DocumentReference,
): Promise<number> {
  const snap = await source.get();
  if (!snap.exists) return 0;
  await dest.set(snap.data() ?? {}, { merge: true });
  let n = 1;
  const subcols = await source.listCollections();
  for (const sub of subcols) {
    const destSub = dest.collection(sub.id);
    const docs = await sub.get();
    for (const d of docs.docs) {
      n += await copyDocRecursive(d.ref, destSub.doc(d.id));
    }
  }
  return n;
}

async function migrateTopLevelCollection(
  tenantRef: admin.firestore.DocumentReference,
  fromId: string,
  toId: string,
  deleteSource: boolean,
): Promise<MigStats> {
  const stats: MigStats = { copied: 0, deleted: 0, skipped: 0 };
  const sourceCol = tenantRef.collection(fromId);
  const destCol = tenantRef.collection(toId);

  let last: admin.firestore.DocumentSnapshot | undefined;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = sourceCol.orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_LIMIT);
    if (last) q = q.startAfter(last.id);
    const page = await q.get();
    if (page.empty) break;

    for (const doc of page.docs) {
      const destRef = destCol.doc(doc.id);
      stats.copied += await copyDocRecursive(doc.ref, destRef);
      if (deleteSource) {
        await deleteDocRecursive(doc.ref);
        stats.deleted += 1;
      }
    }
    last = page.docs[page.docs.length - 1];
    if (page.size < BATCH_LIMIT) break;
  }
  return stats;
}

async function deleteDocRecursive(ref: admin.firestore.DocumentReference): Promise<void> {
  const subcols = await ref.listCollections();
  for (const sub of subcols) {
    const docs = await sub.get();
    for (const d of docs.docs) {
      await deleteDocRecursive(d.ref);
    }
  }
  await ref.delete();
}

export async function runTenantFirestoreCollectionMigration(
  tenantId: string,
  options?: { deleteSource?: boolean },
): Promise<Record<string, unknown>> {
  const tid = String(tenantId || "").trim();
  if (!tid) throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");

  const db = admin.firestore();
  const tenantRef = db.collection("igrejas").doc(tid);
  const metaRef = tenantRef.collection("_meta").doc(META_DOC);

  const existing = await metaRef.get();
  if (existing.exists && existing.data()?.status === "completed") {
    return { tenantId: tid, alreadyCompleted: true, ...(existing.data() ?? {}) };
  }

  await metaRef.set(
    { status: "running", startedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  const deleteSource = options?.deleteSource !== false;

  try {
    const noticias = await migrateTopLevelCollection(
      tenantRef,
      "noticias",
      "eventos",
      deleteSource,
    );
    const chats = await migrateTopLevelCollection(
      tenantRef,
      "chat_threads",
      "chats",
      deleteSource,
    );

    const result = {
      tenantId: tid,
      status: "completed",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      noticiasToEventos: noticias,
      chatThreadsToChats: chats,
      deleteSource,
    };
    await metaRef.set(result, { merge: true });
    return result;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await metaRef.set(
      {
        status: "error",
        error: msg.slice(0, 500),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw e;
  }
}

/** Callable: migra a igreja do utilizador (ou master com tenantId no body). */
export const migrateTenantFirestoreCollections = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const tenantId = String((data as { tenantId?: string })?.tenantId ?? "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
  const token = await admin.auth().getUser(context.auth.uid);
  const claims = (context.auth.token ?? {}) as Record<string, unknown>;
  const claimTenant = String(claims.igrejaId ?? claims.tenantId ?? "").trim();
  const isMaster =
    claims.admin === true ||
    claims.role === "master" ||
    (token.email ?? "").toLowerCase() === "raihom@gmail.com";
  if (!isMaster && claimTenant !== tenantId) {
    throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja.");
  }
    const deleteSource = (data as { deleteSource?: boolean })?.deleteSource !== false;
    return runTenantFirestoreCollectionMigration(tenantId, { deleteSource });
  });

/** Master: migra todas as igrejas (batch sequencial). */
export const migrateAllTenantsFirestoreCollections = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "2GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const email = (token.email ?? "").toLowerCase();
    const claims = (context.auth.token ?? {}) as Record<string, unknown>;
    const isMaster = claims.admin === true || claims.role === "master" || email === "raihom@gmail.com";
    if (!isMaster) {
      throw new functions.https.HttpsError("permission-denied", "Apenas master.");
    }
    const limit = Math.min(
      500,
      Math.max(1, parseInt(String((data as { limit?: number })?.limit ?? 200), 10) || 200),
    );
    const snap = await admin.firestore().collection("igrejas").limit(limit).get();
    const results: Record<string, unknown>[] = [];
    for (const doc of snap.docs) {
      try {
        results.push(await runTenantFirestoreCollectionMigration(doc.id));
      } catch (e) {
        results.push({
          tenantId: doc.id,
          status: "error",
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
    return { processed: results.length, results };
  });
