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
exports.scheduledEventoReminders = void 0;
/**
 * Lembretes push — eventos da igreja ~24h e ~60min antes de `startAt`.
 * Respeita tópico `gypush_{churchId}_evento` (preferência pushEventos no app).
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const pushNovoConteudo_1 = require("./pushNovoConteudo");
const notificationBranding_1 = require("./notificationBranding");
const db = admin.firestore();
const MS_24H = 24 * 60 * 60 * 1000;
const MS_60M = 60 * 60 * 1000;
const WINDOW_MS = 14 * 60 * 1000;
function clip(s, max) {
    const t = String(s || "").trim();
    if (t.length <= max)
        return t;
    return `${t.slice(0, Math.max(0, max - 3))}...`;
}
function eventTitle(d) {
    const t = String(d.title || d.titulo || "Evento").trim();
    return t || "Evento";
}
exports.scheduledEventoReminders = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .pubsub.schedule("every 10 minutes")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const now = Date.now();
    const horizon = now + 50 * 60 * 60 * 1000;
    const igrejasSnap = await db.collection("igrejas").get();
    let sent24 = 0;
    let sent60 = 0;
    for (const church of igrejasSnap.docs) {
        const tenantId = church.id;
        const col = db.collection("igrejas").doc(tenantId).collection("eventos");
        let q;
        try {
            q = await col
                .where("startAt", ">=", admin.firestore.Timestamp.fromMillis(now))
                .where("startAt", "<=", admin.firestore.Timestamp.fromMillis(horizon))
                .get();
        }
        catch (e) {
            functions.logger.warn("eventoReminders query", { tenantId, e });
            continue;
        }
        for (const doc of q.docs) {
            const d = doc.data();
            const ts = d.startAt;
            if (!ts || typeof ts.toMillis !== "function")
                continue;
            const eventMs = ts.toMillis();
            const diffMs = eventMs - now;
            if (diffMs <= 0)
                continue;
            const title = clip(eventTitle(d), 80);
            const when = ts.toDate().toLocaleString("pt-BR", {
                timeZone: "America/Sao_Paulo",
            });
            const in24hWindow = diffMs >= MS_24H - WINDOW_MS && diffMs <= MS_24H + WINDOW_MS;
            if (in24hWindow && !d.eventReminder24hSentAt) {
                try {
                    await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
                        topic: (0, pushNovoConteudo_1.topicPushNovo)(tenantId, "evento"),
                        title: "📅 Evento amanhã",
                        body: clip(`${title} • ${when}`, 160),
                        data: {
                            type: "evento_reminder",
                            reminder: "24h",
                            tenantId,
                            eventoId: doc.id,
                            click_action: "FLUTTER_NOTIFICATION_CLICK",
                        },
                        module: "evento",
                    }));
                    await doc.ref.update({
                        eventReminder24hSentAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    sent24++;
                }
                catch (e) {
                    functions.logger.error("FCM 24h evento", { tenantId, id: doc.id, e });
                }
            }
            const in60Window = diffMs >= MS_60M - WINDOW_MS && diffMs <= MS_60M + WINDOW_MS;
            if (in60Window && !d.eventReminder60mSentAt) {
                try {
                    await admin.messaging().send((0, notificationBranding_1.buildGyTopicMessage)({
                        topic: (0, pushNovoConteudo_1.topicPushNovo)(tenantId, "evento"),
                        title: "📅 Evento em 1 hora",
                        body: clip(`${title} • ${when}`, 160),
                        data: {
                            type: "evento_reminder",
                            reminder: "60m",
                            tenantId,
                            eventoId: doc.id,
                            click_action: "FLUTTER_NOTIFICATION_CLICK",
                        },
                        module: "evento",
                    }));
                    await doc.ref.update({
                        eventReminder60mSentAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    sent60++;
                }
                catch (e) {
                    functions.logger.error("FCM 60m evento", { tenantId, id: doc.id, e });
                }
            }
        }
    }
    functions.logger.info("scheduledEventoReminders done", { sent24, sent60 });
    return null;
});
//# sourceMappingURL=eventoReminders.js.map