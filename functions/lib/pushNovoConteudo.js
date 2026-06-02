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
/**
 * Push FCM por tópico quando há conteúdo novo (avisos, eventos na agenda, escalas).
 * Tópicos alinhados ao app: `gypush_{tenantIdSafe}_{aviso|evento|escala}`.
 * O app inscreve/desinscreve conforme `users/{uid}.pushAvisos`, `pushEventos`, `pushEscalas` (padrão true).
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
async function sendNovoAvisoMuralPush(tenantId, postId, d) {
    const title = clip(String(d.title || "Novo aviso"), 80) || "Novo aviso";
    const rawBody = String(d.text || d.body || d.mensagem || "").trim();
    const body = clip(rawBody, 140) || title;
    await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(tenantId, "aviso"),
        title: "📢 Novo aviso",
        body,
        data: {
            type: "novo_aviso",
            tenantId,
            postId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "aviso",
    }));
}
exports.onNovoAvisoMuralPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId;
    const d = snap.data() || {};
    if (String(d.publishState || "") === "uploading")
        return null;
    try {
        await sendNovoAvisoMuralPush(tenantId, context.params.id, d);
    }
    catch (e) {
        functions.logger.error("onNovoAvisoMuralPush FCM", { tenantId, e });
    }
    return null;
});
/** Push quando o aviso passa de `uploading` → `published` (publicação rápida no app). */
exports.onNovoAvisoMuralPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (String(before.publishState || "") !== "uploading")
        return null;
    if (String(after.publishState || "") !== "published")
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
    if (String(d.type || "").toLowerCase() !== "evento")
        return;
    const title = clip(String(d.title || "Novo evento"), 80) || "Novo evento";
    const startAt = d.startAt;
    let extra = "";
    if (startAt && typeof startAt.toDate === "function") {
        const dt = startAt.toDate();
        extra = ` • ${dt.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`;
    }
    const body = clip(`${title}${extra}`, 180);
    await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
        topic: topicPushNovo(tenantId, "evento"),
        title: "📅 Novo evento",
        body,
        data: {
            type: "novo_evento",
            tenantId,
            postId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "evento",
    }));
}
exports.onNovoEventoNoticiaPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{id}")
    .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    if (String(d.type || "").toLowerCase() !== "evento")
        return null;
    if (String(d.publishState || "") === "uploading")
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
/** Push quando o evento passa de `uploading` → `published` (fotos em segundo plano). */
exports.onNovoEventoNoticiaPublishedPush = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{id}")
    .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (String(after.type || "").toLowerCase() !== "evento")
        return null;
    if (String(before.publishState || "") !== "uploading")
        return null;
    if (String(after.publishState || "") !== "published")
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