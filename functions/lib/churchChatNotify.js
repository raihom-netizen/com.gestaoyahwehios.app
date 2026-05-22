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
exports.onChurchChatMessageCreated = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const notificationBranding_1 = require("./notificationBranding");
const db = admin.firestore();
/** Alinhado a `ChurchChatAlertNotificationService` (Flutter) — canais para FCM em segundo plano. */
const FCM_CHAT_ANDROID_SOUND = "gy_fcm_chat_sound";
const FCM_CHAT_ANDROID_VIBRATE = "gy_fcm_chat_vibrate";
const FCM_CHAT_ANDROID_SILENT = "gy_fcm_chat_silent";
function parseStringArray(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const x of raw) {
        const s = String(x ?? "").trim();
        if (s)
            out.push(s);
    }
    return out;
}
function normalizeAlertMode(raw) {
    const m = String(raw ?? "").trim().toLowerCase();
    if (m === "vibrate" || m === "silent" || m === "sound")
        return m;
    return "sound";
}
function threadNotifMapFromPrefs(raw) {
    if (!raw || typeof raw !== "object")
        return {};
    const out = {};
    for (const [k, v] of Object.entries(raw)) {
        const id = String(k).trim();
        if (!id)
            continue;
        out[id] = normalizeAlertMode(v);
    }
    return out;
}
function chatDeliveryForMode(mode) {
    switch (mode) {
        case "silent":
            return {
                androidChannelId: FCM_CHAT_ANDROID_SILENT,
                iosSound: null,
                iosInterruptionLevel: "passive",
            };
        case "vibrate":
            return {
                androidChannelId: FCM_CHAT_ANDROID_VIBRATE,
                iosSound: null,
                iosInterruptionLevel: "active",
            };
        default:
            return {
                androidChannelId: FCM_CHAT_ANDROID_SOUND,
                iosSound: "default",
                iosInterruptionLevel: "active",
            };
    }
}
/** `pushChat` + `pushChatAlertMode` por uid (lotes de 10). */
async function loadUsersChatPushState(uids) {
    const out = new Map();
    const unique = [...new Set(uids.map((u) => String(u || "").trim()).filter((u) => u.length >= 8))];
    const step = 10;
    for (let i = 0; i < unique.length; i += step) {
        const slice = unique.slice(i, i + step);
        const refs = slice.map((uid) => db.collection("users").doc(uid));
        const snaps = await db.getAll(...refs);
        for (let j = 0; j < snaps.length; j++) {
            const uid = slice[j];
            const s = snaps[j];
            if (!s.exists) {
                out.set(uid, { enabled: true, globalMode: "sound" });
                continue;
            }
            const d = s.data() || {};
            out.set(uid, {
                enabled: d.pushChat !== false,
                globalMode: normalizeAlertMode(d.pushChatAlertMode),
            });
        }
    }
    return out;
}
async function loadChatMemberPrefsBatch(tenantId, uids) {
    const out = new Map();
    const unique = [...new Set(uids.map((u) => String(u || "").trim()).filter((u) => u.length >= 8))];
    const step = 10;
    for (let i = 0; i < unique.length; i += step) {
        const slice = unique.slice(i, i + step);
        const refs = slice.map((uid) => db.collection("igrejas").doc(tenantId).collection("chat_member_prefs").doc(uid));
        const snaps = await db.getAll(...refs);
        for (let j = 0; j < snaps.length; j++) {
            out.set(slice[j], snaps[j].exists ? snaps[j].data() || {} : {});
        }
    }
    return out;
}
function resolveRecipientChatAlertMode(opts) {
    const threadModes = threadNotifMapFromPrefs(opts.prefs.threadNotifModes);
    const th = threadModes[opts.threadId];
    if (th)
        return th;
    if (opts.threadType === "dm") {
        const peer = String(opts.senderUid || "").trim();
        const peerMap = threadNotifMapFromPrefs(opts.prefs.dmPeerAlertModes);
        if (peer && peerMap[peer])
            return peerMap[peer];
        if (opts.prefs.dmNotificationStyle != null) {
            return normalizeAlertMode(opts.prefs.dmNotificationStyle);
        }
    }
    else {
        const dep = String(opts.departmentId || "").trim();
        const dm = threadNotifMapFromPrefs(opts.prefs.departmentAlertModes);
        if (dep && dm[dep])
            return dm[dep];
        if (opts.prefs.groupNotificationStyle != null) {
            return normalizeAlertMode(opts.prefs.groupNotificationStyle);
        }
    }
    return opts.globalMode;
}
/** Tokens FCM com uid (para corpo personalizado «mencionou-o»). */
async function collectFcmTokenPairsForUids(uids) {
    const pairs = [];
    for (const raw of uids) {
        const uid = String(raw || "").trim();
        if (uid.length < 8)
            continue;
        try {
            const tokSnap = await db.collection("users").doc(uid).collection("fcmTokens").get();
            for (const t of tokSnap.docs) {
                const token = String((t.data() || {}).token || "").trim();
                if (token)
                    pairs.push({ uid, token });
            }
        }
        catch (_) {
            // continuar outros uids
        }
    }
    return pairs;
}
async function sendEachInBatches(messages) {
    const batchSize = 400;
    for (let i = 0; i < messages.length; i += batchSize) {
        const chunk = messages.slice(i, i + batchSize);
        try {
            await admin.messaging().sendEach(chunk);
        }
        catch (e) {
            functions.logger.error("churchChatNotify sendEach", e);
        }
    }
}
function previewFromMessage(msg) {
    const mtype = String(msg.type || "text");
    if (mtype === "text")
        return String(msg.text || "").trim().slice(0, 140);
    if (mtype === "image")
        return "📷 Imagem";
    if (mtype === "sticker")
        return "🎨 Figurinha";
    if (mtype === "video")
        return "🎬 Vídeo";
    if (mtype === "audio")
        return "🎵 Áudio";
    return "Nova mensagem";
}
/** Push aos outros participantes do thread — respeita [users.pushChat] e modos de alerta (som/vibrar/silêncio) em segundo plano. */
exports.onChurchChatMessageCreated = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/chat_threads/{threadId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId;
    const threadId = context.params.threadId;
    const msg = snap.data() || {};
    const senderUid = String(msg.senderUid || "").trim();
    if (!senderUid)
        return null;
    if (String(msg.deliveryStatus || "") === "uploading")
        return null;
    const threadSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("chat_threads")
        .doc(threadId)
        .get();
    if (!threadSnap.exists)
        return null;
    const thread = threadSnap.data() || {};
    const participants = parseStringArray(thread.participantUids);
    const recipients = participants.filter((u) => u && u !== senderUid);
    if (!recipients.length)
        return null;
    const titlesByUid = (thread.titlesByUid || {});
    const senderName = String(titlesByUid[senderUid] || "").trim() || "Alguém";
    const mentionedSet = new Set(parseStringArray(msg.mentionedUids));
    const userChatState = await loadUsersChatPushState(recipients);
    const candidates = recipients.filter((u) => userChatState.get(u)?.enabled !== false);
    if (!candidates.length)
        return null;
    const prefsByUid = await loadChatMemberPrefsBatch(tenantId, candidates);
    const recipientPushOn = [];
    for (const uid of candidates) {
        const prefs = prefsByUid.get(uid) || {};
        try {
            const muted = parseStringArray(prefs.mutedThreadIds);
            const blocked = parseStringArray(prefs.blockedPeerUids);
            if (muted.includes(threadId))
                continue;
            if (blocked.includes(senderUid))
                continue;
        }
        catch (_) {
            // continuar
        }
        recipientPushOn.push(uid);
    }
    if (!recipientPushOn.length)
        return null;
    const pairs = await collectFcmTokenPairsForUids(recipientPushOn);
    if (!pairs.length)
        return null;
    const threadType = String(thread.type || "");
    const departmentIdRaw = String(thread.departmentId || "").trim();
    const departmentIdFromThreadId = threadId.startsWith("dept_") && threadId.length > 5 ? threadId.slice(5) : "";
    const departmentIdForPush = threadType === "department"
        ? (departmentIdRaw || departmentIdFromThreadId)
        : "";
    let title = String(thread.title || "").trim() || "Conversas";
    if (threadType === "dm") {
        title = senderName;
    }
    const preview = previewFromMessage(msg);
    const threadTypeNorm = threadType === "dm" ? "dm" : "department";
    const messages = [];
    for (const { uid, token } of pairs) {
        const wasMentioned = threadType === "department" && mentionedSet.has(uid) && uid !== senderUid;
        const body = threadType === "department"
            ? wasMentioned
                ? `${senderName} mencionou-o: ${preview || "Nova mensagem"}`.slice(0, 200)
                : `${senderName}: ${preview || "Nova mensagem"}`.slice(0, 200)
            : (preview || "Nova mensagem").slice(0, 200);
        const prefs = prefsByUid.get(uid) || {};
        const globalMode = userChatState.get(uid)?.globalMode ?? "sound";
        const bgMode = resolveRecipientChatAlertMode({
            prefs,
            globalMode,
            threadId,
            threadType: threadTypeNorm,
            senderUid,
            departmentId: departmentIdForPush,
        });
        const chatDelivery = chatDeliveryForMode(bgMode);
        messages.push((0, notificationBranding_1.buildGyTokenMessage)({
            token,
            title,
            body,
            data: {
                tenantId,
                type: "novo_chat",
                threadId,
                threadType: threadTypeNorm,
                senderUid,
                gyChatBgMode: bgMode,
                ...(threadType === "dm"
                    ? { dmPeerUid: senderUid }
                    : departmentIdForPush
                        ? { departmentId: departmentIdForPush }
                        : {}),
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                ...(wasMentioned ? { chatMention: "1" } : {}),
            },
            module: "chat",
            chatDelivery,
        }));
    }
    await sendEachInBatches(messages);
    return null;
});
//# sourceMappingURL=churchChatNotify.js.map