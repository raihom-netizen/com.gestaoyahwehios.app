/**
 * Ponte Telegram Bot API <-> Firestore Chat da Igreja.
 *
 * Objetivo: manter o visual do YAHWEH Chat, mas usar o Telegram como
 * transporte real das mensagens (motor por baixo).
 *
 * Fluxo:
 * 1. Administrador cria um bot em @BotFather e obtém um token.
 * 2. Administrador cria/grupo no Telegram, adiciona o bot e obtém o chatId.
 * 3. Painel da igreja grava `telegramBridge` em `igrejas/{churchId}`.
 * 4. Webhook do bot aponta para a Cloud Function `telegramBotWebhook`.
 * 5. Mensagens vindas do Telegram são escritas em
 *    `igrejas/{churchId}/chats/{threadId}/messages`.
 * 6. Mensagens escritas pelo Flutter nessa collection disparam
 *    `telegramOutgoingMessage`, que repassa para o Telegram.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { defineString } from "firebase-functions/params";
import { getFirestore } from "firebase-admin/firestore";

const db = getFirestore();

/** URL base pública do projeto — usada para montar o webhook. */
const PUBLIC_PROJECT_URL_PARAM = defineString("PUBLIC_PROJECT_URL", { default: "" });

/** Secret opcional para validar chamadas no webhook. */
const TELEGRAM_WEBHOOK_SECRET_PARAM = defineString("TELEGRAM_WEBHOOK_SECRET", { default: "" });

interface TelegramBridgeConfig {
  enabled?: boolean;
  botToken?: string;
  chatId?: string;
  threadId?: string;
  threadDocId?: string;
  webhookSecret?: string;
}

interface TelegramUser {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
}

interface TelegramChat {
  id: number;
  type?: string;
  title?: string;
}

interface TelegramMessage {
  message_id: number;
  from?: TelegramUser;
  chat: TelegramChat;
  date: number;
  text?: string;
  caption?: string;
  photo?: Array<{ file_id: string; file_size?: number; width: number; height: number }>;
  document?: { file_id: string; file_name?: string; mime_type?: string; file_size?: number };
  voice?: { file_id: string; duration: number; mime_type?: string; file_size?: number };
  video?: { file_id: string; duration: number; mime_type?: string; file_size?: number; width?: number; height?: number };
  audio?: { file_id: string; duration: number; performer?: string; title?: string; mime_type?: string; file_size?: number };
}

interface TelegramUpdate {
  update_id: number;
  message?: TelegramMessage;
  edited_message?: TelegramMessage;
  channel_post?: TelegramMessage;
  edited_channel_post?: TelegramMessage;
}

function safe(s: unknown): string {
  return String(s ?? "").trim();
}

function telegramApiUrl(botToken: string, method: string): string {
  return `https://api.telegram.org/bot${botToken}/${method}`;
}

