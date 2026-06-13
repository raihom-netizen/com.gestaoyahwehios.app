import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type {
  CollectionReference,
  DocumentReference,
  Firestore,
  QueryDocumentSnapshot,
  WriteBatch,
} from "firebase-admin/firestore";
import { needsTenantFieldsStamp, tenantFieldsPatch } from "./churchTenantFields";
import { provisionChurchTenant } from "./churchTenantProvisioning";

const BATCH_LIMIT = 400;
const DOC_PAGE = 200;

export type ChurchTenantFieldsBackfillStats = {
  churchId: string;
  rootStamped: boolean;
  docsStamped: number;
  docsSkipped: number;
  docsScanned: number;
  batchesCommitted: number;
  errors: number;
};

type Counters = {
  stamped: number;
  skipped: number;
  scanned: number;
  batchOps: number;
  batchesCommitted: number;
  errors: number;
};

function isMasterCaller(context: functions.https.CallableContext): boolean {
  const email = String(context.auth?.token?.email ?? "").toLowerCase();
  if (email === "raihom@gmail.com") return true;
  const role = String(context.auth?.token?.role ?? "").toUpperCase();
  return role === "MASTER" || role === "ADM" || role === "ADMIN";
}

async function flushBatch(
  batch: WriteBatch,
  counters: Counters,
): Promise<WriteBatch> {
  if (counters.batchOps <= 0) {
    return batch;
  }
  await batch.commit();
  counters.batchesCommitted += 1;
  counters.batchOps = 0;
  return admin.firestore().batch();
}

async function queueStamp(
  ref: DocumentReference,
  churchId: string,
  data: Record<string, unknown>,
  batch: WriteBatch,
  counters: Counters,
): Promise<WriteBatch> {
  counters.scanned += 1;
  if (!needsTenantFieldsStamp(data, churchId)) {
    counters.skipped += 1;
    return batch;
  }
  batch.set(ref, tenantFieldsPatch(churchId), { merge: true });
  counters.stamped += 1;
  counters.batchOps += 1;
  if (counters.batchOps >= BATCH_LIMIT) {
    return flushBatch(batch, counters);
  }
  return batch;
}

async function stampDocumentTree(
  firestore: Firestore,
  docRef: DocumentReference,
  churchId: string,
  counters: Counters,
  batch: WriteBatch,
  maxDocs: number,
): Promise<WriteBatch> {
  if (counters.scanned >= maxDocs) return batch;

  const snap = await docRef.get();
  if (snap.exists) {
    batch = await queueStamp(
      docRef,
      churchId,
      (snap.data() ?? {}) as Record<string, unknown>,
      batch,
      counters,
    );
  }

  if (counters.scanned >= maxDocs) return batch;

  let subcols: CollectionReference[];
  try {
    subcols = await docRef.listCollections();
  } catch {
    counters.errors += 1;
    return batch;
  }

  for (const col of subcols) {
    let last: QueryDocumentSnapshot | undefined;
    for (;;) {
      if (counters.scanned >= maxDocs) break;
      let q = col.orderBy(admin.firestore.FieldPath.documentId()).limit(DOC_PAGE);
      if (last) q = q.startAfter(last);
      const page = await q.get();
      if (page.empty) break;
      for (const child of page.docs) {
        batch = await stampDocumentTree(
          firestore,
          child.ref,
          churchId,
          counters,
          batch,
          maxDocs,
        );
        if (counters.scanned >= maxDocs) break;
      }
      last = page.docs[page.docs.length - 1];
      if (page.size < DOC_PAGE) break;
    }
    if (counters.scanned >= maxDocs) break;
  }

  return batch;
}

