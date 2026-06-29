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
exports.gyPublicSignupStatus = exports.gyPublicMemberSignup = exports.gyAdminDeleteFeedPosts = exports.gyAdminUpsertChurchRoot = exports.gyAdminUpsertFeedPost = exports.gyUploadFinanceComprovante = void 0;
/**
 * Cloud Functions — anexos padronizados (WISDOMAPP → GESTAOYAHWEH).
 * Web instável: Admin SDK grava Storage + Firestore sem conflito com snapshots().
 */
const functions = __importStar(require("firebase-functions/v1"));
const adminDb_1 = require("./adminDb");
const tenantCallableResolve_1 = require("./tenantCallableResolve");
const panelPublicSiteCache_1 = require("./panelPublicSiteCache");
const CF_DELETE = "__DELETE__";
const MAX_FINANCE_BYTES = 15 * 1024 * 1024;
const ALLOWED_FEED_COLLECTIONS = new Set([
    "avisos",
    "eventos",
    "patrimonio",
    "finance",
    "membros",
    "fornecedor_compromissos",
    "chats",
]);
function resolveTenantDocRef(churchId, collection, docId, subCollection, subDocId) {
    let ref = (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(churchId)
        .collection(collection)
        .doc(docId);
    const subCol = (subCollection || "").trim();
    const subId = (subDocId || "").trim();
    if (subCol && subId) {
        ref = ref.collection(subCol).doc(subId);
    }
    return ref;
}
function decodeAdminFirestoreValue(value) {
    if (value === CF_DELETE) {
        return adminDb_1.admin.firestore.FieldValue.delete();
    }
    if (value && typeof value === "object" && !Array.isArray(value)) {
        const o = value;
        if (typeof o._tsMs === "number" && Number.isFinite(o._tsMs)) {
            return adminDb_1.admin.firestore.Timestamp.fromMillis(o._tsMs);
        }
        const out = {};
        for (const [k, v] of Object.entries(o)) {
            out[k] = decodeAdminFirestoreValue(v);
        }
        return out;
    }
    if (Array.isArray(value)) {
        return value.map(decodeAdminFirestoreValue);
    }
    return value;
}
function decodeAdminFirestoreMap(raw) {
    const out = {};
    for (const [k, v] of Object.entries(raw || {})) {
        out[k] = decodeAdminFirestoreValue(v);
    }
    return out;
}
async function requireChurchAccess(context, churchId) {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const uid = context.auth.uid;
    const email = String(context.auth.token?.email || "")
        .trim()
        .toLowerCase();
    const tid = String(churchId || "").trim();
    if (!tid) {
        throw new functions.https.HttpsError("invalid-argument", "churchId ausente.");
    }
    const resolved = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid, token: context.auth.token }, tid);
    if (!resolved || resolved !== tid) {
        throw new functions.https.HttpsError("permission-denied", "Sem acesso a esta igreja.");
    }
    const ok = await (0, tenantCallableResolve_1.userCanAccessTenant)(uid, email, tid);
    if (!ok) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão nesta igreja.");
    }
    return { uid, email, churchId: tid };
}
function extFromMime(mimeType, fileName) {
    const m = String(mimeType || "").toLowerCase();
    if (m.includes("pdf"))
        return "pdf";
    if (m.includes("png"))
        return "png";
    if (m.includes("webp"))
        return "webp";
    const fn = String(fileName || "").toLowerCase();
    if (fn.endsWith(".pdf"))
        return "pdf";
    if (fn.endsWith(".png"))
        return "png";
    if (fn.endsWith(".webp"))
        return "webp";
    return "jpg";
}
function financeComprovantePath(churchId, lancamentoId, referenceDate, ext = "jpg") {
    let ym = referenceDate?.trim() || "";
    if (!/^\d{4}_\d{2}$/.test(ym)) {
        const now = new Date();
        const y = now.getFullYear();
        const mo = String(now.getMonth() + 1).padStart(2, "0");
        ym = `${y}_${mo}`;
    }
    const safeExt = ext.replace(/[^a-z0-9]/gi, "").slice(0, 8) || "jpg";
    return `igrejas/${churchId}/financeiro/${ym}/${lancamentoId}.${safeExt}`;
}
/**
 * Web: base64 → Storage → merge Firestore comprovante* no lançamento finance/.
 * Espelho WISDOMAPP ctUploadReceiptToStorage.
 */
