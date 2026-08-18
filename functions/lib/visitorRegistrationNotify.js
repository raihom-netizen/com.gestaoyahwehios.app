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
exports.notifyGestoresNewVisitor = notifyGestoresNewVisitor;
/**
 * Push FCM quando há novo cadastro de visitante — só gestores da igreja
 * (pastor, admin, gestor, secretário). Espelha `memberRegistrationNotify.ts`.
 * Tópico: `gypush_{tenantSafe}_gestores` (inscrição no app por papel).
 */
const admin = __importStar(require("firebase-admin"));
const notificationBranding_1 = require("./notificationBranding");
const pushNovoConteudo_1 = require("./pushNovoConteudo");
function getDb() {
    return admin.firestore();
}
async function notifyGestoresNewVisitor(params) {
    const tenantId = String(params.tenantId || "").trim();
    const visitanteId = String(params.visitanteId || "").trim();
    const nome = String(params.nome || "Novo visitante").trim() || "Novo visitante";
    const telefone = String(params.telefone || "").trim();
    const email = String(params.email || "").trim();
    if (!tenantId || !visitanteId)
        return;
    const tituloVisitante = nome !== 'Novo visitante'
        ? 'Novo visitante: ' + nome
        : 'Novo visitante';
    const contactBits = [telefone, email].filter((s) => s.length > 0);
    const body = contactBits.length > 0
        ? `${nome} — ${contactBits.join(" · ")}. Toque para ver a ficha.`
        : `${nome} acabou de ser cadastrado(a). Toque para ver a ficha.`;
    await (0, pushNovoConteudo_1.sendGyTopicPush)(tenantId, "gestores", (churchId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: (0, pushNovoConteudo_1.topicPushNovo)(churchId, "gestores"),
        title: "🙋 " + tituloVisitante,
        body,
        data: {
            type: "novo_visitante",
            tenantId: churchId,
            visitorId: visitanteId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            deepLink: (0, pushNovoConteudo_1.buildGyNotificationDeepLink)(churchId, `visitante/${visitanteId}`),
        },
        module: "visitante",
    }));
    try {
        await getDb().collection("igrejas").doc(tenantId).collection("notificacoes").add({
            type: "novo_visitante",
            title: tituloVisitante,
            body,
            visitorId: visitanteId,
            visitorName: nome,
            visitorPhone: telefone || null,
            visitorEmail: email || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    catch (_) {
        /* in-app opcional */
    }
}
//# sourceMappingURL=visitorRegistrationNotify.js.map