"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.telegramOutgoingMessage = exports.telegramSetWebhook = exports.telegramBotWebhook = void 0;
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
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const params_1 = require("firebase-functions/params");
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
/** URL base pública do projeto — usada para montar o webhook. */
const PUBLIC_PROJECT_URL_PARAM = (0, params_1.defineString)("PUBLIC_PROJECT_URL", { default: "" });
/** Secret opcional para validar chamadas no webhook. */
const TELEGRAM_WEBHOOK_SECRET_PARAM = (0, params_1.defineString)("TELEGRAM_WEBHOOK_SECRET", { default: "" });
function safe(s) {
    return String(s ?? "").trim();
}
function telegramApiUrl(botToken, method) {
    return `https://api.telegram.org/bot${botToken}/${method}`;
}
async function telegramApiJson(botToken, method, body) {
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
        return (await res.json());
    }
    catch (e) {
        console.warn(`Telegram API ${method} error:`, e);
        return null;
    }
}
/** Recupera a configuração da ponte no documento raiz da igreja. */
async function getBridgeConfig(churchId) {
    if (!churchId)
        return null;
    try {
        const snap = await db.collection("igrejas").doc(churchId).get();
        const data = snap.exists ? (snap.data() ?? {}) : {};
        const bridge = data.telegramBridge;
        if (!bridge || typeof bridge !== "object")
            return null;
        return bridge;
    }
    catch (e) {
        console.warn(`getBridgeConfig ${churchId}:`, e);
        return null;
    }
}
/**
 * Procura a igreja vinculada a um chatId do Telegram.
 * Em produção o índice `telegramBridge.chatId` deve existir (firestore.indexes.json).
 */