exports.gyUploadFinanceComprovante = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    const body = (data || {});
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const lancamentoId = String(body.lancamentoId || body.docId || "").trim();
    const base64 = String(body.base64 || body.dataBase64 || "").trim();
    const mimeType = String(body.mimeType || "image/jpeg").trim();
    const fileName = String(body.fileName || "comprovante").trim();
    const auth = await requireChurchAccess(context, churchId);
    if (!lancamentoId) {
        throw new functions.https.HttpsError("invalid-argument", "lancamentoId ausente.");
    }
    if (!base64) {
        throw new functions.https.HttpsError("invalid-argument", "base64 ausente.");
    }
    let buffer;
    try {
        buffer = Buffer.from(base64, "base64");
    }
    catch {
        throw new functions.https.HttpsError("invalid-argument", "base64 inválido.");
    }
    if (buffer.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Arquivo vazio.");
    }
    if (buffer.length > MAX_FINANCE_BYTES) {
        throw new functions.https.HttpsError("invalid-argument", `Arquivo grande demais (máx ${MAX_FINANCE_BYTES / (1024 * 1024)} MB).`);
    }
    if (mimeType.toLowerCase().startsWith("video/")) {
        throw new functions.https.HttpsError("invalid-argument", "Vídeo não permitido.");
    }
    const ext = extFromMime(mimeType, fileName);
    const refDate = String(body.referenceYearMonth || body.yearMonth || "").trim();
    const storagePath = financeComprovantePath(auth.churchId, lancamentoId, refDate || undefined, ext);
    const contentType = ext === "pdf"
        ? "application/pdf"
        : ext === "png"
            ? "image/png"
            : ext === "webp"
                ? "image/webp"
                : "image/jpeg";
    const bucket = (0, adminDb_1.storageBucket)();
    const file = bucket.file(storagePath);
    await file.save(buffer, {
        metadata: {
            contentType,
            cacheControl: "public, max-age=31536000",
        },
        resumable: false,
    });
    await file.makePublic().catch(() => undefined);
    const [metadata] = await file.getMetadata();
    if (!metadata?.name) {
        throw new functions.https.HttpsError("internal", "Falha ao confirmar upload Storage.");
    }
    const [downloadUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    const docRef = (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(auth.churchId)
        .collection("finance")
        .doc(lancamentoId);
    const patch = {
        comprovanteUrl: downloadUrl,
        comprovanteLink: downloadUrl,
        comprovanteStoragePath: storagePath,
        comprovanteMimeType: contentType,
        comprovanteFileName: fileName || `comprovante.${ext}`,
        hasComprovante: true,
        comprovanteUploadState: "published",
        comprovanteUploadError: adminDb_1.admin.firestore.FieldValue.delete(),
        comprovanteUpdatedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: adminDb_1.admin.firestore.FieldValue.serverTimestamp(),
    };
    await docRef.set(patch, { merge: true });
    return {
        ok: true,
        comprovanteUrl: downloadUrl,
        storagePath,
        mimeType: contentType,
        fileName: patch.comprovanteFileName,
    };
});
/**
 * Web: upsert documento de feed/patrimônio/finance via Admin SDK.
 * Espelho WISDOMAPP ctAdminUpsertCourseVideo.
 */
exports.gyAdminUpsertFeedPost = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    const body = (data || {});
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const collection = String(body.collection || body.subcollection || "").trim();
    const docId = String(body.docId || body.id || "").trim();
    const subCollection = String(body.subCollection || body.subcollectionPath || "").trim();
    const subDocId = String(body.subDocId || body.subId || "").trim();
    const rawData = (body.data || {});
    const create = body.create === true;
    const merge = body.merge !== false;
    const useUpdate = body.useUpdate === true;
    const auth = await requireChurchAccess(context, churchId);
    if (!ALLOWED_FEED_COLLECTIONS.has(collection)) {
        throw new functions.https.HttpsError("invalid-argument", `collection inválida: ${collection}`);
    }
    if (!docId) {
        throw new functions.https.HttpsError("invalid-argument", "docId ausente.");
    }
    if (subCollection && !subDocId) {
        throw new functions.https.HttpsError("invalid-argument", "subDocId ausente.");
    }
    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = adminDb_1.admin.firestore.FieldValue.serverTimestamp();
    if (create && !useUpdate) {
        decoded.createdAt = adminDb_1.admin.firestore.FieldValue.serverTimestamp();
    }
    const docRef = resolveTenantDocRef(auth.churchId, collection, docId, subCollection || undefined, subDocId || undefined);
    if (useUpdate) {
        await docRef.update(decoded);
    }
    else if (create && !merge) {
        await docRef.set(decoded);
    }
    else {
        await docRef.set(decoded, { merge: true });
    }
    return {
        ok: true,
        docId: subDocId || docId,
        path: docRef.path,
    };
});
/**
 * Web: merge doc raiz `igrejas/{churchId}` via Admin SDK.
 * Espelho WISDOMAPP — evita INTERNAL ASSERTION no Firestore JS ao gravar cadastro.
 */
