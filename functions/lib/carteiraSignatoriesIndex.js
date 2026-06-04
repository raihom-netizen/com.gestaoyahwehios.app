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
exports.refreshCarteiraSignatoriesIndex = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const db = admin.firestore();
const ROLE_KEYS = [
    "gestor",
    "pastor",
    "pastora",
    "secretario",
    "secretaria",
    "tesoureiro",
    "lider",
];
function normalizeRoleKey(raw) {
    return String(raw || "")
        .toLowerCase()
        .trim()
        .replace(/\s+/g, "_")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");
}
function roleCanSign(key) {
    if (!key || key === "membro")
        return false;
    if (ROLE_KEYS.includes(key))
        return true;
    if (key.includes("lider") && (key.includes("depart") || key.includes("dept"))) {
        return true;
    }
    if (key.includes("tesour") || key.includes("secretar"))
        return true;
    return false;
}
function memberCanSign(data) {
    const flagged = data.certificadoSignatario === true || data.podeAssinarCertificado === true;
    const funcoes = data.FUNCOES ?? data.funcoes;
    const keys = [];
    if (Array.isArray(funcoes)) {
        for (const f of funcoes) {
            const k = normalizeRoleKey(String(f || ""));
            if (k)
                keys.push(k);
        }
    }
    const single = normalizeRoleKey(String(data.FUNCAO ?? data.funcao ?? data.CARGO ?? data.cargo ?? ""));
    if (single)
        keys.push(single);
    for (const k of keys) {
        if (roleCanSign(k))
            return true;
    }
    return flagged && keys.some((k) => roleCanSign(k));
}
function cargoLabel(data) {
    const cargo = String(data.CARGO ?? data.cargo ?? data.FUNCAO ?? data.funcao ?? "").trim();
    if (cargo)
        return cargo;
    return "Liderança";
}
/**
 * Índice denormalizado de signatários (carteirinha / certificados).
 * Grava em igrejas/{tenantId}/config/carteira_signatories — leitura O(1) no app.
 */
exports.refreshCarteiraSignatoriesIndex = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const col = db.collection("igrejas").doc(tenantId).collection("membros");
    const byId = new Map();
    const absorb = (doc) => {
        if (byId.has(doc.id))
            return;
        const d = doc.data();
        if (!memberCanSign(d))
            return;
        const nome = String(d.NOME_COMPLETO ?? d.nome ?? "").trim();
        if (!nome)
            return;
        const url = String(d.assinaturaUrl ?? d.assinatura_url ?? "").trim();
        byId.set(doc.id, {
            memberId: doc.id,
            nome,
            cargo: cargoLabel(d),
            assinaturaUrl: url || null,
        });
    };
    await Promise.all(ROLE_KEYS.map(async (role) => {
        try {
            const snap = await col.where("FUNCOES", "array-contains", role).limit(30).get();
            snap.docs.forEach(absorb);
        }
        catch (_) {
            /* índice pode faltar */
        }
    }));
    try {
        const flagged = await col.where("certificadoSignatario", "==", true).limit(40).get();
        flagged.docs.forEach(absorb);
    }
    catch (_) { }
    const items = Array.from(byId.values()).sort((a, b) => String(a.nome).localeCompare(String(b.nome), "pt-BR"));
    await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("config")
        .doc("carteira_signatories")
        .set({
        items,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "cloud_function",
    }, { merge: true });
    return { ok: true, count: items.length, items };
});
//# sourceMappingURL=carteiraSignatoriesIndex.js.map