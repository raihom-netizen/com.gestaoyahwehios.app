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
exports.onNovoEventoNoticiaPublishedPush = exports.onNovoEventoNoticiaPush = exports.onNovoAvisoMuralPublishedPush = exports.onNovoAvisoMuralPush = void 0;
exports.topicPushNovo = topicPushNovo;
exports.sendGyTopicPush = sendGyTopicPush;
exports.sendGyTopicPushCluster = sendGyTopicPushCluster;
/**
 * Push FCM por tópico — avisos, eventos (path directo `igrejas/{churchId}/…`).
 * Tópicos: `gypush_{churchId}_{aviso|evento|escala|aniversario|gestores}`.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const notificationBranding_1 = require("./notificationBranding");
function safeTid(t) {
    return String(t || "").replace(/[^a-zA-Z0-9\-_.~%]/g, "_");
}
/** Mesmo formato usado no Flutter [FcmService.topicPushNovo]. */
function topicPushNovo(tenantId, kind) {
    return `gypush_${safeTid(tenantId)}_${kind}`;
}
function clip(s, max) {
    const t = String(s || "").trim();
    if (t.length <= max)
        return t;
    return `${t.slice(0, Math.max(0, max - 3))}...`;
}
function isEventoDoc(d) {
    const typeRaw = String(d.type || "evento").trim().toLowerCase();
    return typeRaw === "evento" || typeRaw === "" || typeRaw === "event";
}
async function recordTenantNotification(tenantId, payload) {
    try {
        await admin
            .firestore()
            .collection("igrejas")
            .doc(tenantId)
            .collection("notificacoes")
            .add({
            ...payload,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    catch (_) {
        /* opcional */
    }
}
/** Push FCM directo — um tópico por `igrejas/{churchId}`. */
async function sendGyTopicPush(tenantId, kind, build) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    await admin.messaging().send(build(tid));
}
/** @deprecated Use [sendGyTopicPush] — mantido para imports legados. */
async function sendGyTopicPushCluster(tenantId, kind, build) {
    await sendGyTopicPush(tenantId, kind, build);
}
async function sendNovoAvisoMuralPush(tenantId, postId, d) {
    if (!isPushableAvisoDoc(d)) {
        functions.logger.info("onNovoAvisoMuralPush skip — título/mídia inválidos", {
            tenantId,
            postId,
        });
        return;
    }
    const title = clip(String(d.title || d.titulo || "Novo aviso"), 80) || "Novo aviso";
    const rawBody = String(d.text || d.body || d.mensagem || "").trim();
    const body = clip(rawBody, 140) || title;
    await sendGyTopicPush(tenantId, "aviso", (churchId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(churchId, "aviso"),
        title: "📢 Novo aviso",
        body,
        data: {
            type: "novo_aviso",
            tenantId: churchId,
            postId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "aviso",
    }));
    await recordTenantNotification(tenantId, {
        type: "novo_aviso",
        title: "Novo aviso",
        body,
        postId,
    });
}
function isPublishedFeedDoc(d) {
    const state = String(d.publishState || "").trim().toLowerCase();
    if (state === "uploading" || state === "draft")
        return false;
    if (state === "published" || state === "success")
        return true;
    if (d.publicado === true)
        return true;
    const status = String(d.status || "").trim().toLowerCase();
    return status === "publicado";
}
const JUNK_TITLES = new Set([
    "sem título",
    "sem titulo",
    "sem titulo.",
    "sem título.",
]);
function resolveFeedTitle(d) {
    for (const k of ["title", "titulo", "name", "nome"]) {
        const v = String(d[k] || "").trim();
        if (v)
            return v;
    }
    return "";
}
function hasValidFeedTitle(d) {
    const t = resolveFeedTitle(d);
    if (!t)
        return false;
    return !JUNK_TITLES.has(t.toLowerCase());
}
function hasValidFeedMedia(d) {
    for (const k of [
        "imageUrl",
        "coverPhotoUrl",
        "coverPhoto",
        "photoUrl",
        "bannerUrl",
        "fotoUrl",
        "imageStoragePath",
        "fotoPath",
        "thumbStoragePath",
        "bannerStoragePath",
        "storagePath",
    ]) {
        if (String(d[k] || "").trim())
            return true;
    }
    for (const k of ["imageUrls", "galeria", "photos", "photoUrls", "imageStoragePaths"]) {
        const raw = d[k];
        if (Array.isArray(raw) && raw.some((e) => String(e || "").trim()))
            return true;
    }
    return false;
}
function isPushableAvisoDoc(d) {
    return isPublishedFeedDoc(d) && hasValidFeedTitle(d) && hasValidFeedMedia(d);
}
exports.onNovoAvisoMuralPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId;
    const d = snap.data() || {};
    if (!isPushableAvisoDoc(d))
        return null;
    try {
        await sendNovoAvisoMuralPush(tenantId, context.params.id, d);
    }
    catch (e) {
        functions.logger.error("onNovoAvisoMuralPush FCM", { tenantId, e });
    }
    return null;
});
exports.onNovoAvisoMuralPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (isPublishedFeedDoc(before))
        return null;
    if (!isPushableAvisoDoc(after))
        return null;
    const tenantId = context.params.tenantId;
    try {
        await sendNovoAvisoMuralPush(tenantId, context.params.id, after);
    }
    catch (e) {
        functions.logger.error("onNovoAvisoMuralPublishedPush FCM", { tenantId, e });
    }
    return null;
});
async function sendNovoEventoNoticiaPush(tenantId, postId, d) {
    if (!isEventoDoc(d))
        return;
    const title = clip(String(d.title || d.titulo || "Novo evento"), 80) || "Novo evento";
    const startAt = d.startAt;
    let extra = "";
    if (startAt && typeof startAt.toDate === "function") {
        const dt = startAt.toDate();
        extra = ` • ${dt.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`;
    }
    const body = clip(`${title}${extra}`, 180);
    await sendGyTopicPush(tenantId, "evento", (churchId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(churchId, "evento"),
        title: "📅 Novo evento",
        body,
        data: {
            type: "novo_evento",
            tenantId: churchId,
            postId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "evento",
    }));
    await recordTenantNotification(tenantId, {
        type: "novo_evento",
        title: "Novo evento",
        body,
        postId,
    });
}
exports.onNovoEventoNoticiaPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{id}")
    .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    if (!isEventoDoc(d))
        return null;
    if (!isPublishedFeedDoc(d))
        return null;
    const tenantId = context.params.tenantId;
    try {
        await sendNovoEventoNoticiaPush(tenantId, context.params.id, d);
    }
    catch (e) {
        functions.logger.error("onNovoEventoNoticiaPush FCM", { tenantId, e });
    }
    return null;
});
exports.onNovoEventoNoticiaPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (!isEventoDoc(after))
        return null;
    if (isPublishedFeedDoc(before))
        return null;
    if (!isPublishedFeedDoc(after))
        return null;
    const tenantId = context.params.tenantId;
    try {
        await sendNovoEventoNoticiaPush(tenantId, context.params.id, after);
    }
    catch (e) {
        functions.logger.error("onNovoEventoNoticiaPublishedPush FCM", {
            tenantId,
            e,
        });
    }
    return null;
});
//# sourceMappingURL=pushNovoConteudo.js.map