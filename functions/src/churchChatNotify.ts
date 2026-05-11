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

async function collectFcmTokensForUids(uids: string[]): Promise<string[]> {
  const out = new Set<string>();
  for (const raw of uids) {
    const uid = String(raw || "").trim();
    if (uid.length < 8) continue;
    const tokSnap = await db.collection("users").doc(uid).collection("fcmTokens").get();
    for (const t of tokSnap.docs) {
      const token = String((t.data() || {}).token || "").trim();
      if (token) out.add(token);
    }
  }
  return [...out];
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

function previewFromMessage(msg: Record<string, unknown>): string {
  const mtype = String(msg.type || "text");
  if (mtype === "text") return String(msg.text || "").trim().slice(0, 140);
  if (mtype === "image") return "📷 Imagem";
  if (mtype === "video") return "🎬 Vídeo";
  if (mtype === "audio") return "🎵 Áudio";
  return "Nova mensagem";
}

/** Push aos outros participantes do thread — respeita [users.pushChat]. */
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

    const recipientPushOn: string[] = [];
    for (const uid of recipients) {
      let pushChat = true;
      try {
        const udoc = await db.collection("users").doc(uid).get();
        const p = udoc.data()?.pushChat;
        if (p === false) pushChat = false;
      } catch (_) {
        pushChat = true;
      }
      if (!pushChat) continue;

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

    const tokens = await collectFcmTokensForUids(recipientPushOn);
    if (!tokens.length) return null;

    const threadType = String(thread.type || "");
    let title = String(thread.title || "").trim() || "Conversas";
    if (threadType === "dm") {
      title = senderName;
    }

    const preview = previewFromMessage(msg as Record<string, unknown>);
    const body =
      threadType === "department"
        ? `${senderName}: ${preview || "Nova mensagem"}`
        : preview || "Nova mensagem";

    const messages: admin.messaging.Message[] = tokens.map((token) =>
      buildGyTokenMessage({
        token,
        title,
        body: body.slice(0, 200),
        data: {
          tenantId,
          type: "novo_chat",
          threadId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "chat",
      })
    );

    await sendEachInBatches(messages);
    return null;
  });