/** Percorre recursivamente `igrejas/{churchId}/**` e grava churchId + tenantId. */
export async function backfillChurchTenantFieldsForChurch(
  firestore: Firestore,
  churchId: string,
  options: { maxDocs?: number; skipRootProvision?: boolean } = {},
): Promise<ChurchTenantFieldsBackfillStats> {
  const id = String(churchId || "").trim();
  const maxDocs = Math.min(
    25000,
    Math.max(100, Number(options.maxDocs) || 8000),
  );
  const counters: Counters = {
    stamped: 0,
    skipped: 0,
    scanned: 0,
    batchOps: 0,
    batchesCommitted: 0,
    errors: 0,
  };

  if (!id) {
    return {
      churchId: "",
      rootStamped: false,
      docsStamped: 0,
      docsSkipped: 0,
      docsScanned: 0,
      batchesCommitted: 0,
      errors: 1,
    };
  }

  let rootStamped = false;
  if (!options.skipRootProvision) {
    try {
      const provision = await provisionChurchTenant(id, {
        source: "backfillChurchTenantFields",
        skipStorage: true,
      });
      rootStamped = provision.rootPatched;
    } catch (e) {
      functions.logger.warn("backfillChurchTenantFields provisionChurchTenant", {
        churchId: id,
        e,
      });
      counters.errors += 1;
    }
  }

  const churchRef = firestore.collection("igrejas").doc(id);
  let batch = firestore.batch();
  batch = await stampDocumentTree(
    firestore,
    churchRef,
    id,
    counters,
    batch,
    maxDocs,
  );
  if (counters.batchOps > 0) {
    batch = await flushBatch(batch, counters);
  }

  return {
    churchId: id,
    rootStamped,
    docsStamped: counters.stamped,
    docsSkipped: counters.skipped,
    docsScanned: counters.scanned,
    batchesCommitted: counters.batchesCommitted,
    errors: counters.errors,
  };
}

/** Callable master — uma igreja ou todas (paginado por igreja). */
export const backfillChurchTenantFields = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    if (!isMasterCaller(context)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Somente operador master.",
      );
    }

    const db = admin.firestore();
    const one = String((data as { tenantId?: string; churchId?: string })?.tenantId
      ?? (data as { churchId?: string })?.churchId
      ?? "").trim();
    const maxDocs = Number((data as { maxDocs?: number })?.maxDocs) || 8000;

    if (one) {
      const stats = await backfillChurchTenantFieldsForChurch(db, one, { maxDocs });
      return { ok: true, churches: 1, stats: [stats] };
    }

    const statsList: ChurchTenantFieldsBackfillStats[] = [];
    let last: QueryDocumentSnapshot | undefined;
    const page = 40;
    for (;;) {
      let q = db
        .collection("igrejas")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(page);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        statsList.push(
          await backfillChurchTenantFieldsForChurch(db, doc.id, { maxDocs }),
        );
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < page) break;
    }

    return {
      ok: true,
      churches: statsList.length,
      totalStamped: statsList.reduce((n, s) => n + s.docsStamped, 0),
      stats: statsList,
    };
  });

/** Auto-stamp em subcoleções directas (nível 1). */
export const stampIgrejaSubdocTenantFields = functions
  .region("us-central1")
  .firestore.document("igrejas/{churchId}/{collectionId}/{docId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;
    const churchId = String(context.params.churchId).trim();
    const data = change.after.data() as Record<string, unknown>;
    if (!needsTenantFieldsStamp(data, churchId)) return;
    await change.after.ref.set(tenantFieldsPatch(churchId, false), { merge: true });
  });

/** Auto-stamp em mensagens de chat (nível 2). */
export const stampIgrejaChatMessageTenantFields = functions
  .region("us-central1")
  .firestore.document("igrejas/{churchId}/chats/{chatId}/messages/{messageId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;
    const churchId = String(context.params.churchId).trim();
    const data = change.after.data() as Record<string, unknown>;
    if (!needsTenantFieldsStamp(data, churchId)) return;
    await change.after.ref.set(tenantFieldsPatch(churchId, false), { merge: true });
  });
