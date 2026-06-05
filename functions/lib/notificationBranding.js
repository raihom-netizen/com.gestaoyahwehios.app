"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.gestaoBrandLogoUrl = gestaoBrandLogoUrl;
exports.moduleAccentHex = moduleAccentHex;
exports.buildGyTopicMessage = buildGyTopicMessage;
exports.buildGyTokenMessage = buildGyTokenMessage;
exports.emailHeaderGradient = emailHeaderGradient;
exports.emailModuleBadgeLabel = emailModuleBadgeLabel;
const params_1 = require("firebase-functions/params");
const PUBLIC_WEB_BASE = (0, params_1.defineString)("PUBLIC_WEB_BASE_URL", {
    default: "https://gestaoyahweh.com.br",
});
/** PNG marca (512px+); mesmo URL nos e-mails e imagem rica do push. */
function gestaoBrandLogoUrl() {
    const base = PUBLIC_WEB_BASE.value().trim().replace(/\/$/, "");
    return `${base}/brand/gestao_yahweh_mark.png`;
}
function moduleAccentHex(kind) {
    switch (kind) {
        case "aviso":
            return "#0EA5E9";
        case "evento":
            return "#F97316";
        case "escala":
            return "#14B8A6";
        case "fornecedor_agenda":
            return "#475569";
        case "pastoral":
            return "#EAB308";
        case "devocional":
            return "#6366F1";
        case "aniversario":
            return "#E11D48";
        case "financeiro":
            return "#37474F";
        case "membro":
            return "#2563EB";
        case "generico":
            return "#3B82F6";
        case "chat":
            return "#8B5CF6";
        default:
            return "#3B82F6";
    }
}
function mergeData(data, module) {
    return {
        ...data,
        gy_module: module,
        gy_brand: "gestao_yahweh",
    };
}
/** Push por tópico — imagem rica + barra de cor (Android) + APNS image. */
function buildGyTopicMessage(params) {
    const img = gestaoBrandLogoUrl();
    const color = moduleAccentHex(params.module);
    const data = mergeData(params.data, params.module);
    return {
        topic: params.topic,
        notification: {
            title: params.title,
            body: params.body,
            imageUrl: img,
        },
        data,
        android: {
            priority: "high",
            notification: {
                imageUrl: img,
                color,
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    mutableContent: true,
                },
            },
            fcmOptions: {
                imageUrl: img,
            },
        },
    };
}
/** Push direto para um token FCM. */
function buildGyTokenMessage(params) {
    const img = gestaoBrandLogoUrl();
    const color = moduleAccentHex(params.module);
    const data = mergeData(params.data, params.module);
    const chat = params.chatDelivery;
    const aps = {
        mutableContent: true,
    };
    const apnsHeaders = {
        "apns-priority": "10",
    };
    if (chat) {
        if (chat.iosSound != null && chat.iosSound.length > 0) {
            aps.sound = chat.iosSound;
        }
        if (chat.iosInterruptionLevel) {
            apnsHeaders["apns-interruption-level"] = chat.iosInterruptionLevel;
        }
    }
    else {
        aps.sound = "default";
    }
    const androidNotif = {
        imageUrl: img,
        color,
        ...(chat?.androidChannelId ? { channelId: chat.androidChannelId } : {}),
    };
    return {
        token: params.token,
        notification: {
            title: params.title,
            body: params.body,
            imageUrl: img,
        },
        data,
        android: {
            priority: "high",
            notification: androidNotif,
        },
        apns: {
            headers: apnsHeaders,
            payload: {
                aps,
            },
            fcmOptions: {
                imageUrl: img,
            },
        },
    };
}
function emailHeaderGradient(module) {
    switch (module) {
        case "aviso":
            return "linear-gradient(135deg,#0EA5E9 0%,#0369A1 100%)";
        case "escala":
            return "linear-gradient(135deg,#14B8A6 0%,#0F766E 100%)";
        case "evento":
            return "linear-gradient(135deg,#F97316 0%,#C2410C 100%)";
        case "aniversario":
            return "linear-gradient(135deg,#FB7185 0%,#BE123C 100%)";
        case "generico":
        default:
            return "linear-gradient(135deg,#0A3D91 0%,#1E40AF 100%)";
    }
}
function emailModuleBadgeLabel(module) {
    switch (module) {
        case "aviso":
            return "Mural de avisos";
        case "escala":
            return "Escalas";
        case "evento":
            return "Eventos";
        case "aniversario":
            return "Aniversário";
        default:
            return "Gestão YAHWEH";
    }
}
//# sourceMappingURL=notificationBranding.js.map