exports.gyAdminUpsertChurchRoot = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    const body = (data || {});
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const rawData = (body.data || {});
    const merge = body.merge !== false;
    const auth = await requireChurchAccess(context, churchId);
    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = adminDb_1.admin.firestore.FieldValue.serverTimestamp();
    const docRef = (0, adminDb_1.fs)().collection("igrejas").doc(auth.churchId);
    if (merge) {
        await docRef.set(decoded, { merge: true });
    }
    else {
        await docRef.set(decoded);
    }
    return { ok: true, path: docRef.path };
});
/** Exclusão em lote de posts aviso/evento (admin). */
exports.gyAdminDeleteFeedPosts = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const body = (data || {});
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const collection = String(body.collection || "avisos").trim();
    const docIds = Array.isArray(body.docIds)
        ? body.docIds.map((id) => String(id || "").trim()).filter(Boolean)
        : [];
    const auth = await requireChurchAccess(context, churchId);
    if (!["avisos", "eventos"].includes(collection)) {
        throw new functions.https.HttpsError("invalid-argument", "collection deve ser avisos ou eventos.");
    }
    if (docIds.length === 0) {
        return { ok: true, deleted: 0 };
    }
    if (docIds.length > 32) {
        throw new functions.https.HttpsError("invalid-argument", "Máximo 32 docs por chamada.");
    }
    const batch = (0, adminDb_1.fs)().batch();
    for (const id of docIds) {
        const ref = (0, adminDb_1.fs)()
            .collection("igrejas")
            .doc(auth.churchId)
            .collection(collection)
            .doc(id);
        batch.delete(ref);
    }
    await batch.commit();
    return { ok: true, deleted: docIds.length };
});
/**
 * Cadastro membro público — Admin SDK (Web-safe, Fase 3 doc mestre).
 * Auth opcional; valida slug/churchId e grava draft em igrejas/{id}/membros.
 */
exports.gyPublicMemberSignup = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    const body = (data || {});
    const churchId = String(body.churchId || body.tenantId || "").trim();
    const docId = String(body.docId || body.memberId || "").trim();
    const rawData = (body.data || {});
    if (!churchId) {
        throw new functions.https.HttpsError("invalid-argument", "churchId ausente.");
    }
    if (!docId) {
        throw new functions.https.HttpsError("invalid-argument", "docId ausente.");
    }
    const churchSnap = await (0, adminDb_1.fs)().collection("igrejas").doc(churchId).get();
    if (!churchSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const decoded = decodeAdminFirestoreMap(rawData);
    decoded.updatedAt = adminDb_1.admin.firestore.FieldValue.serverTimestamp();
    decoded.createdAt = adminDb_1.admin.firestore.FieldValue.serverTimestamp();
    decoded.status = decoded.status || "pendente_aprovacao";
    decoded.publicSignup = true;
    if (context.auth?.uid) {
        decoded.authUid = context.auth.uid;
    }
    const docRef = (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(churchId)
        .collection("membros")
        .doc(docId);
    await docRef.set(decoded, { merge: true });
    return { ok: true, docId, path: docRef.path };
});
function pickPublicString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (v != null && String(v).trim())
            return String(v).trim();
    }
    return "";
}
/** Status de cadastro público — visitante anónimo (sem leitura directa de `membros`). */
exports.gyPublicSignupStatus = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data) => {
    const body = (data || {});
    const protocolo = String(body.protocolo || body.docId || "").trim();
    if (!protocolo) {
        throw new functions.https.HttpsError("invalid-argument", "protocolo ausente.");
    }
    const churchId = await (0, panelPublicSiteCache_1.resolvePublicChurchIdFromInput)(body.churchId ?? body.tenantId ?? body.slug);
    if (!churchId) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const churchSnap = await (0, adminDb_1.fs)().collection("igrejas").doc(churchId).get();
    if (!churchSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const church = (churchSnap.data() ?? {});
    const churchName = pickPublicString(church, ["nome", "name", "NOME_IGREJA", "nomeIgreja"]) ||
        "Igreja";
    const membros = (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(churchId)
        .collection("membros");
    let memberSnap = await membros.doc(protocolo).get();
    if (!memberSnap.exists) {
        const legacy = await membros
            .where("legacyMemberDocId", "==", protocolo)
            .limit(1)
            .get();
        if (!legacy.empty)
            memberSnap = legacy.docs[0];
    }
    if (!memberSnap.exists) {
        return {
            ok: false,
            found: false,
            churchId,
            churchName,
            error: "Cadastro não localizado para o protocolo informado.",
        };
    }
    const member = (memberSnap.data() ?? {});
    if (member.publicSignup !== true) {
        return {
            ok: false,
            found: false,
            churchId,
            churchName,
            error: "Protocolo inválido para acompanhamento público.",
        };
    }
    const nome = pickPublicString(member, ["NOME_COMPLETO", "nome", "name"]) || "Membro";
    const status = String(member.status ?? member.STATUS ?? "pendente").trim();
    return {
        ok: true,
        found: true,
        churchId,
        churchName,
        protocolo: memberSnap.id,
        nome,
        status,
    };
});
//# sourceMappingURL=gyMediaAttachments.js.map