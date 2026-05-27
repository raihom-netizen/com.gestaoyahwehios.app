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
exports.backfillMemberCodigos = void 0;
exports.allocateCodigoMembro = allocateCodigoMembro;
exports.ensureCodigoMembroOnMember = ensureCodigoMembroOnMember;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const CONFIG_DOC = "codigo_membro";
const SEQ_PAD = 5;
function membersCol(tenantId) {
    return admin.firestore().collection("igrejas").doc(tenantId).collection("membros");
}
function configRef(tenantId) {
    return admin
        .firestore()
        .collection("igrejas")
        .doc(tenantId)
        .collection("config")
        .doc(CONFIG_DOC);
}
function readCodigoFromMember(data) {
    for (const k of ["codigoMembro", "COD_MEMBRO", "codigo_membro", "numeroMembro"]) {
        const v = String(data[k] ?? "").trim();
        if (v)
            return v;
    }
    return "";
}
async function isCodeTaken(tenantId, code) {
    const col = membersCol(tenantId);
    for (const field of ["codigoMembro", "COD_MEMBRO", "codigo_membro"]) {
        const snap = await col.where(field, "==", code).limit(1).get();
        if (!snap.empty)
            return true;
    }
    return false;
}
/** Próximo código sequencial da igreja (`AAAA` + `NNNNN`). */
async function allocateCodigoMembro(tenantId) {
    const tid = tenantId.trim();
    const db = admin.firestore();
    const cfgRef = configRef(tid);
    const yearNow = new Date().getFullYear();
    for (let attempt = 0; attempt < 8; attempt++) {
        const code = await db.runTransaction(async (tx) => {
            const snap = await tx.get(cfgRef);
            const data = snap.data() ?? {};
            let year = typeof data.year === "number" ? data.year : yearNow;
            let next = typeof data.nextSequence === "number" ? data.nextSequence : 1;
            if (year !== yearNow) {
                year = yearNow;
                next = 1;
            }
            const candidate = `${year}${String(next).padStart(SEQ_PAD, "0")}`;
            tx.set(cfgRef, {
                year,
                nextSequence: next + 1,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            return candidate;
        });
        if (!(await isCodeTaken(tid, code)))
            return code;
    }
    throw new Error("Não foi possível gerar código de membro único.");
}
/** Garante `codigoMembro` no documento (mantém existente salvo [forceNew]). */
async function ensureCodigoMembroOnMember(tenantId, memberId, memberData, forceNew = false) {
    const tid = tenantId.trim();
    const mid = memberId.trim();
    const ref = membersCol(tid).doc(mid);
    let data = memberData ?? {};
    if (!Object.keys(data).length) {
        const snap = await ref.get();
        data = (snap.data() ?? {});
    }
    if (!forceNew) {
        const existing = readCodigoFromMember(data);
        if (existing)
            return existing;
    }
    const code = await allocateCodigoMembro(tid);
    await ref.set({
        codigoMembro: code,
        COD_MEMBRO: code,
        codigo_membro: code,
        codigoMembroAtribuidoEm: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return code;
}
function isGestorCaller(role, tenantId, igrejaId) {
    const r = role.toUpperCase();
    return (["ADMIN", "ADM", "GESTOR", "MASTER"].includes(r) &&
        (String(igrejaId) === tenantId || r === "MASTER"));
}
/** Atribui códigos a membros sem `codigoMembro` (lote, por igreja). */
exports.backfillMemberCodigos = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId é obrigatório.");
    }
    const role = String(context.auth.token?.role || "");
    const igrejaId = String(context.auth.token?.igrejaId || context.auth.token?.tenantId || "");
    if (!isGestorCaller(role, tenantId, igrejaId)) {
        throw new functions.https.HttpsError("permission-denied", "Apenas gestor pode gerar códigos.");
    }
    const limit = Math.min(200, Math.max(10, Number(data?.limit) || 80));
    const snap = await membersCol(tenantId).limit(limit).get();
    let assigned = 0;
    let skipped = 0;
    let errors = 0;
    for (const doc of snap.docs) {
        if (readCodigoFromMember(doc.data())) {
            skipped++;
            continue;
        }
        try {
            await ensureCodigoMembroOnMember(tenantId, doc.id, doc.data());
            assigned++;
        }
        catch {
            errors++;
        }
    }
    return { ok: true, assigned, skipped, errors };
});
//# sourceMappingURL=memberCodigo.js.map