async function resolveChurchByTelegramChatId(chatId) {
    if (!chatId)
        return null;
    try {
        const snap = await db
            .collection("igrejas")
            .where("telegramBridge.enabled", "==", true)
            .where("telegramBridge.chatId", "==", chatId)
            .limit(1)
            .get();
        if (snap.empty)
            return null;
        const doc = snap.docs[0];
        const config = doc.data()?.telegramBridge;
        if (!config?.botToken)
            return null;
        return { churchId: doc.id, config };
    }
    catch (e) {
        console.warn("resolveChurchByTelegramChatId:", e);
        return null;
    }
}
function senderName(from) {
    if (!from)
        return "Telegram";
    const parts = [from.first_name, from.last_name].filter(Boolean);
    if (parts.length)
        return parts.join(" ");
    return from.username ? `@${from.username}` : `Telegram ${from.id}`;
}
function senderPhotoUrl(from) {
    // Telegram não entrega avatar direto no update; deixamos vazio.
    return "";
}
/** Converte um update do Telegram em um documento de mensagem do YAHWEH Chat. */
function telegramMessageToFirestoreFields(msg, churchId, threadId) {
    const from = msg.from;
    const text = safe(msg.text ?? msg.caption);
    const base = {
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
        const best = msg.photo.reduce((a, b) => (a.file_size ?? 0) > (b.file_size ?? 0) ? a : b);
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
    if (text.length === 0)
        return null;
    return { ...base, type: "text", mediaType: "text" };
}
/** Baixa um arquivo do Telegram e faz upload para o Storage da igreja. */
async function downloadTelegramFileToStorage(botToken, churchId, fileId, fileNameHint) {
    try {
        const fileInfo = await telegramApiJson(botToken, "getFile", { file_id: fileId });
        if (!fileInfo?.ok || !fileInfo.result?.file_path)
            return null;
        const url = `https://api.telegram.org/file/bot${botToken}/${fileInfo.result.file_path}`;
        const res = await fetch(url);
        if (!res.ok)
            return null;
        const buffer = Buffer.from(await res.arrayBuffer());
        if (buffer.length === 0)
            return null;
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
    }
    catch (e) {
        console.warn("downloadTelegramFileToStorage error:", e);
        return null;
    }
}
/**
 * Recebe updates do Telegram (webhook).
 * Recomenda-se proteger com um secret na query string: `?secret=...`.
 */
exports.telegramBotWebhook = functions.https.onRequest(async (req, res) => {
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
    const update = req.body;
    const msg = update.message ??
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
        await threadRef.set({
            title: msg.chat.title || "Telegram",
            telegramChatId: chatId,
            telegramBotToken: config.botToken,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (_) {
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
    }
    catch (e) {
        console.warn("telegramBotWebhook write error:", e);
        res.status(500).send("Write failed");
        return;
    }
    // Download de mídia para o Storage da igreja (best-effort; não bloqueia resposta).
    const fileId = safe(fields.telegramFileId);
    const fileNameHint = safe(fields.fileName) ||
        (fields.type === "image" ? "photo.jpg" : fields.type === "video" ? "video.mp4" : "file.bin");
    if (fileId && config.botToken) {
        (async () => {
            try {
                const media = await downloadTelegramFileToStorage(config.botToken, churchId, fileId, fileNameHint);
                if (media) {
                    await messageRef.set({
                        mediaUrl: media.downloadUrl,
                        storagePath: media.storagePath,
                        mimeType: media.mimeType,
                        uploadCompleted: true,
                    }, { merge: true });
                }
            }
            catch (_) {
                // best effort
            }
        })();
    }
    res.status(200).send("OK");
});
/** Cloud Function callable para configurar o webhook no Telegram. */
exports.telegramSetWebhook = functions.https.onCall(async (data, context) => {
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
    const result = await telegramApiJson(botToken, "setWebhook", isDisabling
        ? { url: "" }
        : {
            url: webhookUrl,
            allowed_updates: ["message", "edited_message", "channel_post"],
            max_connections: 20,
        });
    if (!result?.ok) {
        throw new functions.https.HttpsError("internal", `Falha ao configurar webhook: ${result?.description || "desconhecido"}`);
    }
    if (isDisabling) {
        await db
            .collection("igrejas")
            .doc(churchId)
            .set({
            telegramBridge: {
                enabled: false,
                botToken: "",
                chatId: "",
                webhookUrl: "",
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        }, { merge: true });
        return { ok: true, webhookUrl: "" };
    }
    // Salva token e habilita bridge no doc da igreja.
    await db
        .collection("igrejas")
        .doc(churchId)
        .set({
        telegramBridge: {
            enabled: true,
            botToken: botToken,
            chatId: chatId,
            threadDocId: safe(data.threadDocId) || "telegram",
            webhookSecret: secret,
            webhookUrl: webhookUrl,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    }, { merge: true });
    return { ok: true, webhookUrl };
});
/**
 * Envia mensagens do Firestore para o Telegram.
 * Trigger em `igrejas/{churchId}/chats/{threadId}/messages/{messageId}`.
 */
exports.telegramOutgoingMessage = functions.firestore
    .document("igrejas/{churchId}/chats/{threadId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
    const data = snap.data() ?? {};
    if (data.telegramInbound === true)
        return;
    if (data.telegramMessageId)
        return;
    const churchId = context.params.churchId;
    const threadId = context.params.threadId;
    const messageId = context.params.messageId;
    const config = await getBridgeConfig(churchId);
    if (!config?.enabled || !config.botToken)
        return;
    // So encaminha threads explicitamente vinculadas ao Telegram.
    const threadDoc = await db
        .collection("igrejas")
        .doc(churchId)
        .collection("chats")
        .doc(threadId)
        .get();
    const threadData = threadDoc.exists ? (threadDoc.data() ?? {}) : {};
    // Resolve chatId: primeiro do thread, depois do bridge config da igreja.
    const effectiveChatId = safe(threadData.telegramChatId) || safe(config.chatId);
    if (!effectiveChatId)
        return;
    const text = safe(data.text);
    const type = safe(data.type ?? data.mediaType ?? "text");
    const replyTo = data.replyToMessageId ? Number(data.replyToMessageId) : undefined;
    const messageThreadId = config.threadId ? Number(config.threadId) : undefined;
    let result = null;
    try {
        if (type === "image" && (data.telegramFileId || data.storagePath || data.mediaUrl)) {
            const fileIdOrUrl = safe(data.telegramFileId || data.mediaUrl);
            const photoBody = {
                chat_id: effectiveChatId,
                caption: text || undefined,
            };
            if (messageThreadId)
                photoBody.message_thread_id = messageThreadId;
            if (replyTo)
                photoBody.reply_to_message_id = replyTo;
            if (fileIdOrUrl) {
                photoBody.photo = fileIdOrUrl;
                result = await telegramApiJson(config.botToken, "sendPhoto", photoBody);
            }
        }
        else if (["document", "pdf", "doc", "xls", "zip"].includes(type) &&
            (data.telegramFileId || data.mediaUrl)) {
            const docBody = {
                chat_id: effectiveChatId,
                document: safe(data.telegramFileId || data.mediaUrl),
                caption: text || undefined,
            };
            if (messageThreadId)
                docBody.message_thread_id = messageThreadId;
            if (replyTo)
                docBody.reply_to_message_id = replyTo;
            result = await telegramApiJson(config.botToken, "sendDocument", docBody);
        }
        else if (type === "audio" && (data.telegramFileId || data.mediaUrl)) {
            const audioBody = {
                chat_id: effectiveChatId,
                audio: safe(data.telegramFileId || data.mediaUrl),
                caption: text || undefined,
                duration: data.duration ?? undefined,
            };
            if (messageThreadId)
                audioBody.message_thread_id = messageThreadId;
            if (replyTo)
                audioBody.reply_to_message_id = replyTo;
            result = await telegramApiJson(config.botToken, "sendAudio", audioBody);
        }
        else if (type === "video" && (data.telegramFileId || data.mediaUrl)) {
            const videoBody = {
                chat_id: effectiveChatId,
                video: safe(data.telegramFileId || data.mediaUrl),
                caption: text || undefined,
                duration: data.duration ?? undefined,
            };
            if (messageThreadId)
                videoBody.message_thread_id = messageThreadId;
            if (replyTo)
                videoBody.reply_to_message_id = replyTo;
            result = await telegramApiJson(config.botToken, "sendVideo", videoBody);
        }
        else if (text.length > 0) {
            const textBody = {
                chat_id: effectiveChatId,
                text: text.slice(0, 4096),
            };
            if (messageThreadId)
                textBody.message_thread_id = messageThreadId;
            if (replyTo)
                textBody.reply_to_message_id = replyTo;
            result = await telegramApiJson(config.botToken, "sendMessage", textBody);
        }
        if (result?.ok && result.result?.message_id) {
            await snap.ref.set({
                telegramMessageId: result.result.message_id,
                telegramChatId: effectiveChatId,
                status: "delivered",
                deliveryStatus: "delivered",
                deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        else if (result && !result.ok) {
            await snap.ref.set({
                telegramSendError: result.description || "unknown",
                status: "failed",
                deliveryStatus: "failed",
            }, { merge: true });
        }
    }
    catch (e) {
        console.warn("telegramOutgoingMessage error:", e);
        await snap.ref.set({
            telegramSendError: String(e).slice(0, 500),
            status: "failed",
            deliveryStatus: "failed",
        }, { merge: true });
    }
});
//# sourceMappingURL=telegramBotBridge.js.map