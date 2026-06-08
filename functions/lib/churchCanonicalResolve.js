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
exports.resolveCanonicalChurchDocId = resolveCanonicalChurchDocId;
const admin = __importStar(require("firebase-admin"));
const churchClusterAnchors_1 = require("./churchClusterAnchors");
function db() {
    return admin.firestore();
}
/** Doc canónico: `church_aliases` → campos do doc raiz → cluster ancorado. */
async function resolveCanonicalChurchDocId(seed) {
    const raw = String(seed || "").trim();
    if (!raw)
        return raw;
    try {
        const aliasSnap = await db().collection("church_aliases").doc(raw).get();
        if (aliasSnap.exists) {
            const fromAlias = String(aliasSnap.data()?.canonicalId || "").trim();
            if (fromAlias)
                return (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(fromAlias);
        }
    }
    catch {
        /* ignore */
    }
    try {
        const doc = await db().collection("igrejas").doc(raw).get();
        if (doc.exists) {
            const d = doc.data() || {};
            for (const k of ["canonicalTenantId", "igrejaId", "churchId", "tenantId"]) {
                const v = String(d[k] || "").trim();
                if (v)
                    return (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(v);
            }
        }
    }
    catch {
        /* ignore */
    }
    return (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(raw);
}
//# sourceMappingURL=churchCanonicalResolve.js.map