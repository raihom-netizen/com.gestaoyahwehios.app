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
exports.onEscalaTrocaInviteTarget = exports.respondScheduleSwap = exports.hourlyDevotionalBroadcast = exports.rollingScaleRemindersConfirmed = exports.dayBeforeScaleReminder = exports.dailyBirthdayTopicPush = exports.onEscalaImpedimentoNotifyLeaders = exports.notifySchedulePublished = exports.deleteDevotionalEnvio = exports.resendDevotionalEnvio = exports.resendPastoralMessage = exports.archivePastoralMessage = exports.sendSegmentedPush = void 0;
exports.slugTopicPart = slugTopicPart;
/**
 * Comunicação pastoral: push segmentado (tópicos), lembrete de escala (véspera), devocional diário.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const memberNotificationEmail_1 = require("./memberNotificationEmail");
const db = admin.firestore();
function normalizeRole(value) {
    return String(value || "").trim().toUpperCase();
}
function isPrivilegedRole(role) {
    return ["MASTER", "ADMIN", "ADM"].includes(role);
}
function isChurchManagerRole(role) {
    return ["MASTER", "ADMIN", "ADM", "GESTOR"].includes(role);
}
async function resolveRoleFromTokenOrDb(uid, tokenRole) {
    const tokenNormalized = normalizeRole(tokenRole);
    if (tokenNormalized)
        return tokenNormalized;
    try {
        const userDoc = await db.collection("users").doc(uid).get();
        const data = userDoc.exists ? userDoc.data() || {} : {};
        const roleFromDb = normalizeRole(data.role ?? data.nivel ?? data.perfil ?? data.NIVEL);
        if (roleFromDb)
            return roleFromDb;
    }
    catch (_) { }
    return "";
}
async function canManageTenant(uid, tokenRole, tokenTenantId, tenantId) {
    const role = await resolveRoleFromTokenOrDb(uid, tokenRole);
    if (isPrivilegedRole(role))
        return true;
    if (!isChurchManagerRole(role))
        return false;
    const tokenTenant = String(tokenTenantId || "").trim();
    if (tokenTenant && tokenTenant === tenantId)
        return true;
    try {
        const u = await db.collection("users").doc(uid).get();
        const data = u.exists ? u.data() || {} : {};
        const userTenant = String(data.tenantId || data.igrejaId || "").trim();
        if (userTenant && userTenant === tenantId)
            return true;
    }
    catch (_) { }
    return false;
}
const PASTORAL_COMMS_ROLES = new Set([
    "PASTOR",
    "PASTORA",
    "SECRETARIO",
    "SECRETÁRIO",
    "PRESBITERO",
    "PRESBITERA",
    "BISPO",
]);
async function canSendChurchCommunications(uid, tokenRole, tokenTenantId, tenantId) {
    if (await canManageTenant(uid, tokenRole, tokenTenantId, tenantId))
        return true;
    const role = await resolveRoleFromTokenOrDb(uid, tokenRole);
    if (!PASTORAL_COMMS_ROLES.has(role))
        return false;
    const tokenTenant = String(tokenTenantId || "").trim();
    if (tokenTenant && tokenTenant === tenantId)
        return true;
    try {
        const u = await db.collection("users").doc(uid).get();
        const data = u.exists ? u.data() || {} : {};
        const userTenant = String(data.tenantId || data.igrejaId || "").trim();
        return userTenant === tenantId;
    }
    catch (_) {
        return false;
    }
}
function slugTopicPart(raw) {
    const s = String(raw || "")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "")
        .slice(0, 48);
    return s || "todos";
}
function ymdStringInTz(d, tz) {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: tz,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(d);
}
function addOneDayYmd(ymd) {
    const [y, m, d] = ymd.split("-").map((v) => parseInt(v, 10));
    const dt = new Date(Date.UTC(y, m - 1, d));
    dt.setUTCDate(dt.getUTCDate() + 1);
    const yy = dt.getUTCFullYear();
    const mm = String(dt.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(dt.getUTCDate()).padStart(2, "0");
    return `${yy}-${mm}-${dd}`;
}
async function collectFcmTokensForCpfs(tenantId, cpfs) {
    const out = new Set();
    const col = db.collection("igrejas").doc(tenantId).collection("membros");
    for (const raw of cpfs) {
        const digits = String(raw || "").replace(/\D/g, "");
        if (digits.length !== 11)
            continue;
        let snap = await col.doc(digits).get();
        if (!snap.exists) {
            const q = await col.where("CPF", "==", digits).limit(1).get();
            snap = q.docs[0] || snap;
        }
        if (!snap.exists)
            continue;
        const uid = String((snap.data() || {}).authUid || "").trim();
        if (!uid)
            continue;
        const tokSnap = await db.collection("users").doc(uid).collection("fcmTokens").get();
        for (const t of tokSnap.docs) {
            const token = String((t.data() || {}).token || "").trim();
            if (token)
                out.add(token);
        }
    }
    return [...out];
}
async function firstNameForCpf(tenantId, cpfDigits) {
    const col = db.collection("igrejas").doc(tenantId).collection("membros");
    const digits = cpfDigits.replace(/\D/g, "");
    if (digits.length !== 11)
        return "Irmão(ã)";
    let snap = await col.doc(digits).get();
    if (!snap.exists) {
        const q = await col.where("CPF", "==", digits).limit(1).get();
        snap = q.docs[0] || snap;
    }
    if (!snap.exists)
        return "Irmão(ã)";
    const full = String((snap.data() || {}).NOME_COMPLETO || (snap.data() || {}).nome || "").trim();
    return (full.split(/\s+/)[0] || "Irmão(ã)").replace(/,$/, "");
}
/** E-mail do cadastro de membro (para notificações HTML). */
async function memberEmailFromMembro(tenantId, cpfDigits) {
    const col = db.collection("igrejas").doc(tenantId).collection("membros");
    const digits = cpfDigits.replace(/\D/g, "");
    if (digits.length !== 11)
        return null;
    let snap = await col.doc(digits).get();
    if (!snap.exists) {
        const q = await col.where("CPF", "==", digits).limit(1).get();
        snap = q.docs[0] || snap;
    }
    if (!snap.exists)
        return null;
    const m = snap.data() || {};
    const raw = String(m.EMAIL || m.email || "").trim().toLowerCase();
    return raw.includes("@") ? raw : null;
}
async function sendEachInBatches(messages) {
    const batchSize = 400;
    for (let i = 0; i < messages.length; i += batchSize) {
        const chunk = messages.slice(i, i + batchSize);
        try {
            await admin.messaging().sendEach(chunk);
        }
        catch (e) {
            functions.logger.error("sendEach batch", e);
        }
    }
}
function parseStringArray(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const x of raw) {
        const s = String(x ?? "").trim();
        if (s)
            out.push(s);
    }
    return out;
}
/**
 * Entrega FCM: vários departamentos/cargos = vários tópicos; vários membros = tokens agregados.
 */
