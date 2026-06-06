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
exports.purgeAnonymousAuthUsers = void 0;
exports.isAnonymousOnlyAuthUser = isAnonymousOnlyAuthUser;
exports.purgeAnonymousAuthUsersCore = purgeAnonymousAuthUsersCore;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const masterPlatformAuth_1 = require("./masterPlatformAuth");
/** Provedores válidos — nunca apagar quem tem um destes. */
const VALID_PROVIDER_IDS = new Set([
    "password",
    "google.com",
    "apple.com",
    "phone",
]);
/** Utilizador só anónimo (Auth): sem e-mail/telefone e sem provedor real. */
function isAnonymousOnlyAuthUser(user) {
    const email = String(user.email ?? "").trim();
    if (email.length > 0)
        return false;
    const phone = String(user.phoneNumber ?? "").trim();
    if (phone.length > 0)
        return false;
    const providers = user.providerData ?? [];
    if (providers.length === 0)
        return true;
    return !providers.some((p) => VALID_PROVIDER_IDS.has(String(p.providerId ?? "").trim()));
}
async function deleteFirestoreUserDocIfOrphan(uid, dryRun) {
    const ref = admin.firestore().collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists)
        return false;
    const data = snap.data() ?? {};
    const docEmail = String(data.email ?? "").trim();
    const cpf = String(data.cpf ?? "").replace(/\D/g, "");
    const role = String(data.role ?? "").trim().toUpperCase();
    if (docEmail.length > 0 || cpf.length >= 11)
        return false;
    if (role === "MASTER" ||
        role === "ADM" ||
        role === "ADMIN" ||
        role === "GESTOR") {
        return false;
    }
    if (!dryRun) {
        await ref.delete();
    }
    return true;
}
/**
 * Remove todos os utilizadores Firebase Auth **somente anónimos**.
 * Mantém Gmail, Apple, e-mail/senha e telefone.
 */
async function purgeAnonymousAuthUsersCore(options) {
    const dryRun = options?.dryRun === true;
    const maxDelete = typeof options?.maxDelete === "number" && options.maxDelete > 0
        ? Math.min(options.maxDelete, 5000)
        : 5000;
    const result = {
        scanned: 0,
        deleted: 0,
        skipped: 0,
        firestoreUsersDeleted: 0,
        errors: [],
        dryRun,
    };
    let pageToken;
    const pendingDelete = [];
    const deletedUids = [];
    const flushDeletes = async () => {
        while (pendingDelete.length > 0 && result.deleted < maxDelete) {
            const chunk = pendingDelete.splice(0, Math.min(1000, maxDelete - result.deleted));
            if (chunk.length === 0)
                break;
            if (dryRun) {
                result.deleted += chunk.length;
                deletedUids.push(...chunk);
                continue;
            }
            try {
                const del = await admin.auth().deleteUsers(chunk);
                result.deleted += del.successCount;
                deletedUids.push(...chunk.slice(0, del.successCount));
                for (const e of del.errors) {
                    result.errors.push(`${e.index}: ${e.error.message}`);
                }
            }
            catch (e) {
                result.errors.push(e instanceof Error ? e.message : String(e));
            }
        }
    };
    do {
        const page = await admin.auth().listUsers(1000, pageToken);
        for (const user of page.users) {
            if (result.deleted + pendingDelete.length >= maxDelete)
                break;
            result.scanned += 1;
            if (!isAnonymousOnlyAuthUser(user)) {
                result.skipped += 1;
                continue;
            }
            pendingDelete.push(user.uid);
            if (pendingDelete.length >= 1000) {
                await flushDeletes();
            }
        }
        if (result.deleted + pendingDelete.length >= maxDelete) {
            pageToken = undefined;
        }
        else {
            pageToken = page.pageToken;
        }
    } while (pageToken);
    await flushDeletes();
    for (const uid of deletedUids) {
        try {
            const removed = await deleteFirestoreUserDocIfOrphan(uid, dryRun);
            if (removed)
                result.firestoreUsersDeleted += 1;
        }
        catch (e) {
            result.errors.push(`users/${uid}: ${e instanceof Error ? e.message : String(e)}`);
        }
    }
    return result;
}
/**
 * Callable — só operador master (Console / painel).
 * `dryRun: true` — conta sem apagar.
 */
exports.purgeAnonymousAuthUsers = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login como master.");
    }
    const token = context.auth.token;
    if (!(0, masterPlatformAuth_1.isPlatformOperatorToken)(token)) {
        throw new functions.https.HttpsError("permission-denied", "Só o operador master pode limpar utilizadores anónimos.");
    }
    const dryRun = data?.dryRun === true;
    const maxDelete = typeof data?.maxDelete === "number" ? data.maxDelete : undefined;
    const result = await purgeAnonymousAuthUsersCore({ dryRun, maxDelete });
    functions.logger.info("purgeAnonymousAuthUsers", result);
    return result;
});
//# sourceMappingURL=purgeAnonymousAuthUsers.js.map