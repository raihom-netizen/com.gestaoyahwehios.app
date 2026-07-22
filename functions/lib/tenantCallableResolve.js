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
exports.resolveTenantIdForCallable = resolveTenantIdForCallable;
exports.userCanAccessTenant = userCanAccessTenant;
const functions = __importStar(require("firebase-functions/v1"));
const adminDb_1 = require("./adminDb");
/** Resolve igreja do utilizador (claims → body → users → membros). Mobile costuma falhar só com claims. */
async function resolveTenantIdForCallable(auth, dataTenantId) {
    const uid = auth.uid;
    const email = String(auth.token?.email || "")
        .trim()
        .toLowerCase();
    const fromBody = String(dataTenantId || "").trim();
    if (fromBody && (await userCanAccessTenant(uid, email, fromBody))) {
        const ig = await (0, adminDb_1.fs)().collection("igrejas").doc(fromBody).get();
        if (ig.exists)
            return fromBody;
    }
    try {
        const tokenUser = await adminDb_1.admin.auth().getUser(uid);
        const claims = (tokenUser.customClaims || {});
        const fromClaims = String(claims.igrejaId || claims.tenantId || "").trim();
        if (fromClaims) {
            const ig = await (0, adminDb_1.fs)().collection("igrejas").doc(fromClaims).get();
            if (ig.exists)
                return fromClaims;
        }
    }
    catch (e) {
        functions.logger.warn("resolveTenantIdForCallable: claims", { uid, e });
    }
    const userSnap = await (0, adminDb_1.fs)().collection("users").doc(uid).get();
    if (userSnap.exists) {
        const d = userSnap.data() || {};
        const tid = String(d.igrejaId || d.tenantId || "").trim();
        if (tid) {
            const ig = await (0, adminDb_1.fs)().collection("igrejas").doc(tid).get();
            if (ig.exists)
                return tid;
        }
    }
    try {
        const membrosCg = await (0, adminDb_1.fs)()
            .collectionGroup("membros")
            .where("authUid", "==", uid)
            .limit(8)
            .get();
        for (const doc of membrosCg.docs) {
            const parts = doc.ref.path.split("/");
            if (parts[0] !== "igrejas" || parts[2] !== "membros")
                continue;
            const tid = parts[1];
            const ig = await (0, adminDb_1.fs)().collection("igrejas").doc(tid).get();
            if (ig.exists)
                return tid;
        }
    }
    catch (e) {
        // Índice CG em falta não pode derrubar o resolve (usa fallback por e-mail abaixo).
        functions.logger.warn("resolveTenantIdForCallable: membros CG", { uid, e });
    }
    if (email) {
        for (const field of ["email", "gestorEmail", "emailGestor"]) {
            const q = await (0, adminDb_1.fs)()
                .collection("igrejas")
                .where(field, "==", email)
                .limit(1)
                .get();
            if (!q.empty)
                return q.docs[0].id;
        }
    }
    return "";
}
async function userCanAccessTenant(uid, email, tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return false;
    const ig = await (0, adminDb_1.fs)().collection("igrejas").doc(tid).get();
    if (!ig.exists)
        return false;
    const byUid = await (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(tid)
        .collection("membros")
        .doc(uid)
        .get();
    if (byUid.exists)
        return true;
    const tenantUser = await (0, adminDb_1.fs)()
        .collection("igrejas")
        .doc(tid)
        .collection("users")
        .doc(uid)
        .get();
    if (tenantUser.exists)
        return true;
    const rootUser = await (0, adminDb_1.fs)().collection("users").doc(uid).get();
    if (rootUser.exists) {
        const d = rootUser.data() || {};
        if (String(d.igrejaId || d.tenantId || "").trim() === tid)
            return true;
    }
    try {
        const cg = await (0, adminDb_1.fs)()
            .collectionGroup("membros")
            .where("authUid", "==", uid)
            .limit(4)
            .get();
        for (const doc of cg.docs) {
            if (doc.ref.path.startsWith(`igrejas/${tid}/membros/`))
                return true;
        }
    }
    catch (e) {
        functions.logger.warn("userCanAccessTenant: membros CG", { uid, e });
    }
    if (email) {
        const data = ig.data() || {};
        const em = email.toLowerCase();
        if (String(data.email || "").toLowerCase() === em)
            return true;
        if (String(data.gestorEmail || "").toLowerCase() === em)
            return true;
    }
    return false;
}
//# sourceMappingURL=tenantCallableResolve.js.map