async function runMultiSegmentDelivery(params) {
    const { tenantId, title, body, messageId, segment: segIn, departmentId, departmentIds: deptIdsIn, cargoLabel, cargoLabels: cargosIn, memberDocId, memberDocIds: membersIn, } = params;
    const segment = (segIn || "broadcast").toLowerCase();
    const deptList = deptIdsIn.length > 0 ? deptIdsIn : departmentId ? [departmentId] : [];
    const cargoList = cargosIn.length > 0 ? cargosIn : cargoLabel ? [cargoLabel] : [];
    const memberList = membersIn.length > 0 ? membersIn : memberDocId ? [memberDocId] : [];
    const baseData = (seg) => ({
        tenantId,
        type: "pastoral_comm",
        pastoralMessageId: messageId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        segment: seg,
    });
    if (segment === "member") {
        if (!memberList.length) {
            throw new functions.https.HttpsError("invalid-argument", "Selecione ao menos um membro.");
        }
        const cpfs = [];
        const col = db.collection("igrejas").doc(tenantId).collection("membros");
        for (const mid of memberList) {
            const msnap = await col.doc(mid).get();
            if (!msnap.exists)
                continue;
            const md = msnap.data() || {};
            const cpfRaw = String(md.CPF || md.cpf || "").replace(/\D/g, "");
            if (cpfRaw.length === 11)
                cpfs.push(cpfRaw);
        }
        if (!cpfs.length) {
            throw new functions.https.HttpsError("failed-precondition", "Nenhum membro válido (CPF) na seleção.");
        }
        const tokens = await collectFcmTokensForCpfs(tenantId, cpfs);
        if (!tokens.length) {
            throw new functions.https.HttpsError("failed-precondition", "Nenhum aparelho com notificação para os membros selecionados.");
        }
        const messages = tokens.map((token) => ({
            token,
            notification: { title, body },
            data: baseData("member"),
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
        }));
        await sendEachInBatches(messages);
        return { topic: `direct_members_${memberList.length}` };
    }
    const topicsOut = [];
    if (segment === "department") {
        if (!deptList.length) {
            throw new functions.https.HttpsError("invalid-argument", "Selecione ao menos um departamento.");
        }
        for (const did of deptList) {
            const topic = `dept_${did}`;
            await admin.messaging().send({
                topic,
                notification: { title, body },
                data: baseData("department"),
            });
            topicsOut.push(topic);
        }
        return { topic: topicsOut.join(",") };
    }
    if (segment === "cargo") {
        if (!cargoList.length) {
            throw new functions.https.HttpsError("invalid-argument", "Selecione ao menos um cargo.");
        }
        for (const lab of cargoList) {
            const topic = `cargo_${slugTopicPart(lab)}`;
            await admin.messaging().send({
                topic,
                notification: { title, body },
                data: baseData("cargo"),
            });
            topicsOut.push(topic);
        }
        return { topic: topicsOut.join(",") };
    }
    const topic = `igreja_${tenantId}`;
    await admin.messaging().send({
        topic,
        notification: { title, body },
        data: baseData("broadcast"),
    });
    return { topic };
}
/** Gestor ou pastoral: envia FCM para tópico (igreja, departamento, cargo) ou direto a um membro. */
exports.sendSegmentedPush = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const title = String(data?.title || "").trim();
    const body = String(data?.body || "").trim();
    const segment = String(data?.segment || "broadcast").trim().toLowerCase();
    const departmentId = String(data?.departmentId || "").trim();
    const cargoLabel = String(data?.cargoLabel || "").trim();
    const memberDocId = String(data?.memberDocId || "").trim();
    const departmentIds = parseStringArray(data?.departmentIds);
    const cargoLabels = parseStringArray(data?.cargoLabels);
    const memberDocIds = parseStringArray(data?.memberDocIds);
    const expMsRaw = data?.expiresAtMillis;
    let expiresAt = null;
    if (typeof expMsRaw === "number" && Number.isFinite(expMsRaw) && expMsRaw > 0) {
        expiresAt = admin.firestore.Timestamp.fromMillis(Math.floor(expMsRaw));
    }
    if (!tenantId || !title || !body) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId, title e body são obrigatórios.");
    }
    const allowed = await canSendChurchCommunications(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para enviar comunicações.");
    }
    const msgRef = db.collection("igrejas").doc(tenantId).collection("pastoral_mensagens").doc();
    const messageId = msgRef.id;
    let topicOut;
    try {
        const r = await runMultiSegmentDelivery({
            tenantId,
            title,
            body,
            messageId,
            segment,
            departmentId,
            departmentIds,
            cargoLabel,
            cargoLabels,
            memberDocId,
            memberDocIds,
        });
        topicOut = r.topic;
    }
    catch (e) {
        if (e instanceof functions.https.HttpsError) {
            throw e;
        }
        functions.logger.error("sendSegmentedPush FCM", e);
        throw new functions.https.HttpsError("internal", "Falha ao enviar notificação.");
    }
    const msgPayload = {
        title,
        body,
        segment,
        topic: topicOut,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentByUid: context.auth.uid,
        archived: false,
    };
    if (departmentIds.length) {
        msgPayload.departmentIds = departmentIds;
        msgPayload.departmentId = departmentIds[0];
    }
    else if (departmentId) {
        msgPayload.departmentId = departmentId;
    }
    if (cargoLabels.length) {
        msgPayload.cargoLabels = cargoLabels;
        msgPayload.cargoLabel = cargoLabels[0];
    }
    else if (cargoLabel) {
        msgPayload.cargoLabel = cargoLabel;
    }
    if (memberDocIds.length) {
        msgPayload.memberDocIds = memberDocIds;
        msgPayload.memberDocId = memberDocIds[0];
    }
    else if (memberDocId) {
        msgPayload.memberDocId = memberDocId;
    }
    if (expiresAt)
        msgPayload.expiresAt = expiresAt;
    await msgRef.set(msgPayload);
    const notifPayload = {
        type: "push_segmentado",
        messageId,
        title,
        body,
        segment,
        topic: topicOut,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        sentByUid: context.auth.uid,
    };
    if (departmentIds.length) {
        notifPayload.departmentIds = departmentIds;
        notifPayload.departmentId = departmentIds[0];
    }
    else if (departmentId) {
        notifPayload.departmentId = departmentId;
    }
    if (cargoLabels.length) {
        notifPayload.cargoLabels = cargoLabels;
        notifPayload.cargoLabel = cargoLabels[0];
    }
    else if (cargoLabel) {
        notifPayload.cargoLabel = cargoLabel;
    }
    if (memberDocIds.length) {
        notifPayload.memberDocIds = memberDocIds;
        notifPayload.memberDocId = memberDocIds[0];
    }
    else if (memberDocId) {
        notifPayload.memberDocId = memberDocId;
    }
    if (expiresAt)
        notifPayload.expiresAt = expiresAt;
    await db.collection("igrejas").doc(tenantId).collection("notificacoes").add(notifPayload);
    return { ok: true, topic: topicOut, messageId };
});
/** Arquivar mensagem pastoral (some do painel / histórico ativo). */
exports.archivePastoralMessage = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const messageId = String(data?.messageId || "").trim();
    if (!tenantId || !messageId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e messageId são obrigatórios.");
    }
    const allowed = await canSendChurchCommunications(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão.");
    }
    await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("pastoral_mensagens")
        .doc(messageId)
        .set({
        archived: true,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        archivedByUid: context.auth.uid,
    }, { merge: true });
    return { ok: true };
});
/** Reenviar mesma notificação (novo push com o mesmo conteúdo). */
exports.resendPastoralMessage = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const messageId = String(data?.messageId || "").trim();
    if (!tenantId || !messageId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e messageId são obrigatórios.");
    }
    const allowed = await canSendChurchCommunications(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão.");
    }
    const ref = db.collection("igrejas").doc(tenantId).collection("pastoral_mensagens").doc(messageId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Mensagem não encontrada.");
    }
    const d = snap.data() || {};
    if (d.archived === true) {
        throw new functions.https.HttpsError("failed-precondition", "Mensagem arquivada — reative ou crie nova.");
    }
    const segment = String(d.segment || "broadcast").trim().toLowerCase();
    const title = String(d.title || "").trim();
    const body = String(d.body || "").trim();
    if (!title || !body) {
        throw new functions.https.HttpsError("failed-precondition", "Dados incompletos.");
    }
    const departmentIds = parseStringArray(d.departmentIds);
    const cargoLabels = parseStringArray(d.cargoLabels);
    const memberDocIds = parseStringArray(d.memberDocIds);
    try {
        await runMultiSegmentDelivery({
            tenantId,
            title,
            body,
            messageId,
            segment,
            departmentId: String(d.departmentId || "").trim(),
            departmentIds,
            cargoLabel: String(d.cargoLabel || "").trim(),
            cargoLabels,
            memberDocId: String(d.memberDocId || "").trim(),
            memberDocIds,
        });
    }
    catch (e) {
        if (e instanceof functions.https.HttpsError) {
            throw e;
        }
        functions.logger.error("resendPastoralMessage FCM", e);
        throw new functions.https.HttpsError("internal", "Falha ao reenviar.");
    }
    await ref.set({
        lastResentAt: admin.firestore.FieldValue.serverTimestamp(),
        resendCount: admin.firestore.FieldValue.increment(1),
    }, { merge: true });
    return { ok: true };
});
/** Reenvia um devocional já registrado no histórico (mesmo texto/título no tópico da igreja). */
exports.resendDevotionalEnvio = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const envioId = String(data?.envioId || "").trim();
    if (!tenantId || !envioId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e envioId são obrigatórios.");
    }
    const allowed = await canSendChurchCommunications(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão.");
    }
    const ref = db.collection("igrejas").doc(tenantId).collection("devocional_envios").doc(envioId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Registro não encontrado.");
    }
    const d = snap.data() || {};
    const titulo = String(d.titulo || "Bom dia").trim() || "Bom dia";
    const texto = String(d.texto || "").trim();
    const refBib = String(d.referencia || "").trim();
    const body = [texto, refBib].filter((x) => x.length > 0).join("\n").trim();
    if (!body) {
        throw new functions.https.HttpsError("failed-precondition", "Conteúdo vazio.");
    }
    try {
        await admin.messaging().send({
            topic: `igreja_${tenantId}`,
            notification: {
                title: titulo,
                body: body.length > 180 ? `${body.slice(0, 177)}...` : body,
            },
            data: {
                tenantId,
                type: "devocional",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
        });
    }
    catch (e) {
        functions.logger.error("resendDevotionalEnvio FCM", e);
        throw new functions.https.HttpsError("internal", "Falha ao reenviar notificação.");
    }
    await ref.set({
        lastResentAt: admin.firestore.FieldValue.serverTimestamp(),
        resendCount: admin.firestore.FieldValue.increment(1),
    }, { merge: true });
    return { ok: true };
});
/** Remove uma linha do histórico de devocionais enviados (não altera a config atual). */
exports.deleteDevotionalEnvio = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const envioId = String(data?.envioId || "").trim();
    if (!tenantId || !envioId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e envioId são obrigatórios.");
    }
    const allowed = await canSendChurchCommunications(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão.");
    }
    const ref = db.collection("igrejas").doc(tenantId).collection("devocional_envios").doc(envioId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Registro não encontrado.");
    }
    await ref.delete();
    return { ok: true };
});
async function userCpfDigitsFromUid(uid) {
    try {
        const u = await db.collection("users").doc(uid).get();
        const data = u.data() || {};
        const raw = data.cpf ?? data.CPF;
        return String(raw || "").replace(/\D/g, "");
    }
    catch (_) {
        return "";
    }
}
function cpfsFromDepartmentData(data) {
    const out = [];
    const add = (raw) => {
        const x = String(raw || "").replace(/\D/g, "");
        if (x.length === 11 && !out.includes(x))
            out.push(x);
    };
    if (!data)
        return out;
    const rawList = data.leaderCpfs ?? data.leader_cpfs;
    if (Array.isArray(rawList))
        for (const e of rawList)
            add(e);
    add(data.leaderCpf);
    add(data.viceLeaderCpf);
    add(data.vice_leader_cpf);
    return out;
}
async function isDepartmentLeaderCpf(tenantId, departmentId, cpfDigits) {
    if (cpfDigits.length !== 11)
        return false;
    const snap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("departamentos")
        .doc(departmentId)
        .get();
    if (!snap.exists)
        return false;
    return cpfsFromDepartmentData(snap.data()).includes(cpfDigits);
}
async function canNotifyScheduleForUser(uid, tokenRole, tokenTenantId, tenantId, departmentId) {
    if (await canSendChurchCommunications(uid, tokenRole, tokenTenantId, tenantId))
        return true;
    const cpf = await userCpfDigitsFromUid(uid);
    if (!departmentId || cpf.length !== 11)
        return false;
    return isDepartmentLeaderCpf(tenantId, departmentId, cpf);
}
function formatDatePtBr(d) {
    const dd = String(d.getDate()).padStart(2, "0");
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    return `${dd}/${mm}/${d.getFullYear()}`;
}
/**
 * Líder/gestor: envia push personalizado a cada membro escalado (tokens FCM por CPF).
 */
