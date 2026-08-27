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
exports.onNovoPedidoOracao = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const notificationBranding_1 = require("./notificationBranding");
const pushNovoConteudo_1 = require("./pushNovoConteudo");
exports.onNovoPedidoOracao = functions.region("us-central1").firestore
    .document("igrejas/{tenantId}/pedidos_oracao/{pedidoId}")
    .onCreate(async (snap, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    const pedidoId = String(context.params.pedidoId || snap.id || "").trim();
    if (!tenantId || !pedidoId)
        return null;
    const db = admin.firestore();
    const dedupe = db.collection("igrejas").doc(tenantId).collection("internal_notif_state").doc(`prayer_${pedidoId}`);
    const claimed = await db.runTransaction(async (tx) => {
        const existing = await tx.get(dedupe);
        if (existing.exists)
            return false;
        tx.create(dedupe, { type: "novo_pedido_oracao", pedidoId, createdAt: admin.firestore.FieldValue.serverTimestamp() });
        return true;
    });
    if (!claimed)
        return null;
    const d = (snap.data() || {});
    const title = String(d.titulo || d.title || "Novo pedido de oração").trim();
    const requester = String(d.nome || d.name || "Alguém").trim();
    const request = String(d.pedido || d.descricao || d.description || "Novo pedido de oração").replace(/\s+/g, " ").trim();
    const body = `${requester}: ${request.length > 150 ? request.slice(0, 147) + "..." : request}`;
    const deepLink = (0, pushNovoConteudo_1.buildGyNotificationDeepLink)(tenantId, `oracoes/${pedidoId}`);
    await db.collection("igrejas").doc(tenantId).collection("notificacoes").doc(`prayer_${pedidoId}`).set({ type: "novo_pedido_oracao", tenantId, prayerId: pedidoId, title, body, deepLink, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    await (0, pushNovoConteudo_1.sendGyTopicPush)(tenantId, "gestores", (churchId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: (0, pushNovoConteudo_1.topicPushNovo)(churchId, "gestores"), title, body, module: "generico",
        data: { type: "novo_pedido_oracao", tenantId: churchId, prayerId: pedidoId, deepLink, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    }));
    return null;
});
//# sourceMappingURL=prayerRegistrationNotify.js.map