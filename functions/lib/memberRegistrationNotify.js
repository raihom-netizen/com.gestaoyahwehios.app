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
exports.isPublicMemberSignup = isPublicMemberSignup;
exports.notifyGestoresNewMember = notifyGestoresNewMember;
/**
 * Push FCM quando há novo cadastro de membro — só gestores da igreja (pastor, admin, gestor, secretário).
 * Tópico: `gypush_{tenantSafe}_gestores` (inscrição no app por papel).
 */
const admin = __importStar(require("firebase-admin"));
const notificationBranding_1 = require("./notificationBranding");
const pushNovoConteudo_1 = require("./pushNovoConteudo");
function getDb() {
    return admin.firestore();
}
function isPublicMemberSignup(data) {
    if (data.PUBLIC_SIGNUP === true || data.public_signup === true)
        return true;
    const status = String(data.STATUS || data.status || "")
        .trim()
        .toLowerCase();
    return status.includes("pendente") || status.includes("aguard");
}
async function notifyGestoresNewMember(params) {
    const tenantId = String(params.tenantId || "").trim();
    const membroId = String(params.membroId || "").trim();
    const nome = String(params.nome || "Novo membro").trim() || "Novo membro";
    if (!tenantId || !membroId)
        return;
    const publicSignup = isPublicMemberSignup(params.data);
    const body = publicSignup
        ? `${nome} cadastrou-se pelo site público. Toque para ver ou aprovar.`
        : `${nome} foi cadastrado(a) na igreja. Toque para ver a ficha.`;
    await (0, pushNovoConteudo_1.sendGyTopicPushCluster)(tenantId, "gestores", (effectiveTenantId) => (0, notificationBranding_1.buildGyTopicMessage)({
        topic: (0, pushNovoConteudo_1.topicPushNovo)(effectiveTenantId, "gestores"),
        title: publicSignup ? "⚡ Novo cadastro (site)" : "👤 Novo membro",
        body,
        data: {
            type: "new_member",
            tenantId: effectiveTenantId,
            memberId: membroId,
            publicSignup: publicSignup ? "1" : "0",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        module: "membro",
    }));
    try {
        await getDb().collection("igrejas").doc(tenantId).collection("notificacoes").add({
            type: "novo_membro",
            title: publicSignup ? "Novo cadastro (site)" : "Novo membro",
            body,
            memberId: membroId,
            memberName: nome,
            publicSignup,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    catch (_) {
        /* in-app opcional */
    }
}
//# sourceMappingURL=memberRegistrationNotify.js.map