exports.notifySchedulePublished = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const scheduleId = String(data?.scheduleId || "").trim();
    if (!tenantId || !scheduleId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e scheduleId são obrigatórios.");
    }
    const ref = db.collection("igrejas").doc(tenantId).collection("escalas").doc(scheduleId);
    const snap = await ref.get();
    if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Escala não encontrada.");
    }
    const d = snap.data() || {};
    const departmentId = String(d.departmentId || "").trim();
    const allowed = await canNotifyScheduleForUser(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId, departmentId);
    if (!allowed) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para notificar esta escala.");
    }
    const memberCpfs = Array.isArray(d.memberCpfs)
        ? d.memberCpfs
            .map((v) => String(v || "").replace(/\D/g, ""))
            .filter((c) => c.length === 11)
        : [];
    if (!memberCpfs.length) {
        throw new functions.https.HttpsError("failed-precondition", "Nenhum membro na escala.");
    }
    const ts = d.date;
    const eventDate = ts && typeof ts.toDate === "function" ? ts.toDate() : null;
    const dateStr = eventDate ? formatDatePtBr(eventDate) : "data a definir";
    const deptName = String(d.departmentName || "").trim();
    const titleStr = String(d.title || "Escala").trim();
    const timeStr = String(d.time || "19:00").trim();
    const locLine = String(d.location || d.local || d.place || d.setor || "").trim() ||
        deptName ||
        "—";
    const messages = [];
    for (const cpf of memberCpfs) {
        const tokens = await collectFcmTokensForCpfs(tenantId, [cpf]);
        if (!tokens.length)
            continue;
        const nome = await firstNameForCpf(tenantId, cpf);
        const body = `${nome}, você foi escalado(a) para ${deptName || "o ministério"} no dia ${dateStr}${titleStr ? ` — ${titleStr}` : ""}`
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 220);
        for (const token of tokens) {
            messages.push({
                token,
                notification: {
                    title: "Você foi escalado(a)",
                    body,
                },
                data: {
                    tenantId,
                    type: "escala_publicada",
                    scheduleId,
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: { priority: "high" },
                apns: { payload: { aps: { sound: "default" } } },
            });
        }
    }
    await sendEachInBatches(messages);
    let emailsSent = 0;
    try {
        for (const cpf of memberCpfs) {
            const email = await memberEmailFromMembro(tenantId, cpf);
            if (!email)
                continue;
            const nomeVol = await firstNameForCpf(tenantId, cpf);
            const funcao = deptName || titleStr || "Ministério";
            const { subject, html } = (0, memberNotificationEmail_1.buildEscalaEmail)({
                volunteerName: nomeVol,
                funcao,
                dataEventoPt: dateStr,
                horarioChegada: timeStr,
                local: locLine,
            });
            const sent = await (0, memberNotificationEmail_1.sendGestaoYahwehHtmlEmail)({ to: email, subject, html });
            if (sent)
                emailsSent += 1;
        }
    }
    catch (e) {
        functions.logger.error("notifySchedulePublished email", e);
    }
    await ref.set({ lastPushNotifiedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { ok: true, count: messages.length, emailsSent };
});
/**
 * Quando um membro marca indisponível, avisa o tópico do departamento (líderes inscritos em dept_*).
 */
