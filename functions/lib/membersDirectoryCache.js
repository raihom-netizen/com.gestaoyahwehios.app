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
exports.getChurchMembersDirectory = void 0;
exports.recomputeMembersDirectoryFromDocs = recomputeMembersDirectoryFromDocs;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const tenantCallableResolve_1 = require("./tenantCallableResolve");
const DIRECTORY_MAX = 800;
function pickString(data, keys) {
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim())
            return v.trim();
    }
    return "";
}
function pickPhotoUrl(data) {
    const keys = [
        "fotoUrl",
        "fotoURL",
        "FOTO_URL",
        "FOTO_URL_OU_ID",
        "imageUrl",
        "photoUrl",
        "foto",
        "FOTO",
        "avatarUrl",
        "profilePhotoUrl",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http")) {
            return v.trim();
        }
    }
    return "";
}
function pickPhotoThumbUrl(data) {
    const keys = [
        "fotoThumbUrl",
        "photoThumbUrl",
        "photoThumb",
        "thumbUrl",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http")) {
            return v.trim();
        }
    }
    return "";
}
function normCpf(raw) {
    const d = String(raw ?? "").replace(/\D/g, "");
    if (!d)
        return "";
    if (d.length > 11)
        return d.substring(d.length - 11);
    if (d.length < 11)
        return d.padStart(11, "0");
    return d;
}
function directoryEntry(doc) {
    const d = doc.data();
    const revRaw = d.fotoUrlCacheRevision ?? d.photoCacheRevision;
    const fotoUrlCacheRevision = typeof revRaw === "number" && Number.isFinite(revRaw)
        ? Math.floor(revRaw)
        : 0;
    const cpf = normCpf(pickString(d, ["CPF", "cpf"]) || normCpf(doc.id));
    const funcoesRaw = d.FUNCOES ?? d.funcoes;
    const funcoes = [];
    if (Array.isArray(funcoesRaw)) {
        for (const x of funcoesRaw) {
            const s = String(x ?? "").trim();
            if (s)
                funcoes.push(s);
        }
    }
    const deptRaw = d.DEPARTAMENTOS ?? d.departamentos ?? d.departamentosIds;
    const departamentos = [];
    if (Array.isArray(deptRaw)) {
        for (const x of deptRaw) {
            const s = String(x ?? "").trim();
            if (s)
                departamentos.push(s);
        }
    }
    const status = pickString(d, ["STATUS", "status"]).toLowerCase() || "ativo";
    const fullPhoto = pickPhotoUrl(d);
    const thumbPhoto = pickPhotoThumbUrl(d) || fullPhoto || null;
    return {
        memberDocId: doc.id,
        displayName: pickString(d, ["NOME_COMPLETO", "nome", "name"]) || "Membro",
        photoUrl: fullPhoto || null,
        photoThumbUrl: thumbPhoto,
        fotoUrlCacheRevision,
        authUid: pickString(d, ["authUid", "firebaseUid", "uid", "userId"]) || null,
        cpfDigits: cpf.length === 11 ? cpf : null,
        email: pickString(d, ["EMAIL", "email"]) || null,
        telefone: pickString(d, ["TELEFONES", "TELEFONE", "telefone", "phone"]) || null,
        status,
        STATUS: status,
        funcao: pickString(d, ["FUNCAO", "funcao", "CARGO", "role"]) || null,
        funcoes,
        departamentos,
        genero: pickString(d, ["SEXO", "sexo", "genero", "gender"]) || null,
        createdAt: d.createdAt ?? d.criadoEm ?? null,
        updatedAt: d.updatedAt ?? null,
        dataNascimento: d.DATA_NASCIMENTO ?? d.dataNascimento ?? d.birthDate ?? null,
    };
}
function computeMembersSummary(memberDocs) {
    let ativos = 0;
    let inativos = 0;
    let pendentes = 0;
    let homens = 0;
    let mulheres = 0;
    let sexoNi = 0;
    for (const doc of memberDocs) {
        const e = directoryEntry(doc);
        const status = String(e.status ?? "ativo").toLowerCase();
        if (status.includes("pendente"))
            pendentes += 1;
        else if (status.includes("inativ"))
            inativos += 1;
        else
            ativos += 1;
        const g = String(e.genero ?? "").toLowerCase().trim();
        if (g.startsWith("m") || g === "masculino" || g === "m")
            homens += 1;
        else if (g.startsWith("f") || g === "feminino" || g === "f")
            mulheres += 1;
        else
            sexoNi += 1;
    }
    return {
        total: memberDocs.length,
        ativos,
        inativos,
        pendentes,
        homens,
        mulheres,
        sexoNi,
    };
}
/**
 * Grava `igrejas/{tenantId}/_panel_cache/members_directory` (1 read na lista).
 * Chamado após scan de `membros` no painel (sem segunda query).
 */
async function recomputeMembersDirectoryFromDocs(tenantId, memberDocs, totalCount) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return;
    const summary = computeMembersSummary(memberDocs);
    const entries = memberDocs
        .map((doc) => directoryEntry(doc))
        .sort((a, b) => String(a.displayName ?? "")
        .toLowerCase()
        .localeCompare(String(b.displayName ?? "").toLowerCase()))
        .slice(0, DIRECTORY_MAX);
    const ref = admin
        .firestore()
        .collection("igrejas")
        .doc(tid)
        .collection("_panel_cache")
        .doc("members_directory");
    const resolvedTotal = typeof totalCount === "number" && totalCount > 0
        ? totalCount
        : memberDocs.length;
    await ref.set({
        schemaVersion: 2,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        totalCount: resolvedTotal,
        summary: {
            ...summary,
            total: resolvedTotal,
        },
        entries,
    }, { merge: false });
    functions.logger.info("membersDirectoryCache: atualizado", {
        tenantId: tid,
        entries: entries.length,
        totalCount: resolvedTotal,
        ativos: summary.ativos,
    });
}
/** Callable: 1 round-trip para lista leve de membros (módulo Membros). */
exports.getChurchMembersDirectory = functions
    .region("us-central1")
    .https.onCall(async (request, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {});
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(body.tenantId || ""));
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const db = admin.firestore();
    const ref = db
        .collection("igrejas")
        .doc(tenantId)
        .collection("_panel_cache")
        .doc("members_directory");
    const snap = await ref.get();
    const staleMs = 8 * 60 * 1000;
    let directory = snap.data();
    const updated = directory?.updatedAt;
    const isStale = !snap.exists ||
        !updated ||
        Date.now() - updated.toMillis() > staleMs;
    if (isStale) {
        // Sem orderBy — docs legados sem `updatedAt` entravam no count() mas não na lista (46 vs 62).
        const membrosSnap = await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("membros")
            .limit(DIRECTORY_MAX)
            .get();
        let total = membrosSnap.size;
        try {
            const agg = await db
                .collection("igrejas")
                .doc(tenantId)
                .collection("membros")
                .count()
                .get();
            total = agg.data().count;
        }
        catch (_) {
            /* count opcional */
        }
        await recomputeMembersDirectoryFromDocs(tenantId, membrosSnap.docs, total);
        directory = (await ref.get()).data();
    }
    return { ok: true, tenantId, directory: directory ?? {} };
});
//# sourceMappingURL=membersDirectoryCache.js.map