async function telegramApiJson<T>(botToken: string, method: string, body: unknown): Promise<T | null> {
  try {
    const res = await fetch(telegramApiUrl(botToken, method), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      console.warn(`Telegram API ${method} HTTP ${res.status}: ${text}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (e) {
    console.warn(`Telegram API ${method} error:`, e);
    return null;
  }
}

/** Recupera a configuração da ponte no documento raiz da igreja. */
async function getBridgeConfig(churchId: string): Promise<TelegramBridgeConfig | null> {
  if (!churchId) return null;
  try {
    const snap = await db.collection("igrejas").doc(churchId).get();
    const data = snap.exists ? (snap.data() ?? {}) : {};
    const bridge = data.telegramBridge;
    if (!bridge || typeof bridge !== "object") return null;
    return bridge as TelegramBridgeConfig;
  } catch (e) {
    console.warn(`getBridgeConfig ${churchId}:`, e);
    return null;
  }
}

/**
 * Procura a igreja vinculada a um chatId do Telegram.
 * Em produção o índice `telegramBridge.chatId` deve existir (firestore.indexes.json).
 */
async function resolveChurchByTelegramChatId(chatId: string): Promise<{ churchId: string; config: TelegramBridgeConfig } | null> {
  if (!chatId) return null;
  try {
    const snap = await db
      .collection("igrejas")
      .where("telegramBridge.enabled", "==", true)
      .where("telegramBridge.chatId", "==", chatId)
      .limit(1)
      .get();
    if (snap.empty) return null;
    const doc = snap.docs[0];
    const config = doc.data()?.telegramBridge as TelegramBridgeConfig | undefined;
    if (!config?.botToken) return null;
    return { churchId: doc.id, config };
  } catch (e) {
    console.warn("resolveChurchByTelegramChatId:", e);
    return null;
  }
}

function senderName(from?: TelegramUser): string {
  if (!from) return "Telegram";
  const parts = [from.first_name, from.last_name].filter(Boolean);
  if (parts.length) return parts.join(" ");
  return from.username ? `@${from.username}` : `Telegram ${from.id}`;
}

function senderPhotoUrl(from?: TelegramUser): string {
  // Telegram não entrega avatar direto no update; deixamos vazio.
  return "";
}

/** Converte um update do Telegram em um documento de mensagem do YAHWEH Chat. */
function telegramMessageToFirestoreFields(
  msg: TelegramMessage,
  churchId: string,
  threadId: string,
): Record<string, unknown> | null {
  const from = msg.from;
  const text = safe(msg.text ?? msg.caption);
  const base: Record<string, unknown> = {
    telegramMessageId: msg.message_id,
    telegramChatId: String(msg.chat.id),
    telegramInbound: true,
    senderId: `telegram_${from?.id ?? msg.chat.id}`,
    senderUid: `telegram_${from?.id ?? msg.chat.id}`,
    senderName: senderName(from),
    senderDisplayName: senderName(from),
    text: text,
    createdAt: admin.firestore.Timestamp.fromMillis(msg.date * 1000),
    sentAt: admin.firestore.Timestamp.fromMillis(msg.date * 1000),
    status: "delivered",
    deliveryStatus: "delivered",
    uploadCompleted: true,
    churchId: churchId,
    tenantId: churchId,
    participantUids: [],
  };

  if (msg.photo && msg.photo.length > 0) {
    const best = msg.photo.reduce((a, b) =>
      (a.file_size ?? 0) > (b.file_size ?? 0) ? a : b,
    );
    return {
      ...base,
      type: "image",
      mediaType: "image",
      telegramFileId: best.file_id,
      text: text || "📷 Foto",
    };
  }

  if (msg.document) {
    return {
      ...base,
      type: "document",
      mediaType: "document",
      telegramFileId: msg.document.file_id,
      fileName: msg.document.file_name,
      mimeType: msg.document.mime_type,
      size: msg.document.file_size,
      text: text || `📎 ${msg.document.file_name || "Documento"}`,
    };
  }

  if (msg.voice) {
    return {
      ...base,
      type: "audio",
      mediaType: "audio",
      telegramFileId: msg.voice.file_id,
      duration: msg.voice.duration,
      mimeType: msg.voice.mime_type,
      size: msg.voice.file_size,
      text: text || "🎤 Áudio",
    };
  }

  if (msg.video) {
    return {
      ...base,
      type: "video",
      mediaType: "video",
      telegramFileId: msg.video.file_id,
      duration: msg.video.duration,
      width: msg.video.width,
      height: msg.video.height,
      mimeType: msg.video.mime_type,
      size: msg.video.file_size,
      text: text || "🎥 Vídeo",
    };
  }

  if (text.length === 0) return null;

  return { ...base, type: "text", mediaType: "text" };
}

/** Baixa um arquivo do Telegram e faz upload para o Storage da igreja. */
async function downloadTelegramFileToStorage(
  botToken: string,
  churchId: string,
  fileId: string,
  fileNameHint: string,
): Promise<{ downloadUrl: string; storagePath: string; mimeType?: string } | null> {
  try {
    const fileInfo = await telegramApiJson<{ ok: boolean; result?: { file_path?: string }; description?: string }>(
      botToken,
      "getFile",
      { file_id: fileId },
    );
    if (!fileInfo?.ok || !fileInfo.result?.file_path) return null;

    const url = `https://api.telegram.org/file/bot${botToken}/${fileInfo.result.file_path}`;
    const res = await fetch(url);
    if (!res.ok) return null;

    const buffer = Buffer.from(await res.arrayBuffer());
    if (buffer.length === 0) return null;

    const ext = fileNameHint.includes(".")
      ? fileNameHint.split(".").pop()
      : fileInfo.result.file_path.split(".").pop() || "bin";
    const safeName = `${Date.now()}_${fileId}.${ext}`.replace(/[^a-zA-Z0-9_.\-]/g, "_");
    const storagePath = `igrejas/${churchId}/chat_media/telegram_inbound/${safeName}`;

    const contentType = res.headers.get("content-type") || "application/octet-stream";
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    await file.save(buffer, {
      metadata: { contentType },
      public: false,
    });

    const [downloadUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 1000 * 60 * 60 * 24 * 365 * 5, // 5 anos
    });

    return { downloadUrl, storagePath, mimeType: contentType };
  } catch (e) {
    console.warn("downloadTelegramFileToStorage error:", e);
    return null;
  }
}

/**
 * Recebe updates do Telegram (webhook).
 * Recomenda-se proteger com um secret na query string: `?secret=...`.
 */
export const telegramBotWebhook = functions.https.onRequest(async (req, res) => {
  const expected = TELEGRAM_WEBHOOK_SECRET_PARAM.value();
  if (expected) {
    const got = safe(req.query.secret);
    if (got !== expected) {
      res.status(401).send("Unauthorized");
      return;
    }
  }

  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const update = req.body as TelegramUpdate;
  const msg =
    update.message ??
    update.edited_message ??
    update.channel_post ??
    update.edited_channel_post;
  if (!msg) {
    res.status(200).send("OK");
    return;
  }

  const chatId = String(msg.chat.id);
  const resolved = await resolveChurchByTelegramChatId(chatId);
  if (!resolved) {
    // Responde 200 para o Telegram não tentar reenviar.
    res.status(200).send("OK");
    return;
  }

  const { churchId, config } = resolved;
  const threadId = safe(config.threadDocId) || "telegram";

  // Garante que o thread existe (best-effort).
  const threadRef = db.collection("igrejas").doc(churchId).collection("chats").doc(threadId);
  try {
    await threadRef.set(
      {
        title: msg.chat.title || "Telegram",
        telegramChatId: chatId,
        telegramBotToken: config.botToken,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (_) {
    /* não bloqueia */
  }

  const fields = telegramMessageToFirestoreFields(msg, churchId, threadId);
  if (!fields) {
    res.status(200).send("OK");
    return;
  }

  const messageId = `tg_${msg.message_id}_${msg.date}`;
  const messageRef = threadRef.collection("messages").doc(messageId);
  try {
    await messageRef.set(fields, { merge: true });
  } catch (e) {
    console.warn("telegramBotWebhook write error:", e);
    res.status(500).send("Write failed");
    return;
  }

  // Download de mídia para o Storage da igreja (best-effort; não bloqueia resposta).
  const fileId = safe(fields.telegramFileId);
  const fileNameHint =
    safe(fields.fileName) ||
    (fields.type === "image" ? "photo.jpg" : fields.type === "video" ? "video.mp4" : "file.bin");
  if (fileId && config.botToken) {
    (async () => {
      try {
        const media = await downloadTelegramFileToStorage(
          config.botToken!,
          churchId,
          fileId,
          fileNameHint,
        );
        if (media) {
          await messageRef.set(
            {
              mediaUrl: media.downloadUrl,
              storagePath: media.storagePath,
              mimeType: media.mimeType,
              uploadCompleted: true,
            },
            { merge: true },
          );
        }
      } catch (_) {
        // best effort
      }
    })();
  }

  res.status(200).send("OK");
});

/** Cloud Function callable para configurar o webhook no Telegram. */
export const telegramSetWebhook = functions.https.onCall(async (data, context) => {
  const churchId = safe(data.churchId);
  const botToken = safe(data.botToken);
  if (!churchId || !botToken) {
    throw new functions.https.HttpsError("invalid-argument", "churchId e botToken são obrigatórios.");
  }

  // Autenticação básica: exige usuário logado.
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const baseUrl = PUBLIC_PROJECT_URL_PARAM.value() || `https://${process.env.GCLOUD_PROJECT}.web.app`;
  const secret = TELEGRAM_WEBHOOK_SECRET_PARAM.value();
  const webhookUrl = secret
    ? `${baseUrl}/telegramBotWebhook?secret=${encodeURIComponent(secret)}`
    : `${baseUrl}/telegramBotWebhook`;

  const chatId = safe(data.chatId);
  const isDisabling = chatId.length === 0;

  const result = await telegramApiJson<{ ok: boolean; description?: string; result?: boolean }>(
    botToken,
    "setWebhook",
    isDisabling
      ? { url: "" }
      : {
          url: webhookUrl,
          allowed_updates: ["message", "edited_message", "channel_post"],
          max_connections: 20,
        },
  );

  if (!result?.ok) {
    throw new functions.https.HttpsError(
      "internal",
      `Falha ao configurar webhook: ${result?.description || "desconhecido"}`,
    );
  }

  if (isDisabling) {
    await db
      .collection("igrejas")
      .doc(churchId)
      .set(
        {
          telegramBridge: {
            enabled: false,
            botToken: "",
            chatId: "",
            webhookUrl: "",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );
    return { ok: true, webhookUrl: "" };
  }

  // Salva token e habilita bridge no doc da igreja.
  await db
    .collection("igrejas")
    .doc(churchId)
    .set(
      {
        telegramBridge: {
          enabled: true,
          botToken: botToken,
          chatId: chatId,
          threadDocId: safe(data.threadDocId) || "telegram",
          webhookSecret: secret,
          webhookUrl: webhookUrl,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );

  return { ok: true, webhookUrl };
});

/**
 * Envia mensagens do Firestore para o Telegram.
 * Trigger em `igrejas/{churchId}/chats/{threadId}/messages/{messageId}`.
 */
export const telegramOutgoingMessage = functions.firestore
  .document("igrejas/{churchId}/chats/{threadId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() ?? {};
    if (data.telegramInbound === true) return;
    if (data.telegramMessageId) return;

    const churchId = context.params.churchId;
    const threadId = context.params.threadId;
    const messageId = context.params.messageId;

    const config = await getBridgeConfig(churchId);
    if (!config?.enabled || !config.botToken) return;

    // So encaminha threads explicitamente vinculadas ao Telegram.
    const threadDoc = await db
      .collection("igrejas")
      .doc(churchId)
      .collection("chats")
      .doc(threadId)
      .get();
    const threadData = threadDoc.exists ? (threadDoc.data() ?? {}) : {};
    const effectiveChatId = safe(threadData.telegramChatId);
    if (!effectiveChatId) return;

    const text = safe(data.text);
    const type = safe(data.type ?? data.mediaType ?? "text");
    const replyTo = data.replyToMessageId ? Number(data.replyToMessageId) : undefined;
    const messageThreadId = config.threadId ? Number(config.threadId) : undefined;

    let result: { ok: boolean; result?: { message_id: number }; description?: string } | null = null;

    try {
      if (type === "image" && (data.telegramFileId || data.storagePath || data.mediaUrl)) {
        const fileIdOrUrl = safe(data.telegramFileId || data.mediaUrl);
        const photoBody: Record<string, unknown> = {
          chat_id: effectiveChatId,
          caption: text || undefined,
        };
        if (messageThreadId) photoBody.message_thread_id = messageThreadId;
        if (replyTo) photoBody.reply_to_message_id = replyTo;

        if (fileIdOrUrl) {
          photoBody.photo = fileIdOrUrl;
          result = await telegramApiJson<{ ok: boolean; result?: { message_id: number }; description?: string }>(config.botToken, "sendPhoto", photoBody);
        }
      } else if (
        ["document", "pdf", "doc", "xls", "zip"].includes(type) &&
        (data.telegramFileId || data.mediaUrl)
      ) {
        const docBody: Record<string, unknown> = {
          chat_id: effectiveChatId,
          document: safe(data.telegramFileId || data.mediaUrl),
          caption: text || undefined,
        };
        if (messageThreadId) docBody.message_thread_id = messageThreadId;
        if (replyTo) docBody.reply_to_message_id = replyTo;
        result = await telegramApiJson<{ ok: boolean; result?: { message_id: number }; description?: string }>(config.botToken, "sendDocument", docBody);
      } else if (type === "audio" && (data.telegramFileId || data.mediaUrl)) {
        const audioBody: Record<string, unknown> = {
          chat_id: effectiveChatId,
          audio: safe(data.telegramFileId || data.mediaUrl),
          caption: text || undefined,
          duration: data.duration ?? undefined,
        };
        if (messageThreadId) audioBody.message_thread_id = messageThreadId;
        if (replyTo) audioBody.reply_to_message_id = replyTo;
        result = await telegramApiJson<{ ok: boolean; result?: { message_id: number }; description?: string }>(config.botToken, "sendAudio", audioBody);
      } else if (type === "video" && (data.telegramFileId || data.mediaUrl)) {
        const videoBody: Record<string, unknown> = {
          chat_id: effectiveChatId,
          video: safe(data.telegramFileId || data.mediaUrl),
          caption: text || undefined,
          duration: data.duration ?? undefined,
        };
        if (messageThreadId) videoBody.message_thread_id = messageThreadId;
        if (replyTo) videoBody.reply_to_message_id = replyTo;
        result = await telegramApiJson<{ ok: boolean; result?: { message_id: number }; description?: string }>(config.botToken, "sendVideo", videoBody);
      } else if (text.length > 0) {
        const textBody: Record<string, unknown> = {
          chat_id: effectiveChatId,
          text: text.slice(0, 4096),
        };
        if (messageThreadId) textBody.message_thread_id = messageThreadId;
        if (replyTo) textBody.reply_to_message_id = replyTo;
        result = await telegramApiJson<{ ok: boolean; result?: { message_id: number }; description?: string }>(config.botToken, "sendMessage", textBody);
      }

      if (result?.ok && result.result?.message_id) {
        await snap.ref.set(
          {
            telegramMessageId: result.result.message_id,
            telegramChatId: effectiveChatId,
            status: "delivered",
            deliveryStatus: "delivered",
            deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } else if (result && !result.ok) {
        await snap.ref.set(
          {
            telegramSendError: result.description || "unknown",
            status: "failed",
            deliveryStatus: "failed",
          },
          { merge: true },
        );
      }
    } catch (e) {
      console.warn("telegramOutgoingMessage error:", e);
      await snap.ref.set(
        {
          telegramSendError: String(e).slice(0, 500),
          status: "failed",
          deliveryStatus: "failed",
        },
        { merge: true },
      );
    }
  });