exports.onEscalaImpedimentoNotifyLeaders = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/escalas/{escId}")
    .onUpdate(async (change, context) => {
    const tenantId = context.params.tenantId;
    const escId = context.params.escId;
    const before = (change.before.data() || {});
    const after = (change.after.data() || {});
    const befConf = (before.confirmations || {});
    const aftConf = (after.confirmations || {});
    const deptId = String(after.departmentId || "").trim();
    if (!deptId)
        return null;
    const newlyUnavailable = [];
    for (const k of Object.keys(aftConf)) {
        const v = String(aftConf[k] || "").trim();
        if (v !== "indisponivel")
            continue;
        const prev = String(befConf[k] || "").trim();
        if (prev === "indisponivel")
            continue;
        const cpfNorm = k.replace(/\D/g, "");
        if (cpfNorm.length === 11)
            newlyUnavailable.push(cpfNorm);
    }
    if (!newlyUnavailable.length)
        return null;
    const ts = after.date;
    const eventDate = ts && typeof ts.toDate === "function" ? ts.toDate() : null;
    const dateStr = eventDate ? formatDatePtBr(eventDate) : "";
    const titleStr = String(after.title || "Escala").trim();
    const firstCpf = newlyUnavailable[0];
    const nome = await firstNameForCpf(tenantId, firstCpf);
    const extra = newlyUnavailable.length > 1 ? ` (+${newlyUnavailable.length - 1})` : "";
    const body = `${nome} informou impedimento na escala ${dateStr}${titleStr ? ` (${titleStr})` : ""}${extra}. Remaneje se necessário.`
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 220);
    try {
        await admin.messaging().send({
            topic: `dept_${deptId}`,
            notification: {
                title: "Impedimento na escala",
                body,
            },
            data: {
                tenantId,
                type: "escala_impedimento",
                scheduleId: escId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            android: { priority: "high" },
        });
    }
    catch (e) {
        functions.logger.error("onEscalaImpedimentoNotifyLeaders FCM", { tenantId, escId, e });
    }
    return null;
});
const TZ_BR = "America/Sao_Paulo";
/** Mesma lógica ampla do app (Flutter `birthDateFromMemberData`). */
function parseMemberBirthDate(data) {
    const keys = [
        "DATA_NASCIMENTO",
        "dataNascimento",
        "birthDate",
        "nascimento",
        "data_nascimento",
        "dtNascimento",
        "dataNasc",
    ];
    let raw;
    for (const k of keys) {
        if (data[k] != null) {
            raw = data[k];
            break;
        }
    }
    if (raw == null)
        return null;
    if (raw instanceof admin.firestore.Timestamp) {
        return raw.toDate();
    }
    if (typeof raw === "object" && raw !== null && "toDate" in raw && typeof raw.toDate === "function") {
        try {
            return raw.toDate();
        }
        catch (_) {
            return null;
        }
    }
    if (typeof raw === "string") {
        const t = raw.trim();
        if (!t)
            return null;
        const br = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})/.exec(t);
        if (br) {
            const day = parseInt(br[1], 10);
            const month = parseInt(br[2], 10);
            const year = parseInt(br[3], 10);
            if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
                return new Date(year, month - 1, day);
            }
        }
        const iso = Date.parse(t.length >= 10 ? t.slice(0, 10) : t);
        if (!Number.isNaN(iso))
            return new Date(iso);
    }
    return null;
}
/**
 * Todo dia 8h (SP): push no tópico `igreja_{tenantId}` com aniversariantes do dia (todos os usuários inscritos no tópico).
 */
