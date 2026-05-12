import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { buildGyTokenMessage } from "./notificationBranding";

const db = admin.firestore();

function parseStringArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const x of raw) {
    const s = String(x ?? "").trim();
    if (s) out.push(s);
  }
  return out;
}

/** Tokens FCM com uid (para corpo personalizado «mencionou-o»). */
async function collectFcmTokenPairsForUids(
  uids: string[]
): Promise<Array<{ uid: string; token: string }>> {
  const pairs: Array<{ uid: string; token: string }> = [];
  for (const raw of uids) {
    const uid = String(raw || "").trim();
    if (uid.length < 8) continue;
    try {
      const tokSnap = await db.collection("users").doc(uid).collection("fcmTokens").get();
      for (const t of tokSnap.docs) {
        const token = String((t.data() || {}).token || "").trim();
        if (token) pairs.push({ uid, token });
      }
    } catch (_) {
      // continuar outros uids
    }
  }
  return pairs;
}

async function sendEachInBatches(messages: admin.messaging.Message[]): Promise<void> {
  const batchSize = 400;
  for (let i = 0; i < messages.length; i += batchSize) {
    const chunk = messages.slice(i, i + batchSize);
    try {
      await admin.messaging().sendEach(chunk);
    } catch (e) {
      functions.logger.error("churchChatNotify sendEach", e);
    }
  }
}

/** `pushChat !== false` por uid — leitura em lote (evita N get() sequenciais). */
async function uidsWithPushChatEnabled(uids: string[]): Promise<Set<string>> {
  const out = new Set<string>();
  const unique = [...new Set(uids.map((u) => String(u || "").trim()).filter((u) => u.length >= 8))];
  const step = 10;
  for (let i = 0; i < unique.length; i += step) {
    const slice = unique.slice(i, i + step);
    const refs = slice.map((uid) => db.collection("users").doc(uid));
    const snaps = await db.getAll(...refs);
    for (let j = 0; j < snaps.length; j++) {
      const s = snaps[j];
      const uid = slice[j];
      if (!s.exists) {
        out.add(uid);
        continue;
      }
      const p = s.data()?.pushChat;
      if (p !== false) out.add(uid);
    }
  }
  return out;
}

function previewFromMessage(msg: Record<string, unknown>): string {
  const mtype = String(msg.type || "text");
  if (mtype === "text") return String(msg.text || "").trim().slice(0, 140);
  if (mtype === "image") return "📷 Imagem";
  if (mtype === "sticker") return "🎨 Figurinha";
  if (mtype === "video") return "🎬 Vídeo";
  if (mtype === "audio") return "🎵 Áudio";
  return "Nova mensagem";
}

/** Push aos outros participantes do thread — respeita [users.pushChat]. Mencões em grupo: corpo dedicado. */
export const onChurchChatMessageCreated = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/chat_threads/{threadId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId as string;
    const threadId = context.params.threadId as string;
    const msg = snap.data() || {};
    const senderUid = String(msg.senderUid || "").trim();
    if (!senderUid) return null;

    const threadSnap = await db
      .collection("igrejas")
      .doc(tenantId)
      .collection("chat_threads")
      .doc(threadId)
      .get();
    if (!threadSnap.exists) return null;
    const thread = threadSnap.data() || {};
    const participants = parseStringArray(thread.participantUids);
    const recipients = participants.filter((u) => u && u !== senderUid);
    if (!recipients.length) return null;

    const titlesByUid = (thread.titlesByUid || {}) as Record<string, string>;
    const senderName = String(titlesByUid[senderUid] || "").trim() || "Alguém";

    const mentionedSet = new Set(parseStringArray(msg.mentionedUids));

    const pushOk = await uidsWithPushChatEnabled(recipients);

    const recipientPushOn: string[] = [];
    for (const uid of recipients) {
      if (!pushOk.has(uid)) continue;

      try {
        const prefsSnap = await db
          .collection("igrejas")
          .doc(tenantId)
          .collection("chat_member_prefs")
          .doc(uid)
          .get();
        const prefs = prefsSnap.data() || {};
        const muted = parseStringArray(prefs.mutedThreadIds);
        const blocked = parseStringArray(prefs.blockedPeerUids);
        if (muted.includes(threadId)) continue;
        if (blocked.includes(senderUid)) continue;
      } catch (_) {
        // sem doc de prefs: entregar notificação
      }

      recipientPushOn.push(uid);
    }
    if (!recipientPushOn.length) return null;

    const pairs = await collectFcmTokenPairsForUids(recipientPushOn);
    if (!pairs.length) return null;

    const threadType = String(thread.type || "");
    let title = String(thread.title || "").trim() || "Conversas";
    if (threadType === "dm") {
      title = senderName;
    }

    const preview = previewFromMessage(msg as Record<string, unknown>);

    const messages: admin.messaging.Message[] = [];
    for (const { uid, token } of pairs) {
      const wasMentioned =
        threadType === "department" && mentionedSet.has(uid) && uid !== senderUid;
      const body =
        threadType === "department"
          ? wasMentioned
            ? `${senderName} mencionou-o: ${preview || "Nova mensagem"}`.slice(0, 200)
            : `${senderName}: ${preview || "Nova mensagem"}`.slice(0, 200)
          : (preview || "Nova mensagem").slice(0, 200);

      messages.push(
        buildGyTokenMessage({
          token,
          title,
          body,
          data: {
            tenantId,
            type: "novo_chat",
            threadId,
            threadType: threadType === "dm" ? "dm" : "department",
            senderUid,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            ...(wasMentioned ? { chatMention: "1" } : {}),
          },
          module: "chat",
        })
      );
    }

    await sendEachInBatches(messages);
    return null;
  });
