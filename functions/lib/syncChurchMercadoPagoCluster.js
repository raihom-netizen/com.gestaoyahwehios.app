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
exports.syncChurchMercadoPagoFromCluster = void 0;
exports.runSyncChurchMercadoPagoFromCluster = runSyncChurchMercadoPagoFromCluster;
/**
 * Sincroniza Mercado Pago (credenciais + config + conta tesouraria 323)
 * do doc irmão mais completo do cluster → doc operacional da igreja.
 *
 * Caso típico: credenciais em `igreja_o_brasil_...` e painel em `brasilparacristo_sistema`.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
function db() {
    return admin.firestore();
}
function isMpConta(data) {
    if (!data)
        return false;
    if (data.ativo === false)
        return false;
    const cod = String(data.bancoCodigo || "").trim();
    if (cod === "323")
        return true;
    const bn = String(data.bancoNome || "").toLowerCase();
    if (bn.includes("mercado pago"))
        return true;
    if (String(data.seedPreset || "") === "tesouraria_mercado_pago")
        return true;
    const nome = String(data.nome || "").toLowerCase();
    return nome.includes("mercado pago");
}
const ANCHORED_CLUSTERS = {
    brasilparacristo_sistema: [
        "brasilparacristo_sistema",
        "brasilparacristo",
        "igreja_o_brasil_para_cristo_jardim_goiano",
        "iobpc-jardim-goiano",
    ],
};
function addAnchoredCluster(seed, out) {
    const t = String(seed || "").trim();
    if (!t)
        return;
    for (const [key, members] of Object.entries(ANCHORED_CLUSTERS)) {
        if (key === t || members.includes(t)) {
            out.add(key);
            for (const m of members)
                out.add(m);
        }
    }
}
async function collectRelatedIgrejaDocIds(seed) {
    const ids = new Set();
    const add = (x) => {
        const t = String(x || "").trim();
        if (t)
            ids.add(t);
    };
    const raw = String(seed || "").trim();
    if (!raw)
        return [];
    add(raw);
    addAnchoredCluster(raw, ids);
    for (const suf of ["_sistema", "_bpc"]) {
        if (raw.endsWith(suf))
            add(raw.slice(0, -suf.length));
        else
            add(`${raw}${suf}`);
    }
    try {
        const doc = await db().collection("igrejas").doc(raw).get();
        if (doc.exists) {
            const d = doc.data() || {};
            for (const k of ["slug", "slugId", "alias", "churchId"]) {
                const v = String(d[k] || "").trim();
                if (v)
                    add(v);
            }
            for (const field of ["slug", "alias", "slugId"]) {
                const v = String(d[field] || "").trim();
                if (!v)
                    continue;
                try {
                    const q = await db().collection("igrejas").where(field, "==", v).limit(12).get();
                    for (const x of q.docs)
                        add(x.id);
                }
                catch {
                    /* índice opcional */
                }
            }
        }
    }
    catch {
        /* ignore */
    }
    for (const id of Array.from(ids))
        addAnchoredCluster(id, ids);
    return Array.from(ids);
}
async function scoreMpReadiness(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return 0;
    let score = 0;
    try {
        const priv = await db()
            .collection("igrejas")
            .doc(tid)
            .collection("private")
            .doc("mp_credentials")
            .get();
        if (priv.exists && String(priv.data()?.accessToken || "").trim())
            score += 100;
    }
    catch {
        /* ignore */
    }
    try {
        const cfg = await db()
            .collection("igrejas")
            .doc(tid)
            .collection("config")
            .doc("mercado_pago")
            .get();
        const c = cfg.data() || {};
        if (cfg.exists) {
            if (c.enabled === true)
                score += 40;
            if (String(c.publicKey || "").trim())
                score += 25;
            if (c.hasClientSecret === true)
                score += 15;
        }
    }
    catch {
        /* ignore */
    }
    try {
        const fixed = await db()
            .collection("igrejas")
            .doc(tid)
            .collection("contas")
            .doc("mercado_pago")
            .get();
        if (fixed.exists && isMpConta(fixed.data()))
            score += 30;
        else {
            const snap = await db().collection("igrejas").doc(tid).collection("contas").limit(80).get();
            for (const d of snap.docs) {
                if (isMpConta(d.data())) {
                    score += 20;
                    break;
                }
            }
        }
    }
    catch {
        /* ignore */
    }
    return score;
}
async function targetHasMpAccessToken(tenantId) {
    try {
        const priv = await db()
            .collection("igrejas")
            .doc(tenantId)
            .collection("private")
            .doc("mp_credentials")
            .get();
        return !!(priv.exists && String(priv.data()?.accessToken || "").trim());
    }
    catch {
        return false;
    }
}
async function targetHasMpConta(tenantId) {
    try {
        const fixed = await db()
            .collection("igrejas")
            .doc(tenantId)
            .collection("contas")
            .doc("mercado_pago")
            .get();
        if (fixed.exists && isMpConta(fixed.data()))
            return true;
        const snap = await db().collection("igrejas").doc(tenantId).collection("contas").limit(80).get();
        return snap.docs.some((d) => isMpConta(d.data()));
    }
    catch {
        return false;
    }
}
async function runSyncChurchMercadoPagoFromCluster(tenantId, options) {
    const target = String(tenantId || "").trim();
    if (!target) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");
    }
    const force = options?.force === true;
    const candidates = await collectRelatedIgrejaDocIds(target);
    let bestSource = "";
    let bestScore = 0;
    for (const cid of candidates) {
        const s = await scoreMpReadiness(cid);
        if (s > bestScore) {
            bestScore = s;
            bestSource = cid;
        }
    }
    if (!bestSource || bestScore < 20) {
        return {
            ok: true,
            tenantId: target,
            migrated: false,
            reason: "no_mp_source_in_cluster",
            candidates,
        };
    }
    const needsPriv = force || !(await targetHasMpAccessToken(target));
    const needsConta = force || !(await targetHasMpConta(target));
    const copied = [];
    const skipped = [];
    if (needsPriv && bestSource !== target) {
        const from = db()
            .collection("igrejas")
            .doc(bestSource)
            .collection("private")
            .doc("mp_credentials");
        const fromSnap = await from.get();
        if (fromSnap.exists && String(fromSnap.data()?.accessToken || "").trim()) {
            await db()
                .collection("igrejas")
                .doc(target)
                .collection("private")
                .doc("mp_credentials")
                .set(fromSnap.data() || {}, { merge: true });
            copied.push("private/mp_credentials");
        }
    }
    else if (!needsPriv) {
        skipped.push("private/mp_credentials");
    }
    if (bestSource !== target) {
        const cfgFrom = await db()
            .collection("igrejas")
            .doc(bestSource)
            .collection("config")
            .doc("mercado_pago")
            .get();
        if (cfgFrom.exists && (cfgFrom.data()?.enabled || cfgFrom.data()?.publicKey)) {
            await db()
                .collection("igrejas")
                .doc(target)
                .collection("config")
                .doc("mercado_pago")
                .set(cfgFrom.data() || {}, { merge: true });
            copied.push("config/mercado_pago");
        }
    }
    if (needsConta && bestSource !== target) {
        const colFrom = db().collection("igrejas").doc(bestSource).collection("contas");
        const fixed = await colFrom.doc("mercado_pago").get();
        if (fixed.exists && isMpConta(fixed.data())) {
            await db()
                .collection("igrejas")
                .doc(target)
                .collection("contas")
                .doc("mercado_pago")
                .set(fixed.data() || {}, { merge: true });
            copied.push("contas/mercado_pago");
        }
        else {
            const snap = await colFrom.limit(80).get();
            for (const d of snap.docs) {
                if (!isMpConta(d.data()))
                    continue;
                await db()
                    .collection("igrejas")
                    .doc(target)
                    .collection("contas")
                    .doc(d.id)
                    .set(d.data() || {}, { merge: true });
                copied.push(`contas/${d.id}`);
                break;
            }
        }
    }
    else if (!needsConta) {
        skipped.push("contas");
    }
    await db()
        .collection("igrejas")
        .doc(target)
        .collection("_meta")
        .doc("mp_cluster_sync_v1")
        .set({
        sourceTenantId: bestSource,
        copied,
        skipped,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        ok: true,
        tenantId: target,
        migrated: copied.length > 0,
        sourceTenantId: bestSource,
        sourceScore: bestScore,
        copied,
        skipped,
        candidates,
    };
}
/** Callable: gestor da igreja ou master — copia MP do cluster para o tenant operacional. */
exports.syncChurchMercadoPagoFromCluster = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "256MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
    }
    const tenantId = String(data?.tenantId ?? "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const claims = (context.auth.token ?? {});
    const claimTenant = String(claims.igrejaId ?? claims.tenantId ?? "").trim();
    const email = String(claims.email ?? "").toLowerCase();
    const isMaster = claims.admin === true ||
        String(claims.role ?? "").toLowerCase() === "master" ||
        email === "raihom@gmail.com";
    if (!isMaster && claimTenant !== tenantId) {
        const u = await db().collection("users").doc(context.auth.uid).get();
        const userTenant = String(u.data()?.tenantId ?? u.data()?.igrejaId ?? "").trim();
        const related = await collectRelatedIgrejaDocIds(tenantId);
        const allowed = userTenant === tenantId ||
            related.includes(userTenant) ||
            (claimTenant && related.includes(claimTenant));
        if (!allowed) {
            throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja.");
        }
    }
    const force = data?.force === true;
    return runSyncChurchMercadoPagoFromCluster(tenantId, { force });
});
//# sourceMappingURL=syncChurchMercadoPagoCluster.js.map