exports.dailyBirthdayTopicPush = functions
    .region("us-central1")
    .pubsub.schedule("0 8 * * *")
    .timeZone(TZ_BR)
    .onRun(async () => {
    const now = new Date();
    const todaySp = ymdStringInTz(now, TZ_BR);
    const parts = todaySp.split("-").map((v) => parseInt(v, 10));
    const monthToday = parts[1];
    const dayToday = parts[2];
    if (!monthToday || !dayToday)
        return null;
    const churches = await db.collection("igrejas").get();
    let pushes = 0;
    for (const ch of churches.docs) {
        const tenantId = ch.id;
        try {
            const stateRef = db
                .collection("igrejas")
                .doc(tenantId)
                .collection("internal_notif_state")
                .doc("daily_birthday_topic");
            const st = await stateRef.get();
            const last = String(st.data()?.lastSentYmd || "").trim();
            if (last === todaySp)
                continue;
            const names = [];
            const birthdayEmailRecipients = [];
            const col = db.collection("igrejas").doc(tenantId).collection("membros");
            let lastDoc = null;
            for (;;) {
                const base = col
                    .orderBy(admin.firestore.FieldPath.documentId())
                    .limit(500);
                const membros = lastDoc
                    ? await base.startAfter(lastDoc).get()
                    : await base.get();
                if (membros.empty)
                    break;
                for (const doc of membros.docs) {
                    const d = doc.data() || {};
                    const status = String(d.STATUS || d.status || "")
                        .trim()
                        .toLowerCase();
                    if (status.includes("inativ") || status.includes("bloq"))
                        continue;
                    const bd = parseMemberBirthDate(d);
                    if (!bd)
                        continue;
                    if (bd.getMonth() + 1 !== monthToday || bd.getDate() !== dayToday) {
                        continue;
                    }
                    const full = String(d.NOME_COMPLETO || d.nome || "").trim();
                    const first = (full.split(/\s+/)[0] || "Irmão(ã)").replace(/,$/, "");
                    names.push(first || "Irmão(ã)");
                    const em = String(d.EMAIL || d.email || "")
                        .trim()
                        .toLowerCase();
                    if (em.includes("@")) {
                        const displayName = full || first || "Irmão(ã)";
                        birthdayEmailRecipients.push({ email: em, displayName });
                    }
                }
                lastDoc = membros.docs[membros.docs.length - 1];
                if (membros.docs.length < 500)
                    break;
            }
            if (names.length === 0) {
                await stateRef.set({ lastSentYmd: todaySp, skippedEmpty: true, at: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
                continue;
            }
            const body = names.length === 1
                ? `Hoje é aniversário de ${names[0]}. Parabenize com carinho!`
                : `Aniversariantes de hoje: ${names.slice(0, 8).join(", ")}${names.length > 8 ? "…" : ""}.`;
            const bodyOut = body.length > 200 ? `${body.slice(0, 197)}…` : body;
            await admin.messaging().send({
                topic: `igreja_${tenantId}`,
                notification: {
                    title: "Aniversariantes de hoje",
                    body: bodyOut,
                },
                data: {
                    tenantId,
                    type: "birthday_daily",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
            });
            let birthdayEmailsSent = 0;
            try {
                for (const r of birthdayEmailRecipients) {
                    const { subject, html } = (0, memberNotificationEmail_1.buildAniversarianteEmail)({
                        nomeDestinatario: r.displayName,
                    });
                    const ok = await (0, memberNotificationEmail_1.sendGestaoYahwehHtmlEmail)({ to: r.email, subject, html });
                    if (ok)
                        birthdayEmailsSent += 1;
                }
            }
            catch (e) {
                functions.logger.error("dailyBirthdayTopicPush email", { tenantId, e });
            }
            functions.logger.info("dailyBirthdayTopicPush emails", { tenantId, birthdayEmailsSent });
            await db.collection("igrejas").doc(tenantId).collection("notificacoes").add({
                type: "aniversariantes_dia",
                title: "Aniversariantes de hoje",
                body,
                names,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            await stateRef.set({
                lastSentYmd: todaySp,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                count: names.length,
            }, { merge: true });
            pushes += 1;
        }
        catch (e) {
            functions.logger.error("dailyBirthdayTopicPush", { tenantId, e });
        }
    }
    functions.logger.info("dailyBirthdayTopicPush done", { todaySp, pushes });
    return null;
});
/**
 * Legado: antes lembrava “amanhã” a todos os escalados. Substituído por
 * [rollingScaleRemindersConfirmed] (~24h e ~1h antes do horário, só quem confirmou).
 */
exports.dayBeforeScaleReminder = functions
    .region("us-central1")
    .pubsub.schedule("15 8 * * *")
    .timeZone(TZ_BR)
    .onRun(async () => {
    functions.logger.info("dayBeforeScaleReminder: no-op — usar rollingScaleRemindersConfirmed (confirmados, 24h e 1h).");
    return null;
});
function confirmedScheduleCpfsForReminders(d) {
    const rawList = d.memberCpfs || [];
    const digitsList = rawList
        .map((v) => String(v).replace(/\D/g, ""))
        .filter((c) => c.length === 11);
    if (!digitsList.length)
        return [];
    const conf = (d.confirmations || {});
    const out = [];
    for (const norm of digitsList) {
        let st = "";
        for (const [k, v] of Object.entries(conf)) {
            if (String(k).replace(/\D/g, "") === norm) {
                st = String(v || "").trim();
                break;
            }
        }
        if (st === "confirmado") {
            out.push(norm);
        }
    }
    return out;
}
/** Instante UTC aproximado do início da escala (data do doc + hora em BRT, UTC-3 fixo). */
function eventUtcMsSp(dateTs, timeStr) {
    const d = dateTs.toDate();
    const ymd = ymdStringInTz(d, TZ_BR);
    const parts = ymd.split("-").map((x) => parseInt(x, 10));
    if (parts.length !== 3 || parts.some((n) => Number.isNaN(n)))
        return null;
    const [y, mo, da] = parts;
    const m = /^(\d{1,2}):(\d{2})/.exec(String(timeStr || "").trim());
    const hh = m ? Math.min(23, Math.max(0, parseInt(m[1], 10))) : 19;
    const mm = m ? Math.min(59, Math.max(0, parseInt(m[2], 10))) : 0;
    return Date.UTC(y, mo - 1, da, hh + 3, mm, 0, 0);
}
/**
 * A cada 10 min: push para quem está com status "confirmado" na escala,
 * na janela ~24h antes ou ~1h antes do horário combinado (fuso SP).
 */
exports.rollingScaleRemindersConfirmed = functions
    .region("us-central1")
    .pubsub.schedule("*/10 * * * *")
    .timeZone(TZ_BR)
    .onRun(async () => {
    const nowMs = Date.now();
    const from = admin.firestore.Timestamp.fromMillis(nowMs - 2 * 60 * 60 * 1000);
    const to = admin.firestore.Timestamp.fromMillis(nowMs + 28 * 60 * 60 * 1000);
    const tenants = await db.collection("igrejas").get();
    let pushCount = 0;
    for (const t of tenants.docs) {
        const tenantId = t.id;
        try {
            const escSnap = await db
                .collection("igrejas")
                .doc(tenantId)
                .collection("escalas")
                .where("date", ">=", from)
                .where("date", "<=", to)
                .get();
            for (const doc of escSnap.docs) {
                const d = doc.data() || {};
                const ts = d.date;
                if (!ts || typeof ts.toDate !== "function")
                    continue;
                const timeStr = String(d.time || "19:00").trim();
                const evtMs = eventUtcMsSp(ts, timeStr);
                if (evtMs == null)
                    continue;
                const msUntil = evtMs - nowMs;
                if (msUntil < 0)
                    continue;
                const cpfs = confirmedScheduleCpfsForReminders(d);
                if (!cpfs.length)
                    continue;
                const w24a = 22 * 3600000;
                const w24b = 26 * 3600000;
                const w1a = 50 * 60000;
                const w1b = 75 * 60000;
                const send24 = d.scaleReminder24hSent !== true && msUntil >= w24a && msUntil <= w24b;
                const send1 = d.scaleReminder1hSent !== true && msUntil >= w1a && msUntil <= w1b;
                if (!send24 && !send1)
                    continue;
                const dept = String(d.departmentName || "").trim();
                const titleStr = String(d.title || "Escala").trim();
                const dateStr = formatDatePtBr(ts.toDate());
                const messages = [];
                for (const cpf of cpfs) {
                    const tokens = await collectFcmTokensForCpfs(tenantId, [cpf]);
                    if (!tokens.length)
                        continue;
                    const nome = await firstNameForCpf(tenantId, cpf);
                    if (send24) {
                        const body = `${nome}, em cerca de 24h você tem escala confirmada (${dateStr}${timeStr ? ` às ${timeStr}` : ""})${dept ? ` — ${dept}` : ""}`
                            .replace(/\s+/g, " ")
                            .trim()
                            .slice(0, 220);
                        for (const token of tokens) {
                            messages.push({
                                token,
                                notification: { title: "Lembrete: sua escala", body },
                                data: {
                                    tenantId,
                                    type: "escala_lembrete_24h",
                                    scheduleId: doc.id,
                                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                                },
                                android: { priority: "high" },
                                apns: { payload: { aps: { sound: "default" } } },
                            });
                        }
                    }
                    if (send1) {
                        const body = `${nome}, sua escala confirmada começa em cerca de 1 hora${timeStr ? ` (${timeStr})` : ""}${dept ? ` — ${dept}` : ""}${titleStr ? ` · ${titleStr}` : ""}`
                            .replace(/\s+/g, " ")
                            .trim()
                            .slice(0, 220);
                        for (const token of tokens) {
                            messages.push({
                                token,
                                notification: { title: "Escala em 1 hora", body },
                                data: {
                                    tenantId,
                                    type: "escala_lembrete_1h",
                                    scheduleId: doc.id,
                                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                                },
                                android: { priority: "high" },
                                apns: { payload: { aps: { sound: "default" } } },
                            });
                        }
                    }
                }
                if (messages.length) {
                    await sendEachInBatches(messages);
                    pushCount += messages.length;
                }
                const upd = {};
                if (send24) {
                    upd.scaleReminder24hSent = true;
                }
                if (send1) {
                    upd.scaleReminder1hSent = true;
                }
                await doc.ref.set(upd, { merge: true });
            }
        }
        catch (e) {
            functions.logger.error("rollingScaleRemindersConfirmed tenant", { tenantId, e });
        }
    }
    functions.logger.info("rollingScaleRemindersConfirmed done", { pushCount });
    return null;
});
/**
 * A cada hora (SP): devocional no horário configurado pela igreja.
 */
exports.hourlyDevotionalBroadcast = functions
    .region("us-central1")
    .pubsub.schedule("5 * * * *")
    .timeZone(TZ_BR)
    .onRun(async () => {
    const now = new Date();
    const hourSp = parseInt(new Intl.DateTimeFormat("en-GB", {
        timeZone: TZ_BR,
        hour: "2-digit",
        hour12: false,
    })
        .formatToParts(now)
        .find((p) => p.type === "hour")?.value || "0", 10);
    const todaySp = ymdStringInTz(now, TZ_BR);
    const tenants = await db.collection("igrejas").get();
    for (const t of tenants.docs) {
        const tenantId = t.id;
        try {
            const cfgSnap = await db
                .collection("igrejas")
                .doc(tenantId)
                .collection("config")
                .doc("comunicacao")
                .get();
            if (!cfgSnap.exists)
                continue;
            const c = cfgSnap.data() || {};
            if (c.devocionalEnabled !== true)
                continue;
            const hourCfg = Number(c.devocionalHora ?? 7);
            if (!Number.isFinite(hourCfg) || hourCfg < 0 || hourCfg > 23)
                continue;
            if (hourSp !== hourCfg)
                continue;
            const last = String(c.devocionalUltimoEnvioDia || "").trim();
            if (last === todaySp)
                continue;
            const titulo = String(c.devocionalTitulo || "Bom dia").trim() || "Bom dia";
            const texto = String(c.devocionalTexto || "").trim();
            const ref = String(c.devocionalReferencia || "").trim();
            const body = [texto, ref].filter((x) => x.length > 0).join("\n").trim();
            if (!body)
                continue;
            await admin.messaging().send({
                topic: `igreja_${tenantId}`,
                notification: { title: titulo, body: body.length > 180 ? `${body.slice(0, 177)}...` : body },
                data: {
                    tenantId,
                    type: "devocional",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
            });
            await db.collection("igrejas").doc(tenantId).collection("devocional_envios").add({
                titulo,
                texto,
                referencia: ref,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                scheduledHour: hourCfg,
                daySp: todaySp,
                source: "scheduled",
                topic: `igreja_${tenantId}`,
                resendCount: 0,
            });
            await cfgSnap.ref.set({ devocionalUltimoEnvioDia: todaySp, devocionalUltimoEnvioAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        }
        catch (e) {
            functions.logger.error("hourlyDevotionalBroadcast", { tenantId, e });
        }
    }
    return null;
});
// ── Troca de escala entre membros (convite → aceite → notificação ao líder) ──
function normCpfDigitsSwap(raw) {
    return String(raw || "").replace(/\D/g, "");
}
function remapCpfKeyedMapSwap(oldMap, newCpfs) {
    const norm = (s) => s.replace(/\D/g, "");
    const out = {};
    for (const newCpf of newCpfs) {
        const n = norm(newCpf);
        for (const [k, v] of Object.entries(oldMap)) {
            if (norm(String(k)) === n) {
                out[newCpf] = v;
                break;
            }
        }
    }
    return out;
}
async function fullNameForCpfSwap(tenantId, cpfDigits) {
    const col = db.collection("igrejas").doc(tenantId).collection("membros");
    const digits = normCpfDigitsSwap(cpfDigits);
    if (digits.length !== 11)
        return "Irmão(ã)";
    let snap = await col.doc(digits).get();
    if (!snap.exists) {
        const q = await col.where("CPF", "==", digits).limit(1).get();
        snap = q.docs[0] || snap;
    }
    if (!snap.exists)
        return "Irmão(ã)";
    const full = String((snap.data() || {}).NOME_COMPLETO || (snap.data() || {}).nome || "").trim();
    return full || "Irmão(ã)";
}
/**
 * O substituto aceita ou recusa o convite. Se aceitar, a escala é atualizada no Firestore
 * e o tópico do departamento recebe push para o líder.
 */
exports.respondScheduleSwap = functions.region("us-central1").https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const trocaId = String(data?.trocaId || "").trim();
    const accept = Boolean(data?.accept);
    if (!tenantId || !trocaId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e trocaId são obrigatórios.");
    }
    const myCpf = await userCpfDigitsFromUid(context.auth.uid);
    if (myCpf.length !== 11) {
        throw new functions.https.HttpsError("failed-precondition", "CPF não vinculado ao usuário.");
    }
    const trocaRef = db.collection("igrejas").doc(tenantId).collection("escala_trocas").doc(trocaId);
    const trocaSnap = await trocaRef.get();
    if (!trocaSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Pedido não encontrado.");
    }
    const t = trocaSnap.data() || {};
    const status = String(t.status || "").trim();
    if (status !== "pendente_alvo") {
        throw new functions.https.HttpsError("failed-precondition", "Este pedido não está aguardando sua resposta.");
    }
    const alvo = normCpfDigitsSwap(String(t.alvoCpf || ""));
    if (alvo !== myCpf) {
        throw new functions.https.HttpsError("permission-denied", "Este convite não é para você.");
    }
    const solicitante = normCpfDigitsSwap(String(t.solicitanteCpf || ""));
    if (solicitante.length !== 11) {
        throw new functions.https.HttpsError("failed-precondition", "Dados do pedido inválidos.");
    }
    if (!accept) {
        await trocaRef.update({
            status: "recusada_alvo",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const solTokens = await collectFcmTokensForCpfs(tenantId, [solicitante]);
        const declBody = `${await firstNameForCpf(tenantId, alvo)} recusou o pedido de troca de escala.`
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 200);
        const declMsgs = solTokens.map((token) => ({
            token,
            notification: { title: "Troca de escala", body: declBody },
            data: {
                tenantId,
                type: "escala_troca_recusada",
                trocaId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            android: { priority: "high" },
        }));
        await sendEachInBatches(declMsgs);
        return { ok: true, accepted: false };
    }
    const escalaId = String(t.escalaId || "").trim();
    const deptId = String(t.departmentId || "").trim();
    if (!escalaId || !deptId) {
        throw new functions.https.HttpsError("failed-precondition", "Pedido incompleto.");
    }
    const escRef = db.collection("igrejas").doc(tenantId).collection("escalas").doc(escalaId);
    const alvoNomeResolved = await fullNameForCpfSwap(tenantId, alvo);
    await db.runTransaction(async (tx) => {
        const tFresh = await tx.get(trocaRef);
        if (!tFresh.exists) {
            throw new functions.https.HttpsError("not-found", "Pedido removido.");
        }
        const td = tFresh.data() || {};
        if (String(td.status || "") !== "pendente_alvo") {
            throw new functions.https.HttpsError("failed-precondition", "Pedido já foi respondido.");
        }
        const escSnap = await tx.get(escRef);
        if (!escSnap.exists) {
            throw new functions.https.HttpsError("not-found", "Escala não encontrada.");
        }
        const ed = escSnap.data() || {};
        const cpfs = (ed.memberCpfs || []).map((e) => String(e));
        const names = (ed.memberNames || []).map((e) => String(e));
        const solFresh = normCpfDigitsSwap(String(td.solicitanteCpf || ""));
        const alvoFresh = normCpfDigitsSwap(String(td.alvoCpf || ""));
        let idx = -1;
        for (let i = 0; i < cpfs.length; i++) {
            if (normCpfDigitsSwap(cpfs[i]) === solFresh) {
                idx = i;
                break;
            }
        }
        if (idx < 0) {
            throw new functions.https.HttpsError("failed-precondition", "O solicitante não está mais nesta escala.");
        }
        for (const c of cpfs) {
            if (normCpfDigitsSwap(c) === alvoFresh) {
                throw new functions.https.HttpsError("failed-precondition", "O substituto já está nesta escala.");
            }
        }
        const newCpfs = [...cpfs];
        const newNames = [...names];
        newCpfs[idx] = alvoFresh;
        while (newNames.length < newCpfs.length)
            newNames.push("");
        newNames[idx] = alvoNomeResolved;
        const oldConf = { ...(ed.confirmations || {}) };
        const oldUnav = { ...(ed.unavailabilityReasons || {}) };
        delete oldConf[cpfs[idx]];
        delete oldUnav[cpfs[idx]];
        tx.update(escRef, {
            memberCpfs: newCpfs,
            memberNames: newNames,
            confirmations: remapCpfKeyedMapSwap(oldConf, newCpfs),
            unavailabilityReasons: remapCpfKeyedMapSwap(oldUnav, newCpfs),
            updatedAt: admin.firestore.Timestamp.now(),
        });
        tx.update(trocaRef, {
            status: "concluida",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
    const nomeSol = await fullNameForCpfSwap(tenantId, solicitante);
    const nomeAlvo = await fullNameForCpfSwap(tenantId, alvo);
    const leaderBody = `Escala alterada: ${nomeSol} trocou com ${nomeAlvo}.`
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 220);
    try {
        await admin.messaging().send({
            topic: `dept_${deptId}`,
            notification: {
                title: "Escala alterada",
                body: leaderBody,
            },
            data: {
                tenantId,
                type: "escala_troca_concluida",
                scheduleId: escalaId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            android: { priority: "high" },
        });
    }
    catch (e) {
        functions.logger.error("respondScheduleSwap FCM dept topic", { tenantId, deptId, e });
    }
    return { ok: true, accepted: true };
});
/** Ao criar convite pendente_alvo, notifica o substituto por FCM. */
exports.onEscalaTrocaInviteTarget = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/escala_trocas/{trocaId}")
    .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId;
    const d = snap.data() || {};
    if (String(d.status || "").trim() !== "pendente_alvo")
        return null;
    const alvo = normCpfDigitsSwap(String(d.alvoCpf || ""));
    const sol = normCpfDigitsSwap(String(d.solicitanteCpf || ""));
    if (alvo.length !== 11 || sol.length !== 11)
        return null;
    const solPrimeiro = await firstNameForCpf(tenantId, sol);
    const titleStr = String(d.escalaTitle || "Escala").trim();
    const dateStr = String(d.escalaDateLabel || "").trim();
    const body = `${solPrimeiro} pediu para você assumir a escala${dateStr ? ` (${dateStr})` : ""}${titleStr ? ` — ${titleStr}` : ""}. Abra o app em Minhas Escalas para aceitar ou recusar.`
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 220);
    const tokens = await collectFcmTokensForCpfs(tenantId, [alvo]);
    if (!tokens.length)
        return null;
    const msgs = tokens.map((token) => ({
        token,
        notification: { title: "Pedido de troca de escala", body },
        data: {
            tenantId,
            type: "escala_troca_convite",
            trocaId: context.params.trocaId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: { priority: "high" },
    }));
    await sendEachInBatches(msgs);
    return null;
});
//# sourceMappingURL=pastoralComms.js.map