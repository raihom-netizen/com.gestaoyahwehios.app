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
exports.masterApplyTenantLicense = void 0;
exports.applyMasterTenantLicenseCore = applyMasterTenantLicenseCore;
/**
 * Licença/plano igreja — painel Master (Admin SDK).
 * Evita INTERNAL ASSERTION do Firestore Web ao gravar FieldValue.delete em maps aninhados.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const masterChurchesListCache_1 = require("./masterChurchesListCache");
const db = admin.firestore();
const GRACE_DAYS = 3;
/** Campos que mantêm a igreja bloqueada além de `adminBlocked`. */
function unblockExtraFieldsPatch() {
    return {
        masterInactive: admin.firestore.FieldValue.delete(),
        siteDisabled: admin.firestore.FieldValue.delete(),
        ativa: true,
        status: "ativa",
        status_assinatura: "active",
    };
}
function isMasterRole(role) {
    const r = (role || "").toUpperCase();
    return r === "MASTER" || r === "ADMIN" || r === "ADM";
}
function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
async function syncSubscriptionsBlockFlag(tenantId, blocked) {
    const snap = await db
        .collection("subscriptions")
        .where("igrejaId", "==", tenantId)
        .limit(8)
        .get();
    const batch = db.batch();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    for (const doc of snap.docs) {
        batch.set(doc.ref, { adminBlocked: blocked, updatedAt: ts }, { merge: true });
    }
    if (!snap.empty)
        await batch.commit();
}
async function syncSubscriptionsForFree(tenantId, adminBlocked) {
    const snap = await db
        .collection("subscriptions")
        .where("igrejaId", "==", tenantId)
        .limit(8)
        .get();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        status: "ACTIVE",
        status_assinatura: "active",
        planId: "free",
        plano: "free",
        isFree: true,
        adminBlocked,
        updatedAt: ts,
    };
    if (snap.empty) {
        await db.collection("subscriptions").add({
            ...payload,
            igrejaId: tenantId,
            createdAt: ts,
        });
        return;
    }
    const batch = db.batch();
    for (const doc of snap.docs) {
        batch.set(doc.ref, payload, { merge: true });
    }
    await batch.commit();
}
async function syncSubscriptionsForPaid(tenantId, planId, expiresAt, billingCycle, adminBlocked) {
    const snap = await db
        .collection("subscriptions")
        .where("igrejaId", "==", tenantId)
        .limit(8)
        .get();
    const ts = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
        status: "ACTIVE",
        status_assinatura: "active",
        planId,
        plano: planId,
        isFree: false,
        adminBlocked,
        billingCycle,
        data_vencimento: expiresAt,
        nextChargeAt: expiresAt,
        currentPeriodEnd: expiresAt,
        updatedAt: ts,
    };
    if (snap.empty) {
        await db.collection("subscriptions").add({
            ...payload,
            igrejaId: tenantId,
            createdAt: ts,
        });
        return;
    }
    const batch = db.batch();
    for (const doc of snap.docs) {
        batch.set(doc.ref, payload, { merge: true });
    }
    await batch.commit();
}
async function applyMasterTenantLicenseCore(params) {
    const tenantId = String(params.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const ref = db.collection("igrejas").doc(tenantId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const existing = snap.data() || {};
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (params.touchBlockOnly || params.isFreeMode === null) {
        const lic = {
            ...(existing.license ?? {}),
        };
        lic.adminBlocked = params.adminBlocked;
        if (!params.adminBlocked) {
            lic.active = true;
            lic.status = "active";
        }
        lic.updatedAt = now;
        const patch = {
            adminBlocked: params.adminBlocked,
            license: lic,
            updatedAt: now,
        };
        if (!params.adminBlocked) {
            Object.assign(patch, unblockExtraFieldsPatch());
        }
        await ref.set(patch, { merge: true });
        await syncSubscriptionsBlockFlag(tenantId, params.adminBlocked);
        await (0, masterChurchesListCache_1.patchMasterChurchesIndexForTenant)(tenantId);
        return;
    }
    if (params.isFreeMode) {
        await ref.set({
            plano: "free",
            planId: "free",
            isFree: true,
            adminBlocked: params.adminBlocked,
            status: "ativa",
            ativa: true,
            status_assinatura: "active",
            data_bloqueio: admin.firestore.FieldValue.delete(),
            data_vencimento: admin.firestore.FieldValue.delete(),
            expiresAt: admin.firestore.FieldValue.delete(),
            masterInactive: admin.firestore.FieldValue.delete(),
            siteDisabled: admin.firestore.FieldValue.delete(),
            licenseExpiresAt: admin.firestore.FieldValue.delete(),
            trialEndsAt: admin.firestore.FieldValue.delete(),
            removedByAdminAt: admin.firestore.FieldValue.delete(),
            license: {
                isFree: true,
                active: true,
                status: "active",
                adminBlocked: params.adminBlocked,
                expiresAt: admin.firestore.FieldValue.delete(),
                updatedAt: now,
            },
            billing: {
                status: "paid",
                provider: "master_manual",
                updatedAt: now,
            },
            updatedAt: now,
        }, { merge: true });
        await syncSubscriptionsForFree(tenantId, params.adminBlocked);
        await (0, masterChurchesListCache_1.patchMasterChurchesIndexForTenant)(tenantId);
        return;
    }
    const normalizedPlan = String(params.planId || "")
        .trim()
        .toLowerCase();
    if (!normalizedPlan || normalizedPlan === "free") {
        throw new functions.https.HttpsError("invalid-argument", "Selecione um plano pago válido.");
    }
    if (!params.licenseExpiresAt) {
        throw new functions.https.HttpsError("invalid-argument", "Informe a data de vencimento para planos pagos.");
    }
    const vencDay = startOfDay(params.licenseExpiresAt);
    const today = startOfDay(new Date());
    if (vencDay.getTime() < today.getTime()) {
        throw new functions.https.HttpsError("invalid-argument", "A data de vencimento não pode ser anterior a hoje.");
    }
    const cycleRaw = String(params.billingCycle || "monthly").toLowerCase();
    const billingCycle = cycleRaw === "annual" ? "annual" : "monthly";
    const ts = admin.firestore.Timestamp.fromDate(vencDay);
    const graceTs = admin.firestore.Timestamp.fromDate(new Date(vencDay.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000));
    await ref.set({
        plano: normalizedPlan,
        planId: normalizedPlan,
        isFree: false,
        adminBlocked: params.adminBlocked,
        status: "ativa",
        ativa: true,
        billingCycle,
        status_assinatura: "active",
        licenseExpiresAt: ts,
        expiresAt: ts,
        data_vencimento: ts,
        data_bloqueio: graceTs,
        removedByAdminAt: admin.firestore.FieldValue.delete(),
        masterInactive: admin.firestore.FieldValue.delete(),
        siteDisabled: admin.firestore.FieldValue.delete(),
        license: {
            isFree: false,
            active: true,
            status: "active",
            adminBlocked: params.adminBlocked,
            expiresAt: ts,
            updatedAt: now,
        },
        billing: {
            status: "paid",
            provider: "master_manual",
            currentPeriodEnd: ts,
            paidUntil: ts,
            nextChargeAt: ts,
            updatedAt: now,
        },
        updatedAt: now,
    }, { merge: true });
    await syncSubscriptionsForPaid(tenantId, normalizedPlan, ts, billingCycle, params.adminBlocked);
    await (0, masterChurchesListCache_1.patchMasterChurchesIndexForTenant)(tenantId);
}
/** Callable — painel Master: aplicar licença FREE, plano pago ou bloqueio. */
exports.masterApplyTenantLicense = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const role = String(context.auth.token?.role || "").toUpperCase();
    if (!isMasterRole(role)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao painel Master.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const touchBlockOnly = data?.touchBlockOnly === true;
    const adminBlocked = data?.adminBlocked === true;
    let isFreeMode = null;
    if (!touchBlockOnly && typeof data?.isFreeMode === "boolean") {
        isFreeMode = data.isFreeMode;
    }
    let licenseExpiresAt = null;
    const rawExp = data?.licenseExpiresAtMs;
    if (rawExp != null && rawExp !== "") {
        const ms = typeof rawExp === "number" ? rawExp : parseInt(String(rawExp), 10);
        if (!Number.isNaN(ms) && ms > 0) {
            licenseExpiresAt = new Date(ms);
        }
    }
    let planId = String(data?.planId || "").trim();
    if (planId === "premium")
        planId = "inicial";
    await applyMasterTenantLicenseCore({
        tenantId,
        isFreeMode,
        planId: planId || undefined,
        licenseExpiresAt,
        billingCycle: String(data?.billingCycle || "monthly"),
        adminBlocked,
        touchBlockOnly,
    });
    return { ok: true, tenantId };
});
//# sourceMappingURL=masterTenantLicense.js.map