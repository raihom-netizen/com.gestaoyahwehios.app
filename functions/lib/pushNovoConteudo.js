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
exports.sendGyTopicPushCluster = sendGyTopicPushCluster;
/**
 * Push FCM por tópico quando há conteúdo novo (avisos, eventos na agenda, escalas).
 * Tópicos alinhados ao app: `gypush_{tenantIdSafe}_{aviso|evento|escala|aniversario|gestores}`.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const churchClusterAnchors_1 = require("./churchClusterAnchors");
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
async function sendTopicPushCluster(tenantId, kind, build) {
    const sent = new Set();
    for (const tid of (0, churchClusterAnchors_1.tenantIdsForPushTopic)(tenantId)) {
        const topic = topicPushNovo(tid, kind);
        if (sent.has(topic))
            continue;
        sent.add(topic);
        await admin.messaging().send(build(tid));
    }
}
/** Push FCM para todos os alias do cluster (BPC legado + canónico). */
async function sendGyTopicPushCluster(tenantId, kind, build) {
    await sendTopicPushCluster(tenantId, kind, build);
}
async function sendNovoAvisoMuralPush(tenantId, postId, d) {
    const title = clip(String(d.title || d.titulo || "Novo aviso"), 80) || "Novo aviso";
    const rawBody = String(d.text || d.body || d.mensagem || "").trim();
    const body = clip(rawBody, 140) || title;
    await sendTopicPushCluster(tenantId, "aviso", (effectiveTenantId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(effectiveTenantId, "aviso"),
        title: "📢 Novo aviso",
        body,
        data: {
            type: "novo_aviso",
            tenantId: effectiveTenantId,
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
exports.onNovoAvisoMuralPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId;
    const d = snap.data() || {};
    const publishState = String(d.publishState || "").trim();
    if (publishState === "uploading" || publishState === "draft")
        return null;
    try {
        await sendNovoAvisoMuralPush(tenantId, context.params.id, d);
    }
    catch (e) {
        functions.logger.error("onNovoAvisoMuralPush FCM", { tenantId, e });
    }
    return null;
});
/** Push quando o aviso passa de `uploading` → `published`. */
exports.onNovoAvisoMuralPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeState = String(before.publishState || "").trim();
    const afterState = String(after.publishState || "").trim();
    if (beforeState === afterState)
        return null;
    if (afterState !== "published")
        return null;
    if (beforeState !== "uploading" && beforeState !== "draft")
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
    await sendTopicPushCluster(tenantId, "evento", (effectiveTenantId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(effectiveTenantId, "evento"),
        title: "📅 Novo evento",
        body,
        data: {
            type: "novo_evento",
            tenantId: effectiveTenantId,
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
    const publishState = String(d.publishState || "").trim();
    if (publishState === "uploading" || publishState === "draft")
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
/** Push quando o evento passa de `uploading` → `published`. */
exports.onNovoEventoNoticiaPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (!isEventoDoc(after))
        return null;
    const beforeState = String(before.publishState || "").trim();
    const afterState = String(after.publishState || "").trim();
    if (beforeState === afterState)
        return null;
    if (afterState !== "published")
        return null;
    if (beforeState !== "uploading" && beforeState !== "draft")
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