import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const db = admin.firestore();

/** `dm_{uidMenor}_{uidMaior}` — UIDs Firebase não contêm `_`. */
export function parseDmThreadParticipants(threadId: string): [string, string] | null {
  if (!threadId.startsWith("dm_")) return null;
  const body = threadId.slice(3);
  const i = body.indexOf("_");
  if (i <= 0 || i >= body.length - 1) return null;
  const u1 = body.slice(0, i).trim();
  const u2 = body.slice(i + 1).trim();
  if (!u1 || !u2 || u1 === u2) return null;
  return [u1, u2];
}

function patchesForDmThread(
  threadId: string,
  data: FirebaseFirestore.DocumentData,
): FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> | null {
  const parsed = parseDmThreadParticipants(threadId);
  if (!parsed) return null;

  const patches: Record<string, unknown> = {};
  const [u1, u2] = parsed;
  const want = [u1, u2];
  const current = data.participantUids;
  const hasBoth =
    Array.isArray(current) &&
    current.map((e) => String(e)).includes(u1) &&
    current.map((e) => String(e)).includes(u2);
  if (!hasBoth) {
    patches.participantUids = want;
  }
  if (data.type !== "dm") {
    patches.type = "dm";
  }
  if (!data.lastMessageAt) {
    patches.lastMessageAt =
      data.updatedAt || data.createdAt || admin.firestore.FieldValue.serverTimestamp();
  }
  return Object.keys(patches).length > 0 ? patches : null;
}

export async function repairDmThreadsForTenant(tenantId: string): Promise<number> {
  const snap = await db
    .collection("igrejas")
    .doc(tenantId)
    .collection("chat_threads")
    .get();
  let n = 0;
  const batch = db.batch();
  let batchCount = 0;
  for (const doc of snap.docs) {
    if (!doc.id.startsWith("dm_")) continue;
    const data = doc.data();
    const patches = patchesForDmThread(doc.id, data);
    if (!patches) continue;
    batch.update(doc.ref, patches);
    batchCount++;
    n++;
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }
  if (batchCount > 0) await batch.commit();
  return n;
}

/** Corrige DM antigos sem `lastMessageAt` / `participantUids` (lista do app usa orderBy + arrayContains). */
export const onChurchChatDmThreadWrite = functions.firestore
  .document("igrejas/{tenantId}/chat_threads/{threadId}")
  .onWrite(async (change, context) => {
    const threadId = String(context.params.threadId || "");
    if (!threadId.startsWith("dm_")) return;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return;
    const patches = patchesForDmThread(threadId, after);
    if (!patches) return;
    await change.after.ref.update(patches);
  });

/** Garante `lastMessageAt` + `participantUids` no thread após cada mensagem (lista do hub). */
export const onChurchChatMessageIndexThread = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/chat_threads/{threadId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const tenantId = String(context.params.tenantId || "");
    const threadId = String(context.params.threadId || "");
    const msg = snap.data() || {};
    const threadRef = db
      .collection("igrejas")
      .doc(tenantId)
      .collection("chat_threads")
      .doc(threadId);

    const preview = (() => {
      const t = String(msg.type || "text");
      if (t === "image") return "📷 Foto";
      if (t === "video") return "🎬 Vídeo";
      if (t === "audio") return "🎤 Áudio";
      if (t === "sticker") return "🎨 Figurinha";
      const text = String(msg.text || "").trim();
      return text.length > 120 ? `${text.slice(0, 117)}…` : text || "Mensagem";
    })();

    const patches: Record<string, unknown> = {
      lastMessageAt: msg.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      lastMessagePreview: preview,
      lastSenderUid: String(msg.senderUid || ""),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (threadId.startsWith("dm_")) {
      const parsed = parseDmThreadParticipants(threadId);
      if (parsed) patches.participantUids = parsed;
      patches.type = "dm";
    }

    try {
      await threadRef.set(patches, { merge: true });
    } catch (e) {
      functions.logger.warn("onChurchChatMessageIndexThread", { tenantId, threadId, e });
    }
    return null;
  });

/** Backfill agendado — conversas individuais voltam à query do hub sem novo build. */
export const backfillChurchChatDmThreads = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const churches = await db.collection("igrejas").select().get();
    let total = 0;
    for (const church of churches.docs) {
      try {
        total += await repairDmThreadsForTenant(church.id);
      } catch (e) {
        functions.logger.warn("backfillChurchChatDmThreads", { tenantId: church.id, e });
      }
    }
    if (total > 0) {
      functions.logger.info(`backfillChurchChatDmThreads: ${total} thread(s) corrigido(s)`);
    }
  });

/** Reparo imediato — qualquer membro autenticado da igreja (nativo sem lista de conversas). */
export const repairChurchChatDmThreads = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const body = (data || {}) as Record<string, unknown>;
    const { resolveTenantIdForCallable } = await import("./tenantCallableResolve");
    const tenantId = await resolveTenantIdForCallable(
      {
        uid: context.auth.uid,
        token: context.auth.token as Record<string, unknown>,
      },
      String(body.tenantId || ""),
    );
    if (!tenantId) {
      throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const n = await repairDmThreadsForTenant(tenantId);
    return { tenantId, repaired: n };
  });
