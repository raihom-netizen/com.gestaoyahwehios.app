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
exports.scheduledRefreshMasterChurchesList = exports.getMasterChurchesList = void 0;
exports.lightChurchRow = lightChurchRow;
exports.patchMasterChurchesIndexForTenant = patchMasterChurchesIndexForTenant;
exports.recomputeMasterChurchesIndex = recomputeMasterChurchesIndex;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const masterPlatformAuth_1 = require("./masterPlatformAuth");
const STALE_MS = 10 * 60 * 1000;
const LIST_LIMIT = 80;
const RECOMPUTE_MIN_MS = 45000;
function isMasterCaller(token) {
    return (0, masterPlatformAuth_1.isPlatformOperatorToken)(token);
}
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim())
            return v.trim();
    }
    return "";
}
function lightChurchRow(id, data) {
    const lic = data.license;
    let licenseExpiresAt = null;
    if (data.licenseExpiresAt instanceof admin.firestore.Timestamp) {
        licenseExpiresAt = data.licenseExpiresAt;
    }
    else if (lic && typeof lic === "object") {
        const l = lic;
        if (l.expiresAt instanceof admin.firestore.Timestamp) {
            licenseExpiresAt = l.expiresAt;
        }
    }
    return {
        id,
        nome: pickString(data, ["nome", "name"]) || id,
        slug: pickString(data, ["slug", "slugId", "alias"]),
        status: pickString(data, ["status"]) || "ativa",
        plano: pickString(data, ["plano", "planId", "plan"]),
        planId: pickString(data, ["planId", "plano"]),
        logoUrl: pickString(data, ["logoUrl", "logo_url", "logoProcessedUrl"]),
        institutionalVideoUrl: pickString(data, [
            "institutionalVideoUrl",
            "videoInstitucionalUrl",
            "videoUrl",
        ]),
        adminBlocked: data.adminBlocked === true,
        isFree: data.isFree === true ||
            pickString(data, ["plano", "planId"]).toLowerCase() === "free",
        dataVencimento: data.dataVencimento ??
            data.vencimento ??
            licenseExpiresAt ??
            null,
        licenseExpiresAt,
        createdAt: data.createdAt ??
            data.created_at ??
            data.dataCadastro ??
            null,
        gestorEmail: pickString(data, ["gestorEmail", "emailGestor", "email"]),
        whatsappIgreja: pickString(data, [
            "whatsappIgreja",
            "whatsapp",
            "telefone",
            "telefoneIgreja",
        ]),
        removedByAdminAt: data.removedByAdminAt ?? null,
        license: lic && typeof lic === "object" ? lic : null,
    };
}
/** Atualiza uma igreja no índice leve após alteração de licença/bloqueio. */
async function patchMasterChurchesIndexForTenant(tenantId, churchData) {
    const db = admin.firestore();
    const id = String(tenantId || "").trim();
    if (!id)
        return;
    let data = churchData;
    if (!data) {
        const snap = await db.collection("igrejas").doc(id).get();
        if (!snap.exists)
            return;
        data = snap.data();
    }
    const row = lightChurchRow(id, data);
    const indexRef = db.collection("config").doc("master_churches_index");
    const indexSnap = await indexRef.get();
    if (!indexSnap.exists) {
        await recomputeMasterChurchesIndex();
        return;
    }
    const raw = indexSnap.data() ?? {};
    const churches = Array.isArray(raw.churches)
        ? [...raw.churches]
        : [];
    const idx = churches.findIndex((c) => String(c.id) === id);
    if (idx >= 0) {
        churches[idx] = row;
    }
    else {
        churches.unshift(row);
    }
    await indexRef.set({
        churches,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        total: raw.total ?? churches.length,
        schemaVersion: raw.schemaVersion ?? 1,
    }, { merge: true });
}
/** Índice leve para Lista Igrejas — `config/master_churches_index`. */
async function recomputeMasterChurchesIndex() {
    const db = admin.firestore();
    const lockRef = db.collection("config").doc("_master_churches_list_lock");
    const indexRef = db.collection("config").doc("master_churches_index");
    const nowMs = Date.now();
    const lockSnap = await lockRef.get();
    if (lockSnap.exists) {
        const last = lockSnap.data()?.lastRun;
        if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_MS)
            return;
    }
    await lockRef.set({ lastRun: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    let docs = [];
    try {
        const ordered = await db
            .collection("igrejas")
            .orderBy("createdAt", "desc")
            .limit(LIST_LIMIT)
            .get();
        docs = ordered.docs;
    }
    catch (e) {
        functions.logger.warn("masterChurchesList: orderBy createdAt", { e });
        const plain = await db.collection("igrejas").limit(LIST_LIMIT).get();
        docs = plain.docs;
    }
    const churches = docs.map((d) => lightChurchRow(d.id, d.data()));
    let total = churches.length;
    try {
        const cnt = await db.collection("igrejas").count().get();
        total = cnt.data().count;
    }
    catch (_) { }
    await indexRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        schemaVersion: 1,
        total,
        churches,
    }, { merge: false });
}
exports.getMasterChurchesList = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = (context.auth.token || {});
    if (!isMasterCaller(token)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso apenas para administradores da plataforma");
    }
    const db = admin.firestore();
    const indexRef = db.collection("config").doc("master_churches_index");
    const snap = await indexRef.get();
    const updated = snap.data()?.updatedAt;
    const isStale = !snap.exists ||
        !updated ||
        Date.now() - updated.toMillis() > STALE_MS;
    if (isStale) {
        await recomputeMasterChurchesIndex();
    }
    const fresh = await indexRef.get();
    const data = fresh.data() ?? {};
    return {
        ok: true,
        total: data.total ?? 0,
        churches: data.churches ?? [],
        updatedAt: data.updatedAt ?? null,
    };
});
exports.scheduledRefreshMasterChurchesList = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "256MB" })
    .pubsub.schedule("every 60 minutes")
    .onRun(async () => {
    try {
        await recomputeMasterChurchesIndex();
        functions.logger.info("masterChurchesList: scheduled ok");
    }
    catch (e) {
        functions.logger.error("masterChurchesList: scheduled failed", { e });
    }
    return null;
});
//# sourceMappingURL=masterChurchesListCache.js.map