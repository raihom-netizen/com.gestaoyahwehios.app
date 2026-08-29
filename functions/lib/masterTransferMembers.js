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
exports.masterTransferMembers = exports.masterListChurchMembers = void 0;
/**
 * Painel Master — transferência de membros entre igrejas.
 *
 * Move um ou vários membros de `igrejas/{origem}/membros` para
 * `igrejas/{destino}/membros`, arrastando também o vínculo de login
 * (`users/{uid}` e `igrejas/{t}/users/{uid}`) e refrescando o cache do módulo
 * Membros das duas igrejas — sem isso o membro continuava a aparecer na lista
 * antiga até o TTL de 8 min expirar.
 *
 * Corre com Admin SDK (ignora as regras), mas só para operador SaaS.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const masterPlatformAuth_1 = require("./masterPlatformAuth");
const membersDirectoryCache_1 = require("./membersDirectoryCache");
const forbiddenTestChurchIds_1 = require("./forbiddenTestChurchIds");
/** Lista os membros de uma igreja (id, nome, e-mail, foto) para o seletor. */
exports.masterListChurchMembers = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    if (!(0, masterPlatformAuth_1.isPlatformOperatorToken)(context.auth.token, context.auth.uid)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao painel Master.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId || (0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(tenantId)) {
        throw new functions.https.HttpsError("invalid-argument", "Informe a igreja de origem.");
    }
    const limit = Math.min(Math.max(parseInt(String(data?.limit ?? "500"), 10) || 500, 1), 1000);
    const snap = await admin
        .firestore()
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .limit(limit)
        .get();
    const members = snap.docs.map((d) => {
        const m = d.data() || {};
        return {
            id: d.id,
            nome: String(m.NOME ?? m.nome ?? m.name ?? "").trim(),
            email: String(m.EMAIL ?? m.email ?? "").trim().toLowerCase(),
            telefone: String(m.TELEFONE ?? m.telefone ?? m.phone ?? "").trim(),
            status: String(m.status ?? m.STATUS ?? "").trim(),
            codigo: String(m.codigo ?? m.CODIGO ?? "").trim(),
            fotoUrl: String(m.fotoThumbUrl ?? m.fotoUrl ?? m.FOTO_URL ?? "").trim(),
            authUid: String(m.authUid ?? m.uid ?? d.id).trim(),
        };
    });
    members.sort((a, b) => a.nome.toLocaleLowerCase().localeCompare(b.nome.toLocaleLowerCase()));
    return { ok: true, tenantId, total: members.length, members };
});
/** Transfere os membros indicados de uma igreja para outra, um a um. */
exports.masterTransferMembers = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    if (!(0, masterPlatformAuth_1.isPlatformOperatorToken)(context.auth.token, context.auth.uid)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao painel Master.");
    }
    const fromTenantId = String(data?.fromTenantId || "").trim();
    const toTenantId = String(data?.toTenantId || "").trim();
    const rawIds = Array.isArray(data?.memberIds) ? data.memberIds : [];
    const memberIds = rawIds
        .map((e) => String(e || "").trim())
        .filter((e) => e.length > 0);
    if (!fromTenantId || !toTenantId) {
        throw new functions.https.HttpsError("invalid-argument", "Informe a igreja de origem e a de destino.");
    }
    if (fromTenantId === toTenantId) {
        throw new functions.https.HttpsError("invalid-argument", "A igreja de destino tem de ser diferente da origem.");
    }
    if (memberIds.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Selecione pelo menos um membro.");
    }
    if ((0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(fromTenantId) ||
        (0, forbiddenTestChurchIds_1.isForbiddenTestChurchId)(toTenantId)) {
        throw new functions.https.HttpsError("invalid-argument", "Igreja de teste não pode participar da transferência.");
    }
    const db = admin.firestore();
    const origem = db.collection("igrejas").doc(fromTenantId);
    const destino = db.collection("igrejas").doc(toTenantId);
    const [origemSnap, destinoSnap] = await Promise.all([
        origem.get(),
        destino.get(),
    ]);
    if (!origemSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja de origem não encontrada.");
    }
    if (!destinoSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja de destino não encontrada.");
    }
    const resultados = [];
    // Um a um: se um membro falhar (doc apagado entretanto, por exemplo) os
    // restantes continuam a ser transferidos e o painel mostra o detalhe.
    for (const id of memberIds) {
        try {
            const membroRef = origem.collection("membros").doc(id);
            const membroSnap = await membroRef.get();
            if (!membroSnap.exists) {
                resultados.push({
                    id,
                    ok: false,
                    reason: "Membro não existe mais na igreja de origem.",
                });
                continue;
            }
            const dados = membroSnap.data() || {};
            const authUid = String(dados.authUid ?? dados.uid ?? id).trim();
            const payload = {
                ...dados,
                igrejaId: toTenantId,
                tenantId: toTenantId,
                transferredFromTenantId: fromTenantId,
                transferredAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            await destino.collection("membros").doc(id).set(payload, { merge: true });
            await membroRef.delete();
            // Vínculo de login dentro do tenant.
            if (authUid) {
                try {
                    const tenantUserSnap = await origem
                        .collection("users")
                        .doc(authUid)
                        .get();
                    if (tenantUserSnap.exists) {
                        await destino
                            .collection("users")
                            .doc(authUid)
                            .set({
                            ...(tenantUserSnap.data() || {}),
                            igrejaId: toTenantId,
                            tenantId: toTenantId,
                            authUid,
                            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        }, { merge: true });
                        await origem.collection("users").doc(authUid).delete();
                    }
                }
                catch (_) {
                    /* vínculo opcional — a transferência do membro já foi feita */
                }
                // Documento raiz do utilizador: passa a apontar para o destino.
                try {
                    const rootRef = db.collection("users").doc(authUid);
                    if ((await rootRef.get()).exists) {
                        await rootRef.set({
                            igrejaId: toTenantId,
                            tenantId: toTenantId,
                            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        }, { merge: true });
                    }
                }
                catch (_) {
                    /* idem */
                }
                // Índice de e-mail/uid por igreja, quando existir.
                try {
                    const idxSnap = await origem
                        .collection("usersIndex")
                        .doc(authUid)
                        .get();
                    if (idxSnap.exists) {
                        await destino
                            .collection("usersIndex")
                            .doc(authUid)
                            .set({
                            ...(idxSnap.data() || {}),
                            igrejaId: toTenantId,
                            tenantId: toTenantId,
                        }, { merge: true });
                        await origem.collection("usersIndex").doc(authUid).delete();
                    }
                }
                catch (_) {
                    /* idem */
                }
            }
            resultados.push({ id, ok: true });
        }
        catch (e) {
            resultados.push({
                id,
                ok: false,
                reason: e instanceof Error ? e.message : String(e),
            });
        }
    }
    // Cache do módulo Membros das duas igrejas — sem isto o membro continuava
    // visível na origem e invisível no destino durante minutos.
    await Promise.all([
        (0, membersDirectoryCache_1.refreshMembersDirectoryCache)(fromTenantId).catch(() => undefined),
        (0, membersDirectoryCache_1.refreshMembersDirectoryCache)(toTenantId).catch(() => undefined),
    ]);
    const movidos = resultados.filter((r) => r.ok).length;
    return {
        ok: movidos > 0,
        fromTenantId,
        toTenantId,
        requested: memberIds.length,
        moved: movidos,
        failed: resultados.filter((r) => !r.ok),
    };
});
//# sourceMappingURL=masterTransferMembers.js.map