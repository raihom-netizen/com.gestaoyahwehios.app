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
exports.scheduledSyncMembroSessions = exports.onMembroWriteSyncSession = void 0;
exports.syncSessionFromMembroDoc = syncSessionFromMembroDoc;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const memberAccessPolicy_1 = require("./memberAccessPolicy");
const db = admin.firestore();
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim())
            return v.trim();
    }
    return "";
}
function claimRoleFromRaw(raw, fallback) {
    const s = String(raw || "").trim();
    if (!s)
        return fallback;
    const low = s.toLowerCase();
    if (low === "membro")
        return "membro";
    if (low === "gestor")
        return "GESTOR";
    if (low === "adm" || low === "admin" || low === "administrador")
        return "ADM";
    return s.length <= 24 ? s.toUpperCase() : "membro";
}
function muralRoleFromMemberData(md) {
    const role = pickString(md, ["role", "FUNCAO", "funcao", "CARGO", "cargo"]);
    const low = role.toLowerCase();
    const gestorLike = low.includes("gestor") ||
        low.includes("admin") ||
        low.includes("pastor") ||
        low.includes("secret") ||
        low.includes("lider") ||
        low.includes("líder") ||
        low.includes("tesour") ||
        low.includes("evangel");
    if (gestorLike)
        return true;
    const perms = md.permissions ?? md.PERMISSIONS;
    if (Array.isArray(perms)) {
        for (const p of perms) {
            const k = String(p ?? "").trim();
            if (k === "eventos" ||
                k === "eventos_avisos_edicao" ||
                k === "mural_avisos_edicao") {
                return true;
            }
        }
    }
    return false;
}
/** Sincroniza custom claims + users/{uid} + users_profile_chat a partir de `membros/{id}`. */
async function syncSessionFromMembroDoc(tenantId, memberId, memberData) {
    const tid = String(tenantId || "").trim();
    const mid = String(memberId || "").trim();
    if (!tid || !mid)
        return { ok: false, skipped: "missing_ids" };
    const authUid = pickString(memberData, ["authUid", "firebaseUid", "uid", "userId"]);
    if (!authUid)
        return { ok: false, skipped: "no_authUid" };
    const ig = await db.collection("igrejas").doc(tid).get();
    if (!ig.exists)
        return { ok: false, skipped: "church_missing" };
    const pendingApproval = (0, memberAccessPolicy_1.memberDocIsPending)(memberData);
    const activeClaim = (0, memberAccessPolicy_1.memberDocIsActive)(memberData);
    const roleRaw = pickString(memberData, ["role", "FUNCAO", "funcao", "CARGO", "cargo"]) || "membro";
    const roleOut = claimRoleFromRaw(roleRaw, muralRoleFromMemberData(memberData) ? "GESTOR" : "membro");
    const cpf = String(memberData.CPF || memberData.cpf || "").replace(/\D/g, "");
    const nome = pickString(memberData, ["NOME_COMPLETO", "nome", "name"]);
    const email = pickString(memberData, ["EMAIL", "email"]).toLowerCase();
    const photoUrl = pickString(memberData, [
        "fotoThumbUrl",
        "photoThumbUrl",
        "fotoUrl",
        "FOTO_URL_OU_ID",
        "photoUrl",
        "photoURL",
    ]);
    const photoStoragePath = pickString(memberData, [
        "photoThumbStoragePath",
        "fotoThumbPath",
        "photoStoragePath",
        "fotoPath",
    ]);
    const photoRevRaw = memberData.fotoUrlCacheRevision;
    const photoRevision = typeof photoRevRaw === "number" && Number.isFinite(photoRevRaw)
        ? Math.floor(photoRevRaw)
        : 0;
    const authUser = await admin.auth().getUser(authUid);
    const cur = (authUser.customClaims || {});
    await admin.auth().setCustomUserClaims(authUid, {
        ...cur,
        role: roleOut,
        igrejaId: tid,
        tenantId: tid,
        active: activeClaim,
        isUser: true,
        isDriver: cur.isDriver === true,
        pendingApproval,
        ...(cpf.length === 11 ? { cpf, memberDocId: mid } : { memberDocId: mid }),
    });
    await db.collection("users").doc(authUid).set({
        uid: authUid,
        email: email || authUser.email || "",
        igrejaId: tid,
        tenantId: tid,
        role: roleOut,
        memberDocId: mid,
        cpf: cpf.length === 11 ? cpf : "",
        nome,
        displayName: nome,
        ...(photoUrl ? { fotoUrl: photoUrl, photoUrl } : {}),
        ...(photoStoragePath
            ? {
                photoStoragePath,
                photoThumbStoragePath: photoStoragePath,
            }
            : {}),
        ...(photoRevision > 0 ? { fotoUrlCacheRevision: photoRevision } : {}),
        ativo: activeClaim,
        active: activeClaim,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const deptIds = [];
    const rawIds = memberData.departamentosIds ?? memberData.DEPARTAMENTOS_IDS;
    if (Array.isArray(rawIds)) {
        for (const x of rawIds) {
            const s = String(x ?? "").trim();
            if (s)
                deptIds.push(s);
        }
    }
    await db
        .collection("igrejas")
        .doc(tid)
        .collection("users_profile_chat")
        .doc(authUid)
        .set({
        uid: authUid,
        departmentIds: [...new Set(deptIds)],
        memberDocId: mid,
        ...(photoUrl ? { photoUrl, fotoUrl: photoUrl } : {}),
        ...(photoStoragePath
            ? {
                photoStoragePath,
                photoThumbStoragePath: photoStoragePath,
            }
            : {}),
        ...(photoRevision > 0 ? { fotoUrlCacheRevision: photoRevision } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, uid: authUid };
}
exports.onMembroWriteSyncSession = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .firestore.document("igrejas/{tenantId}/membros/{memberId}")
    .onWrite(async (change, context) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after)
        return null;
    const tenantId = context.params.tenantId;
    const memberId = context.params.memberId;
    try {
        const r = await syncSessionFromMembroDoc(tenantId, memberId, after);
        if (r.ok) {
            functions.logger.info("membroSessionSync: ok", { tenantId, memberId, uid: r.uid });
        }
    }
    catch (e) {
        functions.logger.warn("membroSessionSync: falhou", { tenantId, memberId, e });
    }
    return null;
});
/** Repara claims + users_profile_chat em lote (apps nativos sem token igrejaId). */
exports.scheduledSyncMembroSessions = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .pubsub.schedule("every 6 hours")
    .onRun(async () => {
    const snap = await db.collectionGroup("membros").limit(100).get();
    let n = 0;
    for (const doc of snap.docs) {
        const parts = doc.ref.path.split("/");
        if (parts[0] !== "igrejas" || parts[2] !== "membros")
            continue;
        const tenantId = parts[1];
        const md = doc.data();
        const uid = pickString(md, ["authUid", "firebaseUid", "uid", "userId"]);
        if (!uid)
            continue;
        try {
            const user = await admin.auth().getUser(uid);
            const claims = (user.customClaims || {});
            const hasTenant = String(claims.igrejaId || claims.tenantId || "").trim() === tenantId;
            if (hasTenant)
                continue;
            await syncSessionFromMembroDoc(tenantId, doc.id, md);
            n++;
        }
        catch (e) {
            functions.logger.warn("scheduledSyncMembroSessions", { path: doc.ref.path, e });
        }
    }
    if (n > 0)
        functions.logger.info(`scheduledSyncMembroSessions: ${n} conta(s)`);
    return null;
});
//# sourceMappingURL=membroSessionSync.js.map