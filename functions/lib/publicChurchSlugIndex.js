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
exports.backfillPublicChurchSlugIndex = exports.onIgrejaWritePublicSlugIndex = void 0;
exports.normalizePublicSlugKey = normalizePublicSlugKey;
exports.syncPublicChurchSlugIndexForChurch = syncPublicChurchSlugIndexForChurch;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (v != null && String(v).trim())
            return String(v).trim();
    }
    return "";
}
/** Chave canónica do doc `public_church_slugs/{key}` — igual à URL `/igreja/{slug}`. */
function normalizePublicSlugKey(raw) {
    return String(raw || "")
        .trim()
        .toLowerCase()
        .replace(/[\s_]+/g, "-")
        .replace(/[^a-z0-9\-]/g, "")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "");
}
/**
 * Índice global slug → churchId — 1 leitura no site público e cadastro membro.
 * Mantido por trigger + recomputes de cache público.
 */
async function syncPublicChurchSlugIndexForChurch(tenantId, church) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const db = admin.firestore();
    let data = church;
    if (!data) {
        const snap = await db.collection("igrejas").doc(tid).get();
        if (!snap.exists)
            return;
        data = (snap.data() ?? {});
    }
    const slugKeys = new Set();
    for (const k of ["slug", "slugId", "alias", "siteSlug", "churchSlug"]) {
        const v = pickString(data, [k]);
        if (v)
            slugKeys.add(normalizePublicSlugKey(v));
    }
    slugKeys.add(normalizePublicSlugKey(tid));
    const churchName = pickString(data, ["nome", "name", "NOME_IGREJA", "nomeIgreja"]);
    const logoUrl = pickString(data, ["logoUrl", "logo_url", "churchLogoUrl"]);
    const endereco = pickString(data, ["endereco", "address", "ENDERECO"]);
    const rua = pickString(data, ["rua", "logradouro"]);
    const bairro = pickString(data, ["bairro"]);
    const cidade = pickString(data, ["cidade", "city"]);
    const estado = pickString(data, ["estado", "uf"]);
    const cep = pickString(data, ["cep"]);
    const churchAddress = endereco ||
        [rua, bairro, cidade, estado, cep].filter(Boolean).join(", ");
    const batch = db.batch();
    for (const key of slugKeys) {
        if (!key)
            continue;
        batch.set(db.collection("public_church_slugs").doc(key), {
            schemaVersion: 2,
            churchId: tid,
            slug: key,
            churchName,
            logoUrl: logoUrl || null,
            churchAddress: churchAddress || null,
            endereco: endereco || null,
            cidade: cidade || null,
            estado: estado || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    await batch.commit();
    functions.logger.info("publicChurchSlugIndex: synced", {
        tenantId: tid,
        keys: [...slugKeys],
    });
}
/** Trigger: slug/alias alterados ou igreja nova. */
exports.onIgrejaWritePublicSlugIndex = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}")
    .onWrite(async (change, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    if (!tenantId)
        return;
    if (!change.after.exists) {
        return;
    }
    const after = change.after.data();
    const before = change.before.exists
        ? change.before.data()
        : null;
    const slugFields = ["slug", "slugId", "alias", "siteSlug", "churchSlug", "nome", "name"];
    let changed = !change.before.exists;
    if (!changed && before) {
        for (const k of slugFields) {
            if (String(after[k] ?? "") !== String(before[k] ?? "")) {
                changed = true;
                break;
            }
        }
    }
    if (!changed)
        return;
    try {
        await syncPublicChurchSlugIndexForChurch(tenantId, after);
    }
    catch (e) {
        functions.logger.warn("onIgrejaWritePublicSlugIndex", { tenantId, e });
    }
});
/** Backfill master — todas as igrejas ou uma só. */
exports.backfillPublicChurchSlugIndex = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth?.token?.email) {
        throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const email = String(context.auth.token.email).toLowerCase();
    if (email !== "raihom@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "Somente operador master.");
    }
    const db = admin.firestore();
    const one = String(data?.tenantId ?? "").trim();
    if (one) {
        await syncPublicChurchSlugIndexForChurch(one);
        return { ok: true, count: 1 };
    }
    let count = 0;
    let last;
    const page = 80;
    for (;;) {
        let q = db.collection("igrejas").orderBy(admin.firestore.FieldPath.documentId()).limit(page);
        if (last)
            q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty)
            break;
        for (const doc of snap.docs) {
            await syncPublicChurchSlugIndexForChurch(doc.id, doc.data());
            count += 1;
        }
        last = snap.docs[snap.docs.length - 1];
        if (snap.size < page)
            break;
    }
    return { ok: true, count };
});
//# sourceMappingURL=publicChurchSlugIndex.js.map