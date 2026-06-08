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
exports.migrateMembersSubcollectionToMembros = migrateMembersSubcollectionToMembros;
exports.runChurchTenantConsolidation = runChurchTenantConsolidation;
/**
 * Padroniza cada igreja: tudo em `igrejas/{canonicalId}/…` (membros, finance, chats, etc.).
 * Idempotente — igrejas existentes e novas.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const churchTenantProvisioning_1 = require("./churchTenantProvisioning");
const syncChurchClusterData_1 = require("./syncChurchClusterData");
const churchCanonicalResolve_1 = require("./churchCanonicalResolve");
function db() {
    return admin.firestore();
}
/** Copia `igrejas/{id}/members` → `igrejas/{canonical}/membros` (merge). */
async function migrateMembersSubcollectionToMembros(igrejaId) {
    const canonical = await (0, churchCanonicalResolve_1.resolveCanonicalChurchDocId)(igrejaId);
    const target = canonical || igrejaId;
    const churchRef = db().collection("igrejas").doc(target);
    const probe = await churchRef.collection("members").limit(1).get();
    if (probe.empty)
        return 0;
    const FieldPath = admin.firestore.FieldPath;
    let total = 0;
    let last;
    for (;;) {
        let q = churchRef.collection("members").orderBy(FieldPath.documentId()).limit(400);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        const batch = db().batch();
        for (const d of snap.docs) {
            batch.set(churchRef.collection("membros").doc(d.id), d.data() || {}, { merge: true });
            total++;
        }
        await batch.commit();
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < 400)
            break;
    }
    return total;
}
/** Uma chamada: aliases + doc raiz + subcoleções no canónico + members→membros. */
async function runChurchTenantConsolidation(tenantId, options) {
    const seed = String(tenantId || "").trim();
    if (!seed) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const canonical = await (0, churchCanonicalResolve_1.resolveCanonicalChurchDocId)(seed);
    const source = String(options?.source || "runChurchTenantConsolidation");
    const provision = await (0, churchTenantProvisioning_1.provisionChurchTenant)(canonical, {
        source: `${source}:provision`,
    });
    let clusterSync = { skipped: true };
    try {
        clusterSync = await (0, syncChurchClusterData_1.runSyncChurchClusterDataFromRichest)(canonical, {
            force: options?.forceCluster === true,
        });
    }
    catch (e) {
        clusterSync = {
            ok: false,
            error: e instanceof Error ? e.message : String(e),
        };
    }
    const membersMigrated = await migrateMembersSubcollectionToMembros(canonical);
    return {
        ok: true,
        tenantId: seed,
        canonicalId: canonical,
        provision: provision,
        clusterSync,
        membersMigrated,
        source,
    };
}
//# sourceMappingURL=churchTenantConsolidation.js.map