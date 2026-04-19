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
exports.resolveCpfToChurchPublicFinal = exports.resolveCpfToChurchPublicHttp = exports.seedPublicCpfIndex = exports.reportSecurityEvent = exports.bootstrapAdmin = exports.getAdminCheck = exports.getUserProfile = exports.seedFrotaMasterHttp = exports.seedFrotaMaster = exports.migrateFrotaToFrotasveiculo = exports.corrigirBancoFrota = exports.cleanFrotaFromDefault = exports.ensureBrasilParaCristoAccess = exports.getMemberEmailForReset = exports.bulkEnsureMembersAuth = exports.setMemberApproved = exports.setMemberPassword = exports.recreateMemberAuthForNewEmail = exports.alignMemberDocToAuthUid = exports.createMemberLoginFromPublic = exports.createMemberAuthAccountForGestor = exports.syncGestorBrasilParaCristo = exports.seedGestorBrasilParaCristo = exports.createChurchForOnboardingGestor = exports.registerGestorProfile = exports.createChurchAndGestorWithGoogle = exports.consumeUserSignupInvite = exports.getUserSignupInviteInfo = exports.createUserSignupInvite = exports.upsertTenantUser = exports.setUserActive = exports.setUserRole = exports.resolveCpfToEmail = exports.syncMemberRoleClaims = exports.repairMyChurchBinding = exports.resolveEmailToChurchPublic = exports.mpWebhook = exports.mercadoPagoWebhook = exports.createMpPixPayment = exports.createMpPreapproval = exports.backupDailyToGcs = exports.testDriveWriteForChurch = exports.getChurchStorageUsage = exports.archiveChurchMediaNow = exports.archiveChurchMediaToDrive = exports.backupDailyToDrive = exports.ensureGlobalDownloads = exports.ensureDriveFolders = exports.onTenantCreate = exports.resolveCpfToChurchPublic = void 0;
exports.pruneContribuicoesDizimoHistorico = exports.createChurchDonationPreference = exports.createChurchDonationPix = exports.ensureChurchTreasuryAccountPresets = exports.saveChurchMercadoPagoCredentials = exports.scheduledFornecedorAgendaReminders = exports.onNovoEventoNoticiaPush = exports.onNovoAvisoMuralPush = exports.onIgrejaPatrimonioDeleteCleanupStorage = exports.onIgrejaNoticiaDeleteCleanupStorage = exports.onIgrejaMembroDeleteCleanupStorage = exports.hourlyDevotionalBroadcast = exports.rollingScaleRemindersConfirmed = exports.dayBeforeScaleReminder = exports.dailyBirthdayTopicPush = exports.onEscalaTrocaInviteTarget = exports.respondScheduleSwap = exports.onEscalaImpedimentoNotifyLeaders = exports.notifySchedulePublished = exports.deleteDevotionalEnvio = exports.resendDevotionalEnvio = exports.resendPastoralMessage = exports.updatePastoralMessage = exports.archivePastoralMessage = exports.sendSegmentedPush = exports.processarCertificadosLote = exports.gerarCertificadosEmLote = exports.shareEvento = exports.recordDomainDailyHit = exports.generateThumbnail = exports.onNewMemberLegacy = exports.onNewMember = exports.validateCarteirinhaPublic = exports.migrateAllIgrejasMembersToMembros = exports.scheduledGerarReceitasRecorrentesPendentes = exports.scheduledMigrateIgrejaMembersToMembros = exports.ensureMigrateMembersToMembros = exports.migrateMembersFull = exports.syncMembersFromUsers = exports.autoGenerateEvents = exports.onScheduleCreate = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const churchWelcomeSeed_1 = require("./churchWelcomeSeed");
const publicSignupEmail_1 = require("./publicSignupEmail");
const pushNovoConteudo_1 = require("./pushNovoConteudo");
const receitasRecorrentesScheduled_1 = require("./receitasRecorrentesScheduled");
const churchMercadoPago_1 = require("./churchMercadoPago");
admin.initializeApp();
const db = admin.firestore();
/** Banco Firestore separado para frotas (frotasveiculo). */
const dbFrota = (0, firestore_1.getFirestore)(admin.app(), "frotasveiculo");
const DRIVE_ROOT_ID_PARAM = (0, params_1.defineString)("DRIVE_ROOT_ID", { default: "" });
const DRIVE_CHURCH_ROOT_ID_PARAM = (0, params_1.defineString)("DRIVE_CHURCH_ROOT_ID", { default: "" });
const DRIVE_FLEET_ROOT_ID_PARAM = (0, params_1.defineString)("DRIVE_FLEET_ROOT_ID", { default: "" });
const MEDIA_RETENTION_DAYS_PARAM = (0, params_1.defineString)("MEDIA_RETENTION_DAYS", { default: "15" });
const GCS_BACKUP_BUCKET_PARAM = (0, params_1.defineString)("GCS_BACKUP_BUCKET", { default: "" });
const MP_ACCESS_TOKEN_PARAM = (0, params_1.defineString)("MP_ACCESS_TOKEN", { default: "" });
const MP_WEBHOOK_SECRET_PARAM = (0, params_1.defineString)("MP_WEBHOOK_SECRET", { default: "" });
const MP_WEBHOOK_URL_PARAM = (0, params_1.defineString)("MP_WEBHOOK_URL", { default: "" });
/** Chave para o usuário virar ADMIN pelo painel (modal "Virar ADMIN agora"). Defina no Google Cloud Console > Functions > bootstrapAdmin > Variáveis de ambiente: ADMIN_SETUP_KEY. */
const ADMIN_SETUP_KEY_PARAM = (0, params_1.defineString)("ADMIN_SETUP_KEY", { default: "" });
function parseDriveFolderId(rawValue) {
    const raw = String(rawValue || "").trim();
    if (raw.includes("folders/")) {
        const parts = raw.split("folders/");
        return parts[parts.length - 1].split("?")[0];
    }
    return raw;
}
function getDriveRootId() {
    return parseDriveFolderId(String(DRIVE_ROOT_ID_PARAM.value() || ""));
}
function getChurchDriveRootId() {
    const scoped = parseDriveFolderId(String(DRIVE_CHURCH_ROOT_ID_PARAM.value() || ""));
    return scoped || getDriveRootId();
}
function getFleetDriveRootId() {
    return parseDriveFolderId(String(DRIVE_FLEET_ROOT_ID_PARAM.value() || ""));
}
function getMediaRetentionDays() {
    const raw = String(MEDIA_RETENTION_DAYS_PARAM.value() || "15").trim();
    const n = parseInt(raw, 10);
    if (!Number.isFinite(n) || n < 1)
        return 15;
    return n;
}
function getGcsBackupBucket() {
    return String(GCS_BACKUP_BUCKET_PARAM.value() || "").trim();
}
function getMpAccessToken() {
    return String(MP_ACCESS_TOKEN_PARAM.value() || "").trim();
}
/** Token do Mercado Pago: env MP_ACCESS_TOKEN ou Firestore config/mercado_pago (painel admin). */
async function getMpToken() {
    const fromEnv = getMpAccessToken();
    if (fromEnv)
        return fromEnv;
    const snap = await db.collection("config").doc("mercado_pago").get();
    const data = snap.exists ? snap.data() : null;
    if (!data)
        throw new Error("Mercado Pago: configure Access Token no painel admin (config/mercado_pago) ou em MP_ACCESS_TOKEN");
    const mode = String(data.mode || "production").toLowerCase();
    const token = mode === "test" ? data.accessTokenTest : data.accessToken;
    const out = String(token || "").trim();
    if (!out)
        throw new Error("Mercado Pago: accessToken (ou accessTokenTest) nao definido em config/mercado_pago");
    return out;
}
function getMpWebhookSecret() {
    return String(MP_WEBHOOK_SECRET_PARAM.value() || "").trim();
}
function getMpWebhookUrl() {
    return String(MP_WEBHOOK_URL_PARAM.value() || "").trim();
}
/** Documento config/mercado_pago (credenciais + URLs editáveis no painel master). */
async function getMercadoPagoConfig() {
    try {
        const snap = await db.collection("config").doc("mercado_pago").get();
        if (!snap.exists)
            return null;
        return (snap.data() || null);
    }
    catch {
        return null;
    }
}
/**
 * URL de notificação: env MP_WEBHOOK_URL > Firestore webhookUrl > função mpWebhook (alias) > mercadoPagoWebhook.
 */
async function resolveMpNotificationUrl() {
    const fromEnv = getMpWebhookUrl();
    if (fromEnv)
        return fromEnv;
    const cfg = await getMercadoPagoConfig();
    const fromDb = String(cfg?.webhookUrl || cfg?.webhook_url || "").trim();
    if (fromDb)
        return fromDb;
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    if (!projectId)
        return "";
    return `https://us-central1-${projectId}.cloudfunctions.net/mpWebhook`;
}
/**
 * URL para onde o MP redireciona após o fluxo (obrigatório na API atual — erro "back_url is required").
 * Firestore: backUrl / back_url / publicAppUrl (só domínio) ou env MP_BACK_URL.
 */
async function resolveMpBackUrl() {
    const fromEnv = String(process.env.MP_BACK_URL || "").trim();
    if (fromEnv)
        return fromEnv;
    const cfg = await getMercadoPagoConfig();
    const direct = String(cfg?.backUrl || cfg?.back_url || cfg?.returnUrl || "").trim();
    if (direct)
        return direct;
    const base = String(cfg?.publicAppUrl || cfg?.public_app_url || cfg?.appUrl || "").trim().replace(/\/+$/, "");
    if (base && (base.startsWith("http://") || base.startsWith("https://"))) {
        return `${base}/planos`;
    }
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    if (projectId) {
        const slug = projectId.replace(/_/g, "-");
        return `https://${slug}.web.app/planos`;
    }
    return "https://gestaoyahweh.com.br/planos";
}
function getFetch() {
    const f = globalThis.fetch;
    if (!f) {
        throw new Error("fetch nao disponivel no runtime");
    }
    return f;
}
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
async function isAdminPanelActor(uid, tokenRole, email) {
    const role = await resolveRoleFromTokenOrDb(uid, tokenRole);
    if (isPrivilegedRole(role))
        return true;
    if (email === "raihom@gmail.com")
        return true;
    try {
        const adminDoc = await db.collection("admins").doc(uid).get();
        if (adminDoc.exists)
            return true;
    }
    catch (_) { }
    return false;
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
async function getDrive() {
    const { google } = await Promise.resolve().then(() => __importStar(require("googleapis")));
    const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/drive"],
    });
    return google.drive({ version: "v3", auth });
}
async function findFolder(drive, parentId, name) {
    const res = await drive.files.list({
        q: [
            `'${parentId}' in parents`,
            `name='${name}'`,
            "mimeType='application/vnd.google-apps.folder'",
            "trashed=false",
        ].join(" and "),
        fields: "files(id, name)",
        pageSize: 1,
    });
    const files = res.data.files || [];
    return files.length ? files[0].id : null;
}
async function createFolder(drive, parentId, name, description) {
    const res = await drive.files.create({
        requestBody: {
            name,
            mimeType: "application/vnd.google-apps.folder",
            parents: [parentId],
            description,
        },
        fields: "id",
    });
    return res.data.id;
}
async function findOrCreateFolder(drive, parentId, name, description) {
    const found = await findFolder(drive, parentId, name);
    if (found)
        return found;
    return createFolder(drive, parentId, name, description);
}
function ymFolder(date) {
    const y = date.getFullYear().toString();
    const m = (date.getMonth() + 1).toString().padStart(2, "0");
    return `${y}-${m}`;
}
function ymdFolder(date) {
    const y = date.getFullYear().toString();
    const m = (date.getMonth() + 1).toString().padStart(2, "0");
    const d = date.getDate().toString().padStart(2, "0");
    return `${y}-${m}-${d}`;
}
function toDateSafe(input) {
    try {
        if (!input)
            return null;
        if (input instanceof admin.firestore.Timestamp)
            return input.toDate();
        if (input && typeof input.toDate === "function") {
            const d = input.toDate();
            return d instanceof Date && !Number.isNaN(d.getTime()) ? d : null;
        }
        if (input instanceof Date)
            return Number.isNaN(input.getTime()) ? null : input;
        const d = new Date(input);
        return Number.isNaN(d.getTime()) ? null : d;
    }
    catch (_) {
        return null;
    }
}
function storagePathFromUrl(rawUrl) {
    const url = String(rawUrl || "").trim();
    if (!url)
        return null;
    if (url.startsWith("gs://")) {
        const noScheme = url.slice(5);
        const slash = noScheme.indexOf("/");
        if (slash < 0)
            return null;
        return decodeURIComponent(noScheme.slice(slash + 1));
    }
    try {
        const u = new URL(url);
        const host = (u.host || "").toLowerCase();
        if (host.includes("firebasestorage.googleapis.com") || host.includes("storage.googleapis.com") || host.includes("firebasestorage.app")) {
            const marker = "/o/";
            const idx = u.pathname.indexOf(marker);
            if (idx >= 0) {
                const encoded = u.pathname.slice(idx + marker.length);
                return decodeURIComponent(encoded.replace(/^\/+/, ""));
            }
        }
    }
    catch (_) {
        return null;
    }
    return null;
}
async function getTenantFolderLabel(tenantId) {
    const tenantSnap = await db.collection("tenants").doc(tenantId).get();
    const tData = tenantSnap.data() || {};
    const createdByCpf = String(tData.createdByCpf || tData.ownerCpf || tData.gestorCpf || "").trim();
    const folderLabel = createdByCpf ? `${tenantId}_${createdByCpf}` : tenantId;
    const description = createdByCpf ? `createdByCpf: ${createdByCpf}` : undefined;
    return { folderLabel, description };
}
async function ensureTenantMediaArchiveFolder(tenantId, when) {
    const churchRootId = getChurchDriveRootId();
    if (!churchRootId || String(churchRootId).trim() === "") {
        throw new Error("drive.church_root_id nao configurado: defina DRIVE_CHURCH_ROOT_ID nas variaveis da Function");
    }
    const drive = await getDrive();
    const churchesRoot = await findOrCreateFolder(drive, churchRootId, "Igrejas");
    const { folderLabel, description } = await getTenantFolderLabel(tenantId);
    const tenantFolder = await findOrCreateFolder(drive, churchesRoot, folderLabel, description);
    const archiveRoot = await findOrCreateFolder(drive, tenantFolder, "midias_arquivadas");
    const monthFolder = await findOrCreateFolder(drive, archiveRoot, ymFolder(when));
    return { drive, monthFolder };
}
/** Retorna tamanho total em bytes de um folder no Drive (recursivo, apenas arquivos). */
async function getDriveFolderSizeRecursive(drive, folderId) {
    if (!folderId || String(folderId).trim() === "")
        return 0;
    let total = 0;
    let pageToken;
    const folderMime = "application/vnd.google-apps.folder";
    do {
        const res = await drive.files.list({
            q: `'${folderId}' in parents and trashed=false`,
            fields: "nextPageToken, files(id, name, mimeType, size)",
            pageSize: 100,
            pageToken: pageToken || undefined,
        });
        const files = res.data.files || [];
        pageToken = res.data.nextPageToken;
        for (const f of files) {
            if (f.mimeType === folderMime) {
                total += await getDriveFolderSizeRecursive(drive, f.id);
            }
            else {
                const sz = f.size;
                total += typeof sz === "string" ? parseInt(sz, 10) || 0 : (Number(sz) || 0);
            }
        }
    } while (pageToken);
    return total;
}
async function uploadBucketFileToDrive(drive, storagePath, parentFolderId) {
    if (!parentFolderId || String(parentFolderId).trim() === "") {
        throw new Error("uploadBucketFileToDrive: parentFolderId invalido");
    }
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
        throw new Error(`arquivo nao encontrado no Storage: ${storagePath}`);
    }
    const [meta] = await file.getMetadata();
    const mimeType = String(meta?.contentType || "application/octet-stream");
    const safeName = storagePath.split("/").pop() || `media_${Date.now()}`;
    let buffer;
    try {
        const [buf] = await file.download();
        buffer = buf;
    }
    catch (e) {
        throw new Error(`falha ao baixar do Storage (${storagePath}): ${e?.message || e}`);
    }
    let created;
    try {
        created = await drive.files.create({
            requestBody: {
                name: safeName,
                parents: [parentFolderId],
                description: `origem_storage: ${storagePath}`,
            },
            media: {
                mimeType,
                body: buffer,
            },
            fields: "id, webViewLink",
        });
    }
    catch (e) {
        throw new Error(`Drive: falha ao criar arquivo (${safeName}): ${e?.message || e}`);
    }
    const fileId = String(created?.data?.id || "");
    if (!fileId) {
        throw new Error("Drive: resposta sem id do arquivo criado");
    }
    try {
        await drive.permissions.create({
            fileId,
            requestBody: {
                type: "anyone",
                role: "reader",
            },
        });
    }
    catch (e) {
        console.warn("Drive: permissao anyone/reader nao aplicada (arquivo ja criado):", e?.message);
    }
    const webViewLink = String(created?.data?.webViewLink || `https://drive.google.com/file/d/${fileId}/view`);
    const directViewUrl = `https://drive.google.com/uc?export=view&id=${fileId}`;
    return { fileId, webViewLink, directViewUrl, name: safeName, mimeType };
}
async function ensureTenantDriveFolders(tenantId) {
    const driveRootId = getChurchDriveRootId();
    if (!driveRootId) {
        throw new Error("drive.root_id nao configurado");
    }
    const drive = await getDrive();
    const rootId = driveRootId;
    const churchesRoot = await findOrCreateFolder(drive, rootId, "Igrejas");
    const { folderLabel, description } = await getTenantFolderLabel(tenantId);
    const tenantFolder = await findOrCreateFolder(drive, churchesRoot, folderLabel, description);
    const monthFolder = await findOrCreateFolder(drive, tenantFolder, ymFolder(new Date()));
    const firestoreFolder = await findOrCreateFolder(drive, monthFolder, "firestore");
    const reportsFolder = await findOrCreateFolder(drive, monthFolder, "relatorios");
    const mediaFolder = await findOrCreateFolder(drive, monthFolder, "midias");
    const auditFolder = await findOrCreateFolder(drive, monthFolder, "auditoria");
    await db.collection("tenants").doc(tenantId).set({
        drive: {
            rootId,
            churchesRootId: churchesRoot,
            tenantFolderId: tenantFolder,
            monthFolderId: monthFolder,
            firestoreFolderId: firestoreFolder,
            reportsFolderId: reportsFolder,
            mediaFolderId: mediaFolder,
            auditFolderId: auditFolder,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    }, { merge: true });
    return { tenantFolder, monthFolder, firestoreFolder };
}
async function deleteFileByName(drive, parentId, name) {
    const res = await drive.files.list({
        q: [
            `'${parentId}' in parents`,
            `name='${name}'`,
            "trashed=false",
        ].join(" and "),
        fields: "files(id, name)",
        pageSize: 5,
    });
    const files = res.data.files || [];
    for (const f of files) {
        await drive.files.delete({ fileId: f.id });
    }
}
async function writeJsonFile(drive, folderId, name, data) {
    await deleteFileByName(drive, folderId, name);
    const media = {
        mimeType: "application/json",
        body: Buffer.from(JSON.stringify(data, null, 2)),
    };
    await drive.files.create({
        requestBody: {
            name,
            parents: [folderId],
        },
        media,
        fields: "id",
    });
}
function driveFolderUrl(id) {
    return `https://drive.google.com/drive/folders/${id}`;
}
function parseMpDate(raw) {
    if (!raw)
        return null;
    const dt = new Date(raw);
    if (Number.isNaN(dt.getTime()))
        return null;
    return admin.firestore.Timestamp.fromDate(dt);
}
function mapPaymentStatus(status) {
    const s = (status || "").toLowerCase();
    if (s === "approved" || s === "authorized")
        return "paid";
    if (s === "pending" || s === "in_process")
        return "pending";
    if (s === "cancelled" || s === "cancelled" || s === "rejected" || s === "charged_back")
        return "overdue";
    return "canceled";
}
function mapPreapprovalStatus(status) {
    const s = (status || "").toLowerCase();
    if (s === "authorized" || s === "active")
        return "paid";
    if (s === "pending")
        return "pending";
    if (s === "cancelled")
        return "canceled";
    return "overdue";
}
async function mpGet(path) {
    const accessToken = await getMpToken();
    const res = await getFetch()(`https://api.mercadopago.com${path}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
        },
    });
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`MP API error: ${res.status} ${text}`);
    }
    return res.json();
}
async function mpPost(path, body, extraHeaders) {
    const accessToken = await getMpToken();
    const headers = {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        ...extraHeaders,
    };
    const res = await getFetch()(`https://api.mercadopago.com${path}`, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
    });
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`MP API error: ${res.status} ${text}`);
    }
    return res.json();
}
async function upsertSubscription(tenantId, planId, status, trialEndsAt, extras) {
    const subQs = await db
        .collection("subscriptions")
        .where("igrejaId", "==", tenantId)
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();
    const payload = {
        igrejaId: tenantId,
        planId,
        status: status.toUpperCase(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (trialEndsAt)
        payload.trialEndsAt = trialEndsAt;
    else if (status.toUpperCase() === "ACTIVE") {
        payload.trialEndsAt = admin.firestore.FieldValue.delete();
    }
    if (extras?.nextChargeAt)
        payload.nextChargeAt = extras.nextChargeAt;
    if (extras?.lastPaymentAt)
        payload.lastPaymentAt = extras.lastPaymentAt;
    if (subQs.docs.length === 0) {
        await db.collection("subscriptions").add({
            ...payload,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    else {
        await subQs.docs[0].ref.set(payload, { merge: true });
    }
}
/** Vencimento da licença paga: +1 mês ou +1 ano (mesmo dia do mês quando possível). */
function computeLicensePeriodEnd(from, billingCycleRaw) {
    const cycle = (billingCycleRaw || "monthly").toLowerCase();
    const d = new Date(from.getTime());
    if (cycle === "annual" || cycle === "yearly") {
        d.setFullYear(d.getFullYear() + 1);
        return d;
    }
    d.setMonth(d.getMonth() + 1);
    return d;
}
function computeGraceBlockDate(from) {
    const d = new Date(from.getTime());
    d.setDate(d.getDate() + 3);
    return d;
}
/**
 * Atualiza cobrança/licença em `igrejas` e `tenants` (o app usa principalmente `igrejas`).
 * Pagamento aprovado: grava licenseExpiresAt / nextCharge conforme ciclo (mensal/anual) nos metadados do MP.
 */
async function updateTenantBilling(tenantId, billingStatus, extras) {
    const igRef = db.collection("igrejas").doc(tenantId);
    const tnRef = db.collection("tenants").doc(tenantId);
    const [igSnap, tnSnap] = await Promise.all([igRef.get(), tnRef.get()]);
    const igData = igSnap.data() || {};
    const tnData = tnSnap.data() || {};
    const metaPlan = String(extras.metadataPlanId || "").trim();
    const metaCycle = String(extras.billingCycle || "").trim().toLowerCase();
    const planIdRaw = metaPlan ||
        String(igData.planId || tnData.planId || igData.plano || tnData.plan || "inicial");
    const planId = planIdRaw.replace(/\s/g, "").toLowerCase() || "inicial";
    const licenseStatus = billingStatus === "paid"
        ? "active"
        : billingStatus === "pending"
            ? "trial"
            : "blocked";
    const subscriptionUiStatus = billingStatus === "paid"
        ? "ACTIVE"
        : billingStatus === "pending"
            ? "TRIAL"
            : "BLOCKED";
    let licenseExpiresAt;
    let dataVencimentoTs;
    let dataBloqueioTs;
    let nextChargeAtTs = extras.nextChargeAt || undefined;
    const approvedAt = extras.lastPaymentAt || admin.firestore.Timestamp.now();
    if (billingStatus === "paid") {
        const approvedDate = approvedAt.toDate();
        const cycle = metaCycle === "annual" ? "annual" : "monthly";
        const end = computeLicensePeriodEnd(approvedDate, cycle);
        licenseExpiresAt = admin.firestore.Timestamp.fromDate(end);
        dataVencimentoTs = licenseExpiresAt;
        dataBloqueioTs = admin.firestore.Timestamp.fromDate(computeGraceBlockDate(end));
        nextChargeAtTs = licenseExpiresAt;
    }
    else if (extras.nextChargeAt) {
        nextChargeAtTs = extras.nextChargeAt;
        dataVencimentoTs = extras.nextChargeAt;
        dataBloqueioTs = admin.firestore.Timestamp.fromDate(computeGraceBlockDate(extras.nextChargeAt.toDate()));
    }
    const licensePatch = {
        status: licenseStatus,
        active: billingStatus === "paid" || billingStatus === "pending",
        isFree: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (licenseExpiresAt) {
        licensePatch.expiresAt = licenseExpiresAt;
    }
    const billingPatch = {
        status: billingStatus,
        provider: "mercado_pago",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        subscriptionId: extras.subscriptionId || "",
        lastPaymentAt: extras.lastPaymentAt || null,
        nextChargeAt: nextChargeAtTs || null,
    };
    if (extras.mpPaymentId)
        billingPatch.mpPaymentId = extras.mpPaymentId;
    const rootPatch = {
        planId,
        plano: planId,
        billingCycle: metaCycle || igData.billingCycle || tnData.billingCycle || null,
        license: licensePatch,
        billing: billingPatch,
        status_assinatura: billingStatus === "paid"
            ? "active"
            : billingStatus === "pending"
                ? "trialing"
                : billingStatus === "overdue"
                    ? "overdue"
                    : "suspended",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (licenseExpiresAt) {
        rootPatch.licenseExpiresAt = licenseExpiresAt;
    }
    if (dataVencimentoTs)
        rootPatch.data_vencimento = dataVencimentoTs;
    if (dataBloqueioTs)
        rootPatch.data_bloqueio = dataBloqueioTs;
    await igRef.set(rootPatch, { merge: true });
    await tnRef.set(rootPatch, { merge: true });
    const pendingTrialEnds = igData.trialEndsAt || tnData.trialEndsAt || null;
    await upsertSubscription(tenantId, planId, subscriptionUiStatus, billingStatus === "pending" ? pendingTrialEnds : null, {
        nextChargeAt: nextChargeAtTs || extras.nextChargeAt,
        lastPaymentAt: extras.lastPaymentAt,
    });
}
function normalizeCpf(input) {
    return (input || "").replace(/[^0-9]/g, "").trim();
}
function normalizeGender(input) {
    const raw = String(input || "").trim().toLowerCase();
    if (raw.includes("fem") || raw === "mulher")
        return "FEMININO";
    if (raw.includes("masc") || raw === "homem")
        return "MASCULINO";
    return "INDEFINIDO";
}
function canManageUsersRole(role) {
    return role === "MASTER" || role === "ADM" || role === "ADMIN" || role === "GESTOR";
}
function ensureTenantScope(callerRole, callerTenantId, targetTenantId) {
    if (callerRole !== "MASTER" && callerTenantId !== targetTenantId) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para operar em outro tenant");
    }
}
/** Alinhado a `ChurchFuncoesControleService.roleRank` / `pickHighestRole` no app. */
const PANEL_ROLE_TIER_KEYS = [
    ["master"],
    ["adm", "admin", "administrador", "administradora"],
    ["gestor", "pastor_presidente"],
    ["pastor", "pastora"],
    ["secretario", "secretário", "secretária"],
    ["presbitero", "presbitera"],
    ["pastor_auxiliar"],
    ["tesoureiro", "tesouraria"],
    ["lider", "lider_departamento", "lider_depto"],
    ["diacono"],
    ["evangelista"],
    ["musico"],
    ["membro"],
    ["visitante"],
];
function panelRoleRank(role) {
    const x = String(role || "").trim().toLowerCase();
    if (!x)
        return 0;
    for (let i = 0; i < PANEL_ROLE_TIER_KEYS.length; i++) {
        if (PANEL_ROLE_TIER_KEYS[i].includes(x))
            return 1000 - i;
    }
    return 400;
}
function pickHighestPanelRole(candidates) {
    let best = "membro";
    let bestScore = panelRoleRank(best);
    for (const c of candidates) {
        const t = String(c || "").trim().toLowerCase();
        if (!t)
            continue;
        const s = panelRoleRank(t);
        if (s > bestScore) {
            bestScore = s;
            best = t;
        }
    }
    return best;
}
/** Núcleo de permissão a partir de `funcoesControle` / `cargos` (espelho do app). */
async function resolvePermissionBaseServer(tenantId, funcaoKey) {
    let key = String(funcaoKey || "").trim().toLowerCase();
    if (!key)
        return "membro";
    if (key === "administrador" || key === "administradora")
        key = "adm";
    const fcSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("funcoesControle")
        .doc(key)
        .get();
    if (fcSnap.exists) {
        const t = String(fcSnap.data()?.permissionTemplate ?? key)
            .trim()
            .toLowerCase();
        return t || key;
    }
    try {
        const byId = await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("cargos")
            .doc(key)
            .get();
        if (byId.exists) {
            const pt = String(byId.data()?.permissionTemplate ?? "").trim();
            if (pt)
                return pt.toLowerCase();
        }
        const cq = await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("cargos")
            .where("key", "==", key)
            .limit(1)
            .get();
        if (!cq.empty) {
            const pt = String(cq.docs[0].data()?.permissionTemplate ?? "").trim();
            if (pt)
                return pt.toLowerCase();
        }
    }
    catch {
        /* ignore */
    }
    return key;
}
/** Papel efetivo do painel a partir do doc `membros` (FUNCOES + templates). */
async function computeEffectivePanelRoleFromMembroServer(tenantId, memberData) {
    const md = memberData || {};
    const candidates = [];
    const push = (s) => {
        const t = String(s || "").trim().toLowerCase();
        if (t)
            candidates.push(t);
    };
    push(String(md.role || ""));
    push(String(md.FUNCAO_PERMISSOES || md.funcao_permissoes || ""));
    const funcoes = md.FUNCOES ?? md.funcoes;
    if (Array.isArray(funcoes)) {
        for (const e of funcoes) {
            const k = String(e).trim();
            if (!k)
                continue;
            push(await resolvePermissionBaseServer(tenantId, k));
        }
    }
    else {
        const fun = String(md.FUNCAO || md.CARGO || md.cargo || "").trim();
        if (fun)
            push(await resolvePermissionBaseServer(tenantId, fun));
    }
    if (candidates.length === 0)
        push("membro");
    return pickHighestPanelRole(candidates);
}
/** Valor de `role` nas custom claims (token), alinhado a `repairMyChurchBinding`. */
function claimTokenRoleFromPanelKey(panelKey) {
    const s = String(panelKey || "").trim();
    if (!s)
        return "membro";
    const low = s.toLowerCase();
    if (low === "membro")
        return "membro";
    if (low === "gestor")
        return "GESTOR";
    if (low === "master")
        return "MASTER";
    if (low === "adm" ||
        low === "admin" ||
        low === "administrador" ||
        low === "administradora") {
        return "ADM";
    }
    return s.length <= 24 ? s.toUpperCase() : "membro";
}
async function resolveFromPublicIndex(cpf) {
    const snap = await db.doc(`publicCpfIndex/${cpf}`).get();
    if (!snap.exists)
        return null;
    const publicData = snap.data() || {};
    const tenantId = String(publicData.tenantId || publicData.churchId || "").replace(/"/g, "").trim();
    if (!tenantId)
        return null;
    let tenant = {};
    const tenantSnap = await db.collection("tenants").doc(tenantId).get();
    if (tenantSnap.exists) {
        tenant = tenantSnap.data() || {};
    }
    else {
        const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
        if (igrejaSnap.exists) {
            tenant = igrejaSnap.data() || {};
        }
    }
    let userData = {};
    const userDocTenant = await db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf)
        .get();
    if (userDocTenant.exists) {
        userData = userDocTenant.data() || {};
    }
    else {
        const userDocIgreja = await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .get();
        if (userDocIgreja.exists) {
            userData = userDocIgreja.data() || {};
        }
    }
    const name = String(tenant.name || tenant.nome || publicData.name || "Igreja").replace(/"/g, "");
    const slug = String(tenant.slug || tenant.alias || publicData.slug || tenantId || "")
        .replace(/"/g, "")
        .trim();
    return {
        tenantId,
        name,
        logoUrl: String(tenant.logoUrl || tenant.logo || publicData.logoUrl || ""),
        slug,
        role: String(userData.role || publicData.role || "user"),
        email: String(userData.email || publicData.email || ""),
    };
}
/**
 * ✅ CPF → PERFIL DA IGREJA (CALLABLE)
 * Procura em tenants/{tenantId}/usersIndex/{cpf} (docId ou campo cpf)
 */
exports.resolveCpfToChurchPublic = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const cpf = normalizeCpf(String(data?.cpf || ""));
    if (cpf.length !== 11) {
        throw new functions.https.HttpsError("invalid-argument", "CPF inválido");
    }
    try {
        const publicFirst = await resolveFromPublicIndex(cpf);
        if (publicFirst) {
            return {
                tenantId: publicFirst.tenantId,
                name: publicFirst.name,
                logoUrl: publicFirst.logoUrl,
                slug: publicFirst.slug,
                role: publicFirst.role,
            };
        }
        // 1) tenta achar por campo cpf
        let snap = await db
            .collectionGroup("usersIndex")
            .where("cpf", "==", cpf)
            .limit(1)
            .get();
        // 2) fallback: docId == cpf
        if (snap.empty) {
            snap = await db
                .collectionGroup("usersIndex")
                .where(admin.firestore.FieldPath.documentId(), "==", cpf)
                .limit(1)
                .get();
        }
        if (snap.empty) {
            throw new functions.https.HttpsError("not-found", "CPF não encontrado");
        }
        const userDoc = snap.docs[0];
        const userData = userDoc.data() || {};
        const parentRef = userDoc.ref.parent.parent;
        const tenantId = String(userData.tenantId || (parentRef ? parentRef.id : "")).trim();
        if (!tenantId) {
            throw new functions.https.HttpsError("internal", "tenantId ausente");
        }
        let tenant = {};
        const tenantSnap = await db.collection("tenants").doc(tenantId).get();
        if (tenantSnap.exists) {
            tenant = tenantSnap.data() || {};
        }
        else {
            const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
            if (igrejaSnap.exists) {
                tenant = igrejaSnap.data() || {};
            }
        }
        return {
            tenantId,
            name: String(tenant.name || tenant.nome || "Igreja"),
            logoUrl: String(tenant.logoUrl || tenant.logo || ""),
            slug: String(tenant.slug || tenant.alias || tenantId),
            role: String(userData.role || "user"),
        };
    }
    catch (e) {
        console.error("resolveCpfToChurchPublic error:", e);
        if (e instanceof functions.https.HttpsError)
            throw e;
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
// ✅ Cria pastas do Drive quando uma igreja e criada
exports.onTenantCreate = functions
    .region("us-central1")
    .firestore.document("tenants/{tenantId}")
    .onCreate(async (_, context) => {
    const tenantId = context.params.tenantId;
    await ensureTenantDriveFolders(tenantId);
    try {
        await (0, churchWelcomeSeed_1.ensureChurchWelcomeSeed)(db, tenantId);
    }
    catch (e) {
        console.error("onTenantCreate ensureChurchWelcomeSeed:", e);
    }
});
// ✅ Endpoint manual para recriar pastas no Drive
exports.ensureDriveFolders = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const role = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || role != "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatorio");
    }
    try {
        const res = await ensureTenantDriveFolders(tenantId);
        return { ok: true, ...res };
    }
    catch (e) {
        console.error("ensureDriveFolders error:", e);
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
// ✅ Cria pasta global de downloads e grava em config/appDownloads
exports.ensureGlobalDownloads = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    const role = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || role != "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const driveRootId = getDriveRootId();
    if (!driveRootId) {
        throw new functions.https.HttpsError("failed-precondition", "drive.root_id nao configurado");
    }
    try {
        const drive = await getDrive();
        const downloadsFolder = await findOrCreateFolder(drive, driveRootId, "Downloads");
        await db.doc("config/appDownloads").set({
            driveFolderId: downloadsFolder,
            driveFolderUrl: driveFolderUrl(downloadsFolder),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true, driveFolderId: downloadsFolder };
    }
    catch (e) {
        console.error("ensureGlobalDownloads error:", e);
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
// ✅ Backup diario 00:00 BRT para Drive
exports.backupDailyToDrive = functions
    .region("us-central1")
    .pubsub.schedule("0 0 * * *")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const churchRootId = getChurchDriveRootId();
    if (!churchRootId) {
        console.error("drive.church_root_id nao configurado");
        return;
    }
    const drive = await getDrive();
    const backupRoot = await findOrCreateFolder(drive, churchRootId, "GESTAO_YAHWEH_BKPS_DIARIOS");
    const dailyFolder = await findOrCreateFolder(drive, backupRoot, ymdFolder(new Date()));
    const tenantsSnap = await db.collection("tenants").get();
    for (const t of tenantsSnap.docs) {
        const tenantId = t.id;
        const membersSnap = await db
            .collection("tenants")
            .doc(tenantId)
            .collection("members")
            .get();
        const usersSnap = await db
            .collection("tenants")
            .doc(tenantId)
            .collection("usersIndex")
            .get();
        const members = membersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const usersIndex = usersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const fleetVehiclesSnap = await db
            .collection("tenants")
            .doc(tenantId)
            .collection("fleet_vehicles")
            .get();
        const fleetFuelingsSnap = await db
            .collection("tenants")
            .doc(tenantId)
            .collection("fleet_fuelings")
            .get();
        const fleetVehicles = fleetVehiclesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const fleetFuelings = fleetFuelingsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const folders = await ensureTenantDriveFolders(tenantId);
        const date = new Date();
        const name = `firestore_${date
            .toISOString()
            .replace(/[:.]/g, "-")}.json`;
        await writeJsonFile(drive, folders.firestoreFolder, name, {
            tenantId,
            generatedAt: date.toISOString(),
            tenant: t.data(),
            members,
            usersIndex,
            fleetVehicles,
            fleetFuelings,
        });
        await writeJsonFile(drive, dailyFolder, `tenant_${tenantId}.json`, {
            tenantId,
            generatedAt: date.toISOString(),
            tenant: t.data(),
            members,
            usersIndex,
            fleetVehicles,
            fleetFuelings,
        });
    }
    const fleetRootId = getFleetDriveRootId();
    if (fleetRootId) {
        const frotaBackupRoot = await findOrCreateFolder(drive, fleetRootId, "GESTAO_YAHWEH_BKPS_DIARIOS");
        const frotaDailyFolder = await findOrCreateFolder(drive, frotaBackupRoot, ymdFolder(new Date()));
        const [customersSnap, salesSnap, licensesSnap] = await Promise.all([
            db.collection("frota_customers").get(),
            db.collection("sales").get(),
            db.collection("licenses").get(),
        ]);
        const customers = customersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const sales = salesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        const licenses = licensesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        await writeJsonFile(drive, frotaDailyFolder, "frota_global.json", {
            generatedAt: new Date().toISOString(),
            customers,
            sales,
            licenses,
        });
    }
});
async function runChurchMediaArchive(options) {
    const churchRootId = getChurchDriveRootId();
    if (!churchRootId) {
        throw new Error("drive.church_root_id nao configurado");
    }
    const retentionDays = getMediaRetentionDays();
    const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
    const maxPostsPerTenant = Math.max(1, options?.maxPostsPerTenant || 500);
    const tenantsSnap = await db.collection("igrejas").get();
    const bucket = admin.storage().bucket();
    const summary = {
        scannedPosts: 0,
        archivedFiles: 0,
        archivedPosts: 0,
        errors: 0,
    };
    for (const tenant of tenantsSnap.docs) {
        const tenantId = tenant.id;
        const postsSnap = await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("noticias")
            .orderBy("createdAt", "asc")
            .limit(maxPostsPerTenant)
            .get();
        for (const postDoc of postsSnap.docs) {
            summary.scannedPosts += 1;
            const post = postDoc.data() || {};
            if (!options?.forceAll && post.archivedToDriveAt)
                continue;
            const createdAt = toDateSafe(post.createdAt) || toDateSafe(post.updatedAt);
            if (!createdAt)
                continue;
            if (!options?.forceAll && createdAt > cutoff)
                continue;
            const imageUrl = String(post.imageUrl || "").trim();
            const videoUrl = String(post.videoUrl || "").trim();
            const mediaCandidates = [
                { field: "imageUrl", url: imageUrl, kind: "image" },
                { field: "videoUrl", url: videoUrl, kind: "video" },
            ].filter((m) => m.url.length > 0);
            if (!mediaCandidates.length)
                continue;
            const updatePayload = {
                archivedRetentionDays: retentionDays,
                archivedToDriveAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            let archivedCount = 0;
            for (const media of mediaCandidates) {
                try {
                    const storagePath = storagePathFromUrl(media.url);
                    if (!storagePath)
                        continue;
                    const [exists] = await bucket.file(storagePath).exists();
                    if (!exists)
                        continue;
                    const { drive, monthFolder } = await ensureTenantMediaArchiveFolder(tenantId, createdAt);
                    const driveFile = await uploadBucketFileToDrive(drive, storagePath, monthFolder);
                    updatePayload[`${media.field}Firebase`] = media.url;
                    updatePayload[media.field] = driveFile.directViewUrl;
                    updatePayload[`${media.field}DriveFileId`] = driveFile.fileId;
                    updatePayload[`${media.field}DriveViewUrl`] = driveFile.webViewLink;
                    updatePayload[`${media.field}DriveArchivedPath`] = storagePath;
                    await bucket.file(storagePath).delete();
                    archivedCount += 1;
                    summary.archivedFiles += 1;
                    await db.collection("drive_archives").add({
                        tenantId,
                        postId: postDoc.id,
                        type: String(post.type || "aviso"),
                        title: String(post.title || "").trim(),
                        field: media.field,
                        kind: media.kind,
                        storagePath,
                        driveFileId: driveFile.fileId,
                        driveViewUrl: driveFile.webViewLink,
                        driveDirectUrl: driveFile.directViewUrl,
                        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
                        archivedBy: options?.invokedBy || "system",
                        retentionDays,
                    });
                }
                catch (e) {
                    summary.errors += 1;
                    console.error("archiveChurchMediaToDrive media error", {
                        tenantId,
                        postId: postDoc.id,
                        field: media.field,
                        error: e?.message || e,
                    });
                }
            }
            if (archivedCount > 0) {
                summary.archivedPosts += 1;
                updatePayload.archivedMediaCount = archivedCount;
                await postDoc.ref.set(updatePayload, { merge: true });
            }
        }
    }
    return summary;
}
// ✅ Migra mídias de igreja com mais de X dias para Google Drive e remove do Firebase Storage
exports.archiveChurchMediaToDrive = functions
    .region("us-central1")
    .pubsub.schedule("20 0 * * *")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    await runChurchMediaArchive({ invokedBy: "scheduler" });
});
// ✅ Execução manual do arquivamento (painel ADM)
exports.archiveChurchMediaNow = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const role = String(context.auth?.token?.role || "").toUpperCase();
    const canRun = role === "MASTER" || role === "ADM" || role === "ADMIN";
    if (!context.auth || !canRun) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM");
    }
    const forceAll = data?.forceAll === true;
    const summary = await runChurchMediaArchive({
        forceAll,
        invokedBy: context.auth.uid,
    });
    return {
        ok: true,
        ...summary,
        forceAll,
        retentionDays: getMediaRetentionDays(),
    };
});
/** Retorna uso de armazenamento (Firestore). Drive não é mais medido no painel. Acesso: gestor da igreja ou MASTER/ADM. */
exports.getChurchStorageUsage = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login obrigatório");
    }
    const tenantId = String(data?.tenantId ?? "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");
    }
    const role = String(context.auth?.token?.role ?? "").toUpperCase();
    const isMasterOrAdm = role === "MASTER" || role === "ADM" || role === "ADMIN";
    const tokenTenantId = String(context.auth?.token?.tenantId ?? "").trim();
    if (!isMasterOrAdm && tokenTenantId && tokenTenantId !== tenantId) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja");
    }
    const firestoreCounts = {};
    let firestoreTotal = 0;
    try {
        const [membersSnap, noticiasSnap, usersSnap] = await Promise.all([
            db.collection("tenants").doc(tenantId).collection("members").count().get(),
            db.collection("igrejas").doc(tenantId).collection("noticias").count().get(),
            db.collection("tenants").doc(tenantId).collection("usersIndex").count().get(),
        ]);
        firestoreCounts.members = membersSnap.data().count ?? 0;
        firestoreCounts.noticias = noticiasSnap.data().count ?? 0;
        firestoreCounts.usersIndex = usersSnap.data().count ?? 0;
        firestoreTotal = firestoreCounts.members + firestoreCounts.noticias + firestoreCounts.usersIndex + 2; // +2 docs tenant + igreja
    }
    catch (e) {
        console.warn("getChurchStorageUsage firestore counts error", tenantId, e?.message);
    }
    const firestoreEstimateBytes = Math.max(0, firestoreTotal * 1024); // ~1KB por doc estimado
    // Google Drive: não utilizado no produto atual — resposta fixa (compatível com clientes antigos).
    const driveBytes = 0;
    const driveFolderId = "";
    const driveFolderUrlStr = "";
    return {
        ok: true,
        tenantId,
        firestore: {
            docCounts: firestoreCounts,
            totalDocs: firestoreTotal,
            estimateBytes: firestoreEstimateBytes,
        },
        drive: {
            bytes: driveBytes,
            folderId: driveFolderId,
            folderUrl: driveFolderUrlStr,
        },
    };
});
/** Testa gravação no Drive da igreja: cria e remove um arquivo de teste. Acesso: gestor da igreja ou MASTER/ADM. */
exports.testDriveWriteForChurch = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Login obrigatório");
    }
    const tenantId = String(data?.tenantId ?? "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório");
    }
    const role = String(context.auth?.token?.role ?? "").toUpperCase();
    const isMasterOrAdm = role === "MASTER" || role === "ADM" || role === "ADMIN";
    const tokenTenantId = String(context.auth?.token?.tenantId ?? "").trim();
    if (!isMasterOrAdm && tokenTenantId && tokenTenantId !== tenantId) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para esta igreja");
    }
    const churchRootId = getChurchDriveRootId();
    if (!churchRootId || String(churchRootId).trim() === "") {
        throw new functions.https.HttpsError("failed-precondition", "Drive não configurado (DRIVE_CHURCH_ROOT_ID). Configure no painel do Firebase.");
    }
    let testFileId = null;
    try {
        const { drive, monthFolder } = await ensureTenantMediaArchiveFolder(tenantId, new Date());
        const testName = `test_write_${Date.now()}.txt`;
        const created = await drive.files.create({
            requestBody: {
                name: testName,
                parents: [monthFolder],
                description: "Teste de gravação Drive - pode ser removido",
            },
            media: {
                mimeType: "text/plain",
                body: Buffer.from("ok", "utf8"),
            },
            fields: "id",
        });
        testFileId = created?.data?.id || null;
        if (testFileId) {
            await drive.files.delete({ fileId: testFileId });
        }
        return {
            ok: true,
            message: "Drive OK: gravação e exclusão do arquivo de teste concluídas sem erros.",
        };
    }
    catch (e) {
        if (testFileId) {
            try {
                const drive = await getDrive();
                await drive.files.delete({ fileId: testFileId });
            }
            catch (_) { }
        }
        const msg = e?.message || String(e);
        throw new functions.https.HttpsError("internal", `Teste Drive falhou: ${msg}`);
    }
});
// ✅ Backup completo do Firestore para GCS (export oficial)
exports.backupDailyToGcs = functions
    .region("us-central1")
    .pubsub.schedule("5 0 * * *")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    if (!projectId) {
        console.error("projectId nao encontrado");
        return;
    }
    const backupBucket = getGcsBackupBucket();
    if (!backupBucket) {
        console.error("gcs.backup_bucket nao configurado");
        return;
    }
    const { google } = await Promise.resolve().then(() => __importStar(require("googleapis")));
    const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/cloud-platform"],
    });
    const firestore = google.firestore({ version: "v1", auth });
    const name = `projects/${projectId}/databases/(default)`;
    const outputUriPrefix = `gs://${backupBucket}/firestore/${ymFolder(new Date())}`;
    await firestore.projects.databases.exportDocuments({
        name,
        requestBody: {
            outputUriPrefix,
        },
    });
});
// Planos oficiais padrão (mesmos IDs do app planos_oficiais.dart) — usados quando config/plans/items não tem o doc
const DEFAULT_PLANS = {
    inicial: { name: "Plano Inicial", priceMonthly: 49.9, priceAnnual: 499 },
    essencial: { name: "Plano Essencial", priceMonthly: 59.9, priceAnnual: 599 },
    intermediario: { name: "Plano Intermediário", priceMonthly: 69.9, priceAnnual: 699 },
    avancado: { name: "Plano Avançado", priceMonthly: 89.9, priceAnnual: 899 },
    profissional: { name: "Plano Profissional", priceMonthly: 99.9, priceAnnual: 999 },
    premium: { name: "Plano Premium", priceMonthly: 169.9, priceAnnual: 1699 },
    premium_plus: { name: "Plano Premium Plus", priceMonthly: 189.9, priceAnnual: 1899 },
    corporativo: { name: "Plano Corporativo", priceMonthly: 0, priceAnnual: 0 },
};
// ✅ Criar assinatura (preapproval) no Mercado Pago
exports.createMpPreapproval = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const planId = String(data?.planId || "").trim();
    if (!planId) {
        throw new functions.https.HttpsError("invalid-argument", "planId obrigatorio");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const claims = (token.customClaims || {});
    const tenantId = String(claims.igrejaId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const planSnap = await db
        .collection("config")
        .doc("plans")
        .collection("items")
        .doc(planId)
        .get();
    let plan = {};
    if (planSnap.exists) {
        plan = planSnap.data() || {};
    }
    else {
        const defaultPlan = DEFAULT_PLANS[planId];
        if (defaultPlan) {
            plan = {
                name: defaultPlan.name,
                priceMonthly: defaultPlan.priceMonthly,
                priceAnnual: defaultPlan.priceAnnual ?? defaultPlan.priceMonthly * 10,
            };
        }
        else {
            throw new functions.https.HttpsError("not-found", "Plano nao encontrado");
        }
    }
    const billingCycle = String(data?.billingCycle || "monthly").toLowerCase();
    const paymentMethod = String(data?.paymentMethod || "pix").toLowerCase();
    const installments = Math.min(12, Math.max(1, Number(data?.installments) || 10));
    const isAnnual = billingCycle === "annual";
    const priceMonthly = Number(plan.priceMonthly || 0);
    const priceAnnual = Number(plan.priceAnnual ?? plan.priceYear ?? 0);
    const price = isAnnual
        ? (priceAnnual > 0 ? priceAnnual : priceMonthly * 12)
        : priceMonthly;
    if (!price || price <= 0) {
        if (planId === "corporativo") {
            throw new functions.https.HttpsError("failed-precondition", "Plano Corporativo: valor a combinar. Entre em contato com o suporte.");
        }
        throw new functions.https.HttpsError("failed-precondition", "Plano sem preco valido para " + (isAnnual ? "anual" : "mensal"));
    }
    let payerEmail = String(token.email || "").trim();
    if (!payerEmail) {
        try {
            const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
            const igreja = igrejaSnap.exists ? igrejaSnap.data() : {};
            payerEmail = String(igreja?.contactEmail || igreja?.contact_email || igreja?.email || "").trim();
        }
        catch { }
    }
    if (!payerEmail || !payerEmail.includes("@")) {
        payerEmail = `pagamento+${tenantId}@gestaoyahweh.com.br`;
    }
    const notificationUrl = await resolveMpNotificationUrl();
    const backUrl = await resolveMpBackUrl();
    const payload = {
        reason: `Gestao YAHWEH - ${plan.name || planId} (${isAnnual ? "Anual" : "Mensal"})`,
        external_reference: tenantId,
        notification_url: notificationUrl,
        /** Obrigatório Mercado Pago (erro 400 "back_url is required") — retorno após PIX/cartão. */
        back_url: backUrl,
        payer_email: payerEmail,
        auto_recurring: {
            frequency: isAnnual ? 12 : 1,
            frequency_type: "months",
            transaction_amount: price,
            currency_id: "BRL",
        },
        metadata: {
            tenantId: String(tenantId),
            planId: String(planId),
            billingCycle: isAnnual ? "annual" : "monthly",
            paymentMethod: paymentMethod === "card" ? "card" : "pix",
            installments: String(paymentMethod === "card" ? installments : 1),
        },
    };
    try {
        const res = await mpPost("/preapproval", payload);
        return {
            ok: true,
            init_point: res.init_point || res.sandbox_init_point || "",
            id: res.id || "",
            /** App embute o checkout e usa isto para detectar retorno pós-pagamento. */
            back_url: backUrl,
        };
    }
    catch (e) {
        console.error("createMpPreapproval error:", e);
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
// ✅ Criar PIX avulso com QR + copia-e-cola para plano (pagamento imediato)
exports.createMpPixPayment = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const planId = String(data?.planId || "").trim();
    if (!planId) {
        throw new functions.https.HttpsError("invalid-argument", "planId obrigatorio");
    }
    const token = await admin.auth().getUser(context.auth.uid);
    const claims = (token.customClaims || {});
    const tenantId = String(claims.igrejaId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const planSnap = await db
        .collection("config")
        .doc("plans")
        .collection("items")
        .doc(planId)
        .get();
    let plan = {};
    if (planSnap.exists) {
        plan = planSnap.data() || {};
    }
    else {
        const defaultPlan = DEFAULT_PLANS[planId];
        if (defaultPlan) {
            plan = {
                name: defaultPlan.name,
                priceMonthly: defaultPlan.priceMonthly,
                priceAnnual: defaultPlan.priceAnnual ?? defaultPlan.priceMonthly * 10,
            };
        }
        else {
            throw new functions.https.HttpsError("not-found", "Plano nao encontrado");
        }
    }
    const billingCycle = String(data?.billingCycle || "monthly").toLowerCase();
    const isAnnual = billingCycle === "annual";
    const priceMonthly = Number(plan.priceMonthly || 0);
    const priceAnnual = Number(plan.priceAnnual ?? plan.priceYear ?? 0);
    const price = isAnnual
        ? (priceAnnual > 0 ? priceAnnual : priceMonthly * 12)
        : priceMonthly;
    if (!price || price <= 0) {
        if (planId === "corporativo") {
            throw new functions.https.HttpsError("failed-precondition", "Plano Corporativo: valor a combinar. Entre em contato com o suporte.");
        }
        throw new functions.https.HttpsError("failed-precondition", "Plano sem preco valido para " + (isAnnual ? "anual" : "mensal"));
    }
    let payerEmail = String(token.email || "").trim();
    if (!payerEmail) {
        try {
            const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
            const igreja = igrejaSnap.exists ? igrejaSnap.data() : {};
            payerEmail = String(igreja?.contactEmail || igreja?.contact_email || igreja?.email || "").trim();
        }
        catch { }
    }
    if (!payerEmail || !payerEmail.includes("@")) {
        payerEmail = `pagamento+${tenantId}@gestaoyahweh.com.br`;
    }
    const notificationUrl = await resolveMpNotificationUrl();
    const payload = {
        transaction_amount: Number(price.toFixed(2)),
        payment_method_id: "pix",
        description: `Gestao YAHWEH - ${plan.name || planId} (${isAnnual ? "Anual" : "Mensal"})`,
        external_reference: tenantId,
        notification_url: notificationUrl,
        payer: {
            email: payerEmail,
        },
        metadata: {
            tenantId: String(tenantId),
            planId: String(planId),
            billingCycle: isAnnual ? "annual" : "monthly",
            paymentMethod: "pix",
        },
    };
    const idempotencyKey = `pix-${context.auth.uid}-${planId}-${billingCycle}-${Math.floor(Date.now() / 1000)}`;
    try {
        const res = await mpPost("/v1/payments", payload, {
            "X-Idempotency-Key": idempotencyKey,
        });
        const tx = res?.point_of_interaction?.transaction_data || {};
        const qrCode = tx?.qr_code || tx?.pix_copia_cola || tx?.pix_copy_paste || "";
        return {
            ok: true,
            payment_id: String(res?.id || ""),
            status: String(res?.status || ""),
            qr_code: String(qrCode),
            qr_code_base64: String(tx?.qr_code_base64 || ""),
            ticket_url: String(tx?.ticket_url || ""),
        };
    }
    catch (e) {
        const errMsg = e?.message || "Erro interno";
        console.error("createMpPixPayment error:", errMsg);
        throw new functions.https.HttpsError("internal", errMsg.length > 200 ? errMsg.slice(0, 200) : errMsg);
    }
});
// ✅ Webhook Mercado Pago (pagamentos e assinaturas) — mesmo handler em `mpWebhook` e `mercadoPagoWebhook`
async function mercadoPagoWebhookHandler(req, res) {
    try {
        const type = String(req.body?.type || req.query?.type || req.body?.action || req.body?.topic || "").toLowerCase();
        const dataId = String(req.body?.data?.id ??
            req.body?.data?.resource ??
            req.body?.id ??
            req.query?.id ??
            "").trim();
        if (!dataId) {
            res.status(200).json({ ok: true, reason: "NO_ID" });
            return;
        }
        if (type.includes("payment")) {
            const tenantHint = String(req.query?.tenantId || req.body?.tenantId || "").trim();
            const { payment } = await (0, churchMercadoPago_1.fetchPaymentForWebhook)(dataId, mpGet, tenantHint);
            const churchDone = await (0, churchMercadoPago_1.tryHandleChurchDonationPayment)(payment);
            if (churchDone) {
                res.status(200).json({ ok: true, branch: "church_donation" });
                return;
            }
            const tenantId = String(payment.external_reference ||
                payment.metadata?.tenantId ||
                payment.metadata?.igrejaId ||
                "").trim();
            if (!tenantId) {
                res.status(200).json({ ok: true, reason: "NO_TENANT" });
                return;
            }
            const billingStatus = mapPaymentStatus(payment.status || "");
            const amount = Number(payment.transaction_amount || 0);
            const lastPaid = parseMpDate(payment.date_approved);
            const nextCharge = parseMpDate(payment.date_of_expiration);
            const meta = payment.metadata || {};
            await updateTenantBilling(tenantId, billingStatus, {
                subscriptionId: String(payment.order?.id || payment.subscription_id || ""),
                lastPaymentAt: lastPaid || undefined,
                nextChargeAt: nextCharge || undefined,
                metadataPlanId: String(meta.planId || meta.plan_id || ""),
                billingCycle: String(meta.billingCycle || meta.billing_cycle || ""),
                mpPaymentId: String(payment.id || ""),
            });
            await db
                .collection("sales")
                .doc(`mp_payment_${payment.id}`)
                .set({
                provider: "mercado_pago",
                type: "payment",
                tenantId,
                status: payment.status || "",
                amount,
                currency: payment.currency_id || "BRL",
                paymentId: String(payment.id),
                externalReference: String(payment.external_reference || ""),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                rawStatus: payment.status_detail || "",
            }, { merge: true });
            res.status(200).json({ ok: true });
            return;
        }
        if (type.includes("preapproval") || type.includes("subscription")) {
            const pre = await mpGet(`/preapproval/${dataId}`);
            const tenantId = String(pre.external_reference || pre.metadata?.tenantId || "").trim();
            if (!tenantId) {
                res.status(200).json({ ok: true, reason: "NO_TENANT" });
                return;
            }
            const billingStatus = mapPreapprovalStatus(pre.status || "");
            const lastPaid = parseMpDate(pre.last_payment_date);
            const nextCharge = parseMpDate(pre.next_payment_date);
            const preMeta = pre.metadata || {};
            await updateTenantBilling(tenantId, billingStatus, {
                subscriptionId: String(pre.id || ""),
                lastPaymentAt: lastPaid || undefined,
                nextChargeAt: nextCharge || undefined,
                metadataPlanId: String(preMeta.planId || preMeta.plan_id || ""),
                billingCycle: String(preMeta.billingCycle || preMeta.billing_cycle || ""),
            });
            await db
                .collection("sales")
                .doc(`mp_preapproval_${pre.id}`)
                .set({
                provider: "mercado_pago",
                type: "preapproval",
                tenantId,
                status: pre.status || "",
                amount: Number(pre.auto_recurring?.transaction_amount || 0),
                currency: pre.currency_id || "BRL",
                subscriptionId: String(pre.id || ""),
                externalReference: String(pre.external_reference || ""),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
            res.status(200).json({ ok: true });
            return;
        }
        res.status(200).json({ ok: true, reason: "IGNORED" });
        return;
    }
    catch (e) {
        console.error("mercadoPagoWebhook error:", e);
        res.status(500).json({ ok: false, error: e?.message || "ERR" });
        return;
    }
}
exports.mercadoPagoWebhook = functions
    .region("us-central1")
    .https.onRequest(mercadoPagoWebhookHandler);
/** Alias — mesma URL que muitos painéis MP usam: .../mpWebhook */
exports.mpWebhook = functions
    .region("us-central1")
    .https.onRequest(mercadoPagoWebhookHandler);
/**
 * ✅ EMAIL → PERFIL DA IGREJA (CALLABLE)
 * Ordem: usersIndex → campos de e-mail em `igrejas/` → ficha em `membros`/`members`.
 * O site público chama isto sem login; o cliente não tem collectionGroup em usersIndex/membros.
 */
exports.resolveEmailToChurchPublic = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const rawIn = String(data?.email || "").trim();
    const email = rawIn.toLowerCase();
    if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError("invalid-argument", "Email invalido");
    }
    const variants = Array.from(new Set([email, rawIn, rawIn.toUpperCase()])).filter((v) => v.length > 0);
    const churchFields = [
        "email",
        "gestorEmail",
        "gestor_email",
        "emailGestor",
        "emailContato",
        "responsavelEmail",
    ];
    function outPayload(tenantId, ch, role = "user") {
        return {
            tenantId,
            name: String(ch.nome || ch.name || ch.nomeFantasia || "Igreja"),
            logoUrl: String(ch.logoUrl || ch.logoProcessedUrl || ch.logoProcessed || ch.logo || ""),
            slug: String(ch.slug || ch.alias || ""),
            role,
        };
    }
    try {
        const idxSnap = await db
            .collectionGroup("usersIndex")
            .where("email", "==", email)
            .limit(1)
            .get();
        if (!idxSnap.empty) {
            const userDoc = idxSnap.docs[0];
            const userData = userDoc.data() || {};
            const tenantId = String(userData.tenantId || userDoc.ref.parent.parent?.id || "");
            if (tenantId) {
                let churchSnap = await db.collection("igrejas").doc(tenantId).get();
                if (!churchSnap.exists) {
                    churchSnap = await db.collection("tenants").doc(tenantId).get();
                }
                const ch = churchSnap.data() || {};
                return outPayload(tenantId, ch, String(userData.role || "user"));
            }
        }
        // users/{uid} — muitos gestores têm só aqui o e-mail + igrejaId
        try {
            const rootUsers = await db
                .collection("users")
                .where("email", "==", email)
                .limit(8)
                .get();
            for (const ud of rootUsers.docs) {
                const u = ud.data() || {};
                const tenantId = String(u.igrejaId || u.tenantId || u.churchId || "").trim();
                if (tenantId) {
                    let churchSnap = await db.collection("igrejas").doc(tenantId).get();
                    if (!churchSnap.exists) {
                        churchSnap = await db.collection("tenants").doc(tenantId).get();
                    }
                    if (churchSnap.exists) {
                        return outPayload(tenantId, churchSnap.data() || {}, String(u.role || "gestor"));
                    }
                }
            }
        }
        catch (ignore) {
            /* falha se índice em email não existir */
        }
        /** Auth normaliza e-mail — cobre `users/{uid}` incompleto ou com casing diferente no Firestore. */
        try {
            const authU = await admin.auth().getUserByEmail(email);
            const userDoc = await db.collection("users").doc(authU.uid).get();
            const u = userDoc.data() || {};
            const claims = (authU.customClaims || {});
            let tenantId = String(u.igrejaId || u.tenantId || u.churchId || "").trim();
            if (!tenantId) {
                tenantId = String(claims.igrejaId || claims.tenantId || "").trim();
            }
            if (tenantId) {
                let churchSnap = await db.collection("igrejas").doc(tenantId).get();
                if (!churchSnap.exists) {
                    churchSnap = await db.collection("tenants").doc(tenantId).get();
                }
                if (churchSnap.exists) {
                    return outPayload(tenantId, churchSnap.data() || {}, String(u.role || claims.role || "user"));
                }
            }
        }
        catch (_) {
            /* sem conta Auth com este e-mail */
        }
        const churchQs = [];
        for (const field of churchFields) {
            for (const val of variants) {
                churchQs.push(db.collection("igrejas").where(field, "==", val).limit(1).get());
            }
        }
        const churchSettled = await Promise.allSettled(churchQs);
        for (const s of churchSettled) {
            if (s.status !== "fulfilled")
                continue;
            const q = s.value;
            if (!q.empty) {
                const doc = q.docs[0];
                return outPayload(doc.id, doc.data() || {}, "gestor");
            }
        }
        const memberFields = [
            "email",
            "EMAIL",
            "Email",
            "mail",
            "e_mail",
            "correio",
            "correioEletronico",
        ];
        const memberQs = [];
        for (const coll of ["membros", "members"]) {
            for (const val of variants) {
                for (const field of memberFields) {
                    memberQs.push(db.collectionGroup(coll).where(field, "==", val).limit(1).get());
                }
            }
        }
        const memberSettled = await Promise.allSettled(memberQs);
        for (const s of memberSettled) {
            if (s.status !== "fulfilled")
                continue;
            const mq = s.value;
            if (mq.empty)
                continue;
            const parent = mq.docs[0].ref.parent.parent;
            const tid = parent ? String(parent.id) : "";
            if (tid) {
                let churchSnap = await db.collection("igrejas").doc(tid).get();
                if (!churchSnap.exists) {
                    churchSnap = await db.collection("tenants").doc(tid).get();
                }
                if (churchSnap.exists) {
                    return outPayload(tid, churchSnap.data() || {}, "membro");
                }
            }
        }
        throw new functions.https.HttpsError("not-found", "Email nao encontrado");
    }
    catch (e) {
        console.error("resolveEmailToChurchPublic error:", e);
        if (e instanceof functions.https.HttpsError)
            throw e;
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
/**
 * Corrige custom claims + users/{uid} quando o token ainda aponta para uma igreja removida
 * (ex.: igreja_teste) mas o e-mail ou authUid ainda existe numa igreja ativa em `igrejas/`.
 */
exports.repairMyChurchBinding = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "256MB" })
    .https.onCall(async (_, context) => {
    if (!context.auth?.uid) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const uid = context.auth.uid;
    const authEmail = String(context.auth.token?.email || "")
        .trim()
        .toLowerCase();
    if (!authEmail || !authEmail.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Conta sem e-mail para recalcular o vínculo com a igreja.");
    }
    const emailLower = authEmail;
    const emailRaw = authEmail;
    async function firstIgrejaFromGestorFields() {
        const fields = [
            "email",
            "gestorEmail",
            "emailGestor",
            "emailContato",
            "responsavelEmail",
        ];
        const vals = emailLower === emailRaw ? [emailLower] : [emailLower, emailRaw];
        const tasks = [];
        for (const field of fields) {
            for (const val of vals) {
                tasks.push({ field, val });
            }
        }
        const snaps = await Promise.all(tasks.map((t) => db.collection("igrejas").where(t.field, "==", t.val).limit(1).get()));
        for (let i = 0; i < snaps.length; i++) {
            const q = snaps[i];
            if (q.empty)
                continue;
            const id = q.docs[0].id;
            const ig = await db.collection("igrejas").doc(id).get();
            if (ig.exists)
                return id;
        }
        return null;
    }
    async function fromMembrosAuthUid() {
        const snap = await db
            .collectionGroup("membros")
            .where("authUid", "==", uid)
            .limit(15)
            .get();
        for (const doc of snap.docs) {
            const parts = doc.ref.path.split("/");
            if (parts[0] !== "igrejas" || parts[2] !== "membros")
                continue;
            const tid = parts[1];
            const ig = await db.collection("igrejas").doc(tid).get();
            if (!ig.exists)
                continue;
            const md = doc.data() || {};
            const st = String(md.STATUS || md.status || "").toLowerCase();
            const pending = st === "pendente";
            const roleRaw = String(md.role || md.FUNCAO || md.funcao || "membro").trim();
            return { tenantId: tid, role: roleRaw || "membro", pending };
        }
        return null;
    }
    async function fromUsersIndex() {
        const snap = await db
            .collectionGroup("usersIndex")
            .where("email", "==", emailLower)
            .limit(5)
            .get();
        for (const d of snap.docs) {
            const data = d.data() || {};
            const tid = String(data.tenantId || d.ref.parent.parent?.id || "").trim();
            if (!tid)
                continue;
            const ig = await db.collection("igrejas").doc(tid).get();
            if (!ig.exists)
                continue;
            const role = String(data.role || "GESTOR").trim() || "GESTOR";
            return { tenantId: tid, role };
        }
        return null;
    }
    async function fromMembrosEmail() {
        const fields = ["EMAIL", "email", "mail"];
        const vals = emailLower === emailRaw ? [emailLower] : [emailLower, emailRaw];
        const tasks = [];
        for (const field of fields) {
            for (const val of vals) {
                tasks.push({ field, val });
            }
        }
        const snaps = await Promise.all(tasks.map((t) => db
            .collectionGroup("membros")
            .where(t.field, "==", t.val)
            .limit(8)
            .get()));
        for (let i = 0; i < snaps.length; i++) {
            const snap = snaps[i];
            for (const doc of snap.docs) {
                const parts = doc.ref.path.split("/");
                if (parts[0] !== "igrejas" || parts[2] !== "membros")
                    continue;
                const tid = parts[1];
                const ig = await db.collection("igrejas").doc(tid).get();
                if (!ig.exists)
                    continue;
                const md = doc.data() || {};
                const st = String(md.STATUS || md.status || "").toLowerCase();
                if (st === "reprovado")
                    continue;
                const pending = st === "pendente";
                const roleRaw = String(md.role || md.FUNCAO || md.funcao || "membro").trim();
                return { tenantId: tid, role: roleRaw || "membro", pending };
            }
        }
        return null;
    }
    function claimRoleFromRaw(raw, fallback) {
        const s = String(raw || "").trim();
        if (!s)
            return fallback;
        const low = s.toLowerCase();
        if (low === "membro")
            return "membro";
        if (low === "gestor")
            return "GESTOR";
        if (low === "adm" || low === "admin" || low === "administrador")
            return "ADM";
        return s.length <= 24 ? s.toUpperCase() : "membro";
    }
    let tenantId = null;
    let roleOut = "GESTOR";
    let pendingApproval = false;
    let activeClaim = true;
    const [gestorId, byUid, ui] = await Promise.all([
        firstIgrejaFromGestorFields(),
        fromMembrosAuthUid(),
        fromUsersIndex(),
    ]);
    if (gestorId) {
        tenantId = gestorId;
        roleOut = "GESTOR";
        pendingApproval = false;
        activeClaim = true;
    }
    else if (byUid) {
        tenantId = byUid.tenantId;
        roleOut = claimRoleFromRaw(byUid.role, "membro");
        pendingApproval = byUid.pending;
        activeClaim = !byUid.pending;
    }
    else if (ui) {
        tenantId = ui.tenantId;
        roleOut = claimRoleFromRaw(ui.role, "GESTOR");
    }
    if (!tenantId) {
        const byEmail = await fromMembrosEmail();
        if (byEmail) {
            tenantId = byEmail.tenantId;
            roleOut = claimRoleFromRaw(byEmail.role, "membro");
            pendingApproval = byEmail.pending;
            activeClaim = !byEmail.pending;
        }
    }
    if (!tenantId) {
        throw new functions.https.HttpsError("not-found", "Nenhuma igreja ativa encontrada para sua conta. Use a página inicial (Carregar igreja) ou peça ao gestor.");
    }
    const churchSnap = await db.collection("igrejas").doc(tenantId).get();
    if (!churchSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const authUser = await admin.auth().getUser(uid);
    const cur = (authUser.customClaims || {});
    await admin.auth().setCustomUserClaims(uid, {
        ...cur,
        role: roleOut,
        igrejaId: tenantId,
        tenantId,
        active: activeClaim,
        isUser: true,
        isDriver: cur.isDriver === true,
        pendingApproval,
    });
    await db.collection("users").doc(uid).set({
        uid,
        email: authEmail,
        igrejaId: tenantId,
        tenantId,
        role: roleOut,
        ativo: activeClaim,
        active: activeClaim,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        ok: true,
        tenantId,
        role: roleOut,
        pendingApproval,
    };
});
/**
 * GESTOR/ADM/MASTER — Após alterar funções do membro no painel: atualiza custom claims + users + usersIndex
 * para o authUid do membro (evita precisar sair e entrar de novo).
 */
exports.syncMemberRoleClaims = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || !canManageUsersRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM/GESTOR");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const memberId = String(data?.memberId || data?.memberDocId || "").trim();
    const callerTenantId = String(context.auth?.token?.igrejaId || "").trim();
    ensureTenantScope(roleCaller, callerTenantId, tenantId);
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId são obrigatórios");
    }
    const found = await findMemberDocument(tenantId, memberId);
    if (!found) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado");
    }
    const memberData = found.data;
    const authUid = String(memberData.authUid || "").trim();
    if (!authUid) {
        return { ok: true, skipped: true, reason: "no_authUid" };
    }
    const status = String(memberData.STATUS || memberData.status || "").toLowerCase();
    const reallyAtivo = status === "ativo" || (status !== "pendente" && status !== "reprovado");
    const pendingApproval = status === "pendente";
    const panelRole = await computeEffectivePanelRoleFromMembroServer(tenantId, memberData);
    const roleClaim = claimTokenRoleFromPanelKey(panelRole);
    const cpf = String(memberData.CPF || memberData.cpf || "").replace(/\D/g, "");
    const nome = String(memberData.NOME_COMPLETO || memberData.nome || memberData.name || "").trim();
    const email = String(memberData.EMAIL || memberData.email || "")
        .trim()
        .toLowerCase();
    const mdAny = memberData || {};
    const rolesList = Array.isArray(mdAny.FUNCOES || mdAny.funcoes)
        ? (mdAny.FUNCOES || mdAny.funcoes)
            .map((e) => String(e).trim())
            .filter((s) => s.length > 0)
        : [];
    if (rolesList.length === 0) {
        const f = String(mdAny.FUNCAO || mdAny.CARGO || mdAny.cargo || "").trim();
        rolesList.push(f || "membro");
    }
    const funcaoFinal = String(mdAny.FUNCAO || mdAny.CARGO || mdAny.cargo || rolesList[0] || "membro").trim();
    const authUser = await admin.auth().getUser(authUid);
    const cur = (authUser.customClaims || {});
    await admin.auth().setCustomUserClaims(authUid, {
        ...cur,
        role: roleClaim,
        igrejaId: tenantId,
        tenantId,
        active: reallyAtivo,
        isUser: true,
        isDriver: cur.isDriver === true,
        pendingApproval,
        ...(cpf.length === 11 ? { cpf } : {}),
    });
    await db.collection("users").doc(authUid).set({
        email,
        cpf: cpf.length === 11 ? cpf : "",
        igrejaId: tenantId,
        tenantId,
        role: panelRole,
        roles: rolesList,
        nome,
        displayName: nome,
        nomeCompleto: nome,
        funcao: funcaoFinal,
        cargo: funcaoFinal,
        FUNCOES: rolesList,
        CARGO: funcaoFinal,
        ativo: reallyAtivo,
        active: reallyAtivo,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const indexPayload = {
        uid: authUid,
        cpf: cpf.length === 11 ? cpf : "",
        email,
        name: nome,
        nome,
        tenantId,
        role: panelRole,
        active: reallyAtivo,
        ativo: reallyAtivo,
        pendingApproval,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (cpf.length === 11) {
        await db
            .collection("tenants")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(indexPayload, { merge: true });
        await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(indexPayload, { merge: true });
    }
    return {
        ok: true,
        uid: authUid,
        panelRole,
        roleClaim,
        tenantId,
    };
});
/**
 * ✅ CPF → EMAIL (CALLABLE) (login CPF)
 */
exports.resolveCpfToEmail = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const cpf = normalizeCpf(String(data?.cpf || ""));
    if (cpf.length !== 11) {
        throw new functions.https.HttpsError("invalid-argument", "CPF inválido");
    }
    try {
        const publicFirst = await resolveFromPublicIndex(cpf);
        if (publicFirst?.email) {
            return {
                email: publicFirst.email,
                tenantId: publicFirst.tenantId,
                role: String(publicFirst.role || "user"),
            };
        }
        let snap = await db
            .collectionGroup("usersIndex")
            .where("cpf", "==", cpf)
            .limit(1)
            .get();
        if (snap.empty) {
            snap = await db
                .collectionGroup("usersIndex")
                .where(admin.firestore.FieldPath.documentId(), "==", cpf)
                .limit(1)
                .get();
        }
        if (!snap.empty) {
            const userDoc = snap.docs[0];
            const userData = userDoc.data() || {};
            const email = String(userData.email || "").trim().toLowerCase();
            const tenantId = String(userData.tenantId || userDoc.ref.parent.parent?.id || "");
            if (!email) {
                throw new functions.https.HttpsError("failed-precondition", "Usuário sem e-mail");
            }
            return { email, tenantId, role: String(userData.role || "user") };
        }
        /** Login por CPF: busca em igrejas/.../membros (e legado members) */
        let qMem = await db.collectionGroup("membros").where("CPF", "==", cpf).limit(15).get();
        if (qMem.empty) {
            qMem = await db.collectionGroup("membros").where("cpf", "==", cpf).limit(15).get();
        }
        if (qMem.empty) {
            qMem = await db.collectionGroup("members").where("CPF", "==", cpf).limit(15).get();
        }
        if (!qMem.empty) {
            const docs = [...qMem.docs].sort((a, b) => {
                const A = a.data().authUid ? 1 : 0;
                const B = b.data().authUid ? 1 : 0;
                return B - A;
            });
            const d = docs[0];
            const m = d.data();
            const parts = d.ref.path.split("/");
            const tid = parts[0] === "igrejas" && parts.length > 1 ? parts[1] : "";
            let emailOut = String(m.EMAIL || m.email || "").trim().toLowerCase();
            if (!emailOut.includes("@") && m.authUid) {
                try {
                    const u = await admin.auth().getUser(String(m.authUid));
                    if (u.email)
                        emailOut = u.email.toLowerCase();
                }
                catch {
                    /* ignore */
                }
            }
            if (!emailOut.includes("@")) {
                emailOut = `${cpf}@membro.gestaoyahweh.com.br`;
            }
            return { email: emailOut, tenantId: tid, role: "membro" };
        }
        throw new functions.https.HttpsError("not-found", "CPF não encontrado");
    }
    catch (e) {
        console.error("resolveCpfToEmail error:", e);
        if (e instanceof functions.https.HttpsError)
            throw e;
        throw new functions.https.HttpsError("internal", e?.message || "Erro interno");
    }
});
/**
 * ✅ MASTER — Definir perfil (role) do usuario
 * Atualiza custom claims e usersIndex
 */
exports.setUserRole = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || !canManageUsersRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM/GESTOR");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const callerTenantId = String(context.auth?.token?.igrejaId || "").trim();
    const cpf = String(data?.cpf || "").replace(/\D/g, "");
    const role = String(data?.role || "").trim().toUpperCase();
    ensureTenantScope(roleCaller, callerTenantId, tenantId);
    const allowed = ["MASTER", "GESTOR", "ADM", "LIDER", "USER"];
    if (!tenantId || cpf.length != 11 || !allowed.includes(role)) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId, cpf ou role invalidos");
    }
    if (roleCaller !== "MASTER" && role === "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Somente MASTER pode atribuir perfil MASTER");
    }
    const userIndexRef = db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf);
    const userIndexSnap = await userIndexRef.get();
    if (!userIndexSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Usuario nao encontrado");
    }
    const userIndex = userIndexSnap.data() || {};
    const email = String(userIndex.email || data?.email || "").trim();
    if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Usuario sem email valido");
    }
    const user = await admin.auth().getUserByEmail(email);
    const claims = (user.customClaims || {});
    await admin.auth().setCustomUserClaims(user.uid, {
        ...claims,
        role,
        igrejaId: tenantId,
    });
    await userIndexRef.set({
        role,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedByUid: context.auth.uid,
    }, { merge: true });
    await db
        .collection("users")
        .doc(user.uid)
        .set({
        role,
        igrejaId: tenantId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, uid: user.uid, role, tenantId };
});
/**
 * ✅ MASTER/ADM — Ativar/Inativar usuário
 * Atualiza usersIndex, users/{uid} e bloqueia login no Auth quando inativo.
 */
exports.setUserActive = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const canManage = canManageUsersRole(roleCaller);
    if (!context.auth || !canManage) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM/GESTOR");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const callerTenantId = String(context.auth?.token?.igrejaId || "").trim();
    const cpf = String(data?.cpf || "").replace(/\D/g, "");
    const active = data?.active === true;
    ensureTenantScope(roleCaller, callerTenantId, tenantId);
    if (!tenantId || cpf.length != 11) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId ou cpf inválidos");
    }
    const userIndexRef = db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf);
    const userIndexSnap = await userIndexRef.get();
    if (!userIndexSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Usuário não encontrado");
    }
    const userIndex = userIndexSnap.data() || {};
    const email = String(userIndex.email || "").trim();
    if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Usuário sem e-mail válido");
    }
    const user = await admin.auth().getUserByEmail(email);
    const claims = (user.customClaims || {});
    await admin.auth().setCustomUserClaims(user.uid, {
        ...claims,
        active,
        igrejaId: tenantId,
    });
    await admin.auth().updateUser(user.uid, { disabled: !active });
    await userIndexRef.set({
        active,
        registrationStatus: active ? "approved" : "inactive",
        approvedAt: active ? admin.firestore.FieldValue.serverTimestamp() : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedByUid: context.auth.uid,
    }, { merge: true });
    await db
        .collection("users")
        .doc(user.uid)
        .set({
        active,
        registrationStatus: active ? "approved" : "inactive",
        approvedAt: active ? admin.firestore.FieldValue.serverTimestamp() : null,
        igrejaId: tenantId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, uid: user.uid, tenantId, cpf, active };
});
/**
 * ✅ MASTER/ADM/GESTOR — Cadastro inteligente de usuário (cria/edita)
 */
exports.upsertTenantUser = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || !canManageUsersRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM/GESTOR");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const callerTenantId = String(context.auth?.token?.igrejaId || "").trim();
    ensureTenantScope(roleCaller, callerTenantId, tenantId);
    const cpf = normalizeCpf(String(data?.cpf || ""));
    const name = String(data?.name || "").trim();
    const email = String(data?.email || "").trim().toLowerCase();
    const phone = String(data?.phone || "").trim();
    const photoUrl = String(data?.photoUrl || "").trim();
    const gender = normalizeGender(String(data?.gender || data?.sexo || ""));
    const role = String(data?.role || "USER").trim().toUpperCase();
    const active = data?.active !== false;
    const isDriver = data?.isDriver === true;
    const isUser = data?.isUser !== false;
    const allowedRoles = ["MASTER", "GESTOR", "ADM", "LIDER", "USER"];
    if (!tenantId || cpf.length !== 11 || !name || !email.includes("@") || !allowedRoles.includes(role)) {
        throw new functions.https.HttpsError("invalid-argument", "Dados inválidos (tenantId/cpf/nome/email/perfil)");
    }
    if (roleCaller !== "MASTER" && role === "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Somente MASTER pode atribuir perfil MASTER");
    }
    let authUser = null;
    try {
        authUser = await admin.auth().getUserByEmail(email);
    }
    catch (_) {
        authUser = null;
    }
    if (!authUser && isUser) {
        const tempPassword = `Gyh@${cpf.substring(cpf.length - 6)}!`;
        authUser = await admin.auth().createUser({
            email,
            password: tempPassword,
            displayName: name,
            disabled: !active,
        });
    }
    const uid = authUser?.uid || "";
    if (authUser) {
        const currentClaims = (authUser.customClaims || {});
        await admin.auth().setCustomUserClaims(authUser.uid, {
            ...currentClaims,
            role,
            igrejaId: tenantId,
            active,
            isDriver,
            isUser,
        });
        await admin.auth().updateUser(authUser.uid, {
            displayName: name,
            disabled: !active,
        });
        await db.collection("users").doc(authUser.uid).set({
            uid: authUser.uid,
            cpf,
            name,
            email,
            phone,
            photoUrl,
            fotoUrl: photoUrl,
            FOTO_URL_OU_ID: photoUrl,
            gender,
            sexo: gender,
            role,
            igrejaId: tenantId,
            active,
            isDriver,
            isUser,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedByUid: context.auth.uid,
        }, { merge: true });
    }
    await db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf)
        .set({
        uid,
        cpf,
        name,
        nome: name,
        email,
        phone,
        photoUrl,
        fotoUrl: photoUrl,
        FOTO_URL_OU_ID: photoUrl,
        gender,
        sexo: gender,
        role,
        tenantId,
        active,
        isDriver,
        isUser,
        mustChangePass: !authUser,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedByUid: context.auth.uid,
    }, { merge: true });
    return {
        ok: true,
        tenantId,
        cpf,
        uid,
        createdAuthUser: !!authUser,
        role,
        active,
        isDriver,
        isUser,
    };
});
/**
 * ✅ MASTER/ADM/GESTOR — Gera convite de cadastro de usuário com validade
 */
exports.createUserSignupInvite = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || !canManageUsersRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER/ADM/GESTOR");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const callerTenantId = String(context.auth?.token?.igrejaId || "").trim();
    ensureTenantScope(roleCaller, callerTenantId, tenantId);
    const cpf = normalizeCpf(String(data?.cpf || ""));
    const expiresInDaysRaw = Number(data?.expiresInDays || 1);
    const expiresInDays = Math.max(1, Math.min(30, Math.floor(expiresInDaysRaw || 1)));
    const baseUrl = String(data?.baseUrl || "").trim().replace(/\/$/, "");
    if (!tenantId || cpf.length !== 11) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId/cpf inválidos");
    }
    const userIndexRef = db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf);
    const userIndexSnap = await userIndexRef.get();
    if (!userIndexSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Usuário não encontrado no usersIndex");
    }
    const userIndex = userIndexSnap.data() || {};
    const email = String(userIndex.email || "").trim().toLowerCase();
    const name = String(userIndex.name || userIndex.nome || "").trim();
    const role = String(userIndex.role || "USER").trim().toUpperCase();
    const isDriver = userIndex.isDriver === true;
    const isUser = userIndex.isUser !== false;
    if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Usuário sem e-mail válido para convite");
    }
    const token = db.collection("_tokens").doc().id;
    const nowMs = Date.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(nowMs + expiresInDays * 24 * 60 * 60 * 1000);
    const inviteRef = db
        .collection("tenants")
        .doc(tenantId)
        .collection("userSignupInvites")
        .doc(token);
    await inviteRef.set({
        token,
        tenantId,
        cpf,
        email,
        name,
        role,
        isDriver,
        isUser,
        gender: normalizeGender(String(userIndex.gender || userIndex.sexo || "")),
        sexo: normalizeGender(String(userIndex.gender || userIndex.sexo || "")),
        allowedProfileTypes: ["MOTORISTA", "USUARIO"],
        defaultProfileType: "MOTORISTA",
        status: "pending",
        active: true,
        expiresAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdByUid: context.auth.uid,
        usedAt: null,
        usedByUid: null,
    });
    await userIndexRef.set({
        inviteLastToken: token,
        inviteStatus: "pending",
        inviteExpiresAt: expiresAt,
        inviteUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const inviteUrl = baseUrl
        ? `${baseUrl}/invite-signup?token=${encodeURIComponent(token)}`
        : `https://gestaoyahweh-21e23.web.app/invite-signup?token=${encodeURIComponent(token)}`;
    return {
        ok: true,
        token,
        tenantId,
        cpf,
        email,
        expiresInDays,
        expiresAt: expiresAt.toDate().toISOString(),
        inviteUrl,
    };
});
/**
 * ✅ PUBLIC — Pré-visualiza convite de cadastro de usuário
 */
exports.getUserSignupInviteInfo = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const token = String(data?.token || "").trim();
    if (!token) {
        throw new functions.https.HttpsError("invalid-argument", "token obrigatório");
    }
    let snap = await db.collectionGroup("userSignupInvites")
        .where(admin.firestore.FieldPath.documentId(), "==", token)
        .limit(1)
        .get();
    if (snap.empty) {
        throw new functions.https.HttpsError("not-found", "Convite não encontrado");
    }
    const ref = snap.docs[0];
    const inv = ref.data() || {};
    const expiresAt = toDateSafe(inv.expiresAt);
    const usedAt = toDateSafe(inv.usedAt);
    const now = new Date();
    if (inv.active === false || String(inv.status || "") === "cancelled") {
        throw new functions.https.HttpsError("failed-precondition", "Convite inativo");
    }
    if (usedAt) {
        throw new functions.https.HttpsError("failed-precondition", "Convite já utilizado");
    }
    if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
        throw new functions.https.HttpsError("deadline-exceeded", "Convite expirado");
    }
    return {
        ok: true,
        token,
        tenantId: String(inv.tenantId || ""),
        cpf: String(inv.cpf || ""),
        name: String(inv.name || ""),
        email: String(inv.email || ""),
        role: String(inv.role || "USER"),
        isDriver: inv.isDriver === true,
        isUser: inv.isUser !== false,
        gender: normalizeGender(String(inv.gender || inv.sexo || "")),
        sexo: normalizeGender(String(inv.gender || inv.sexo || "")),
        allowedProfileTypes: ["MOTORISTA", "USUARIO"],
        defaultProfileType: "MOTORISTA",
        expiresAt: expiresAt.toISOString(),
        canRegister: true,
    };
});
/**
 * ✅ PUBLIC — Consome convite e cria/atualiza usuário com senha definida
 */
exports.consumeUserSignupInvite = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const token = String(data?.token || "").trim();
    const password = String(data?.password || "");
    const profileType = String(data?.profileType || "MOTORISTA").trim().toUpperCase();
    const gender = normalizeGender(String(data?.gender || data?.sexo || ""));
    const photoUrl = String(data?.photoUrl || "").trim();
    if (!token || password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "token/senha inválidos");
    }
    if (!["MOTORISTA", "USUARIO"].includes(profileType)) {
        throw new functions.https.HttpsError("invalid-argument", "profileType inválido");
    }
    const q = await db
        .collectionGroup("userSignupInvites")
        .where(admin.firestore.FieldPath.documentId(), "==", token)
        .limit(1)
        .get();
    if (q.empty) {
        throw new functions.https.HttpsError("not-found", "Convite não encontrado");
    }
    const inviteDoc = q.docs[0];
    const inv = inviteDoc.data() || {};
    const tenantId = String(inv.tenantId || "").trim();
    const cpf = normalizeCpf(String(inv.cpf || ""));
    const email = String(inv.email || "").trim().toLowerCase();
    const name = String(inv.name || "").trim();
    const role = "USER";
    const isDriver = profileType === "MOTORISTA";
    const isUser = profileType === "USUARIO";
    const active = false;
    const expiresAt = toDateSafe(inv.expiresAt);
    const usedAt = toDateSafe(inv.usedAt);
    const now = new Date();
    if (!tenantId || cpf.length !== 11 || !email.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Convite inválido");
    }
    if (inv.active === false || String(inv.status || "") === "cancelled") {
        throw new functions.https.HttpsError("failed-precondition", "Convite inativo");
    }
    if (usedAt) {
        throw new functions.https.HttpsError("already-exists", "Convite já utilizado");
    }
    if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
        throw new functions.https.HttpsError("deadline-exceeded", "Convite expirado");
    }
    const userIndexRef = db
        .collection("tenants")
        .doc(tenantId)
        .collection("usersIndex")
        .doc(cpf);
    const userIndexSnap = await userIndexRef.get();
    if (!userIndexSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Usuário não encontrado no tenant");
    }
    let authUser = null;
    try {
        authUser = await admin.auth().getUserByEmail(email);
    }
    catch (_) {
        authUser = null;
    }
    if (!authUser) {
        authUser = await admin.auth().createUser({
            email,
            password,
            displayName: name,
            disabled: !active,
        });
    }
    else {
        await admin.auth().updateUser(authUser.uid, {
            password,
            displayName: name || authUser.displayName || undefined,
            disabled: !active,
        });
    }
    const claims = (authUser.customClaims || {});
    await admin.auth().setCustomUserClaims(authUser.uid, {
        ...claims,
        role,
        igrejaId: tenantId,
        active,
        isDriver,
        isUser,
    });
    await db.collection("users").doc(authUser.uid).set({
        uid: authUser.uid,
        cpf,
        name,
        email,
        photoUrl,
        fotoUrl: photoUrl,
        FOTO_URL_OU_ID: photoUrl,
        gender,
        sexo: gender,
        role,
        igrejaId: tenantId,
        active,
        isDriver,
        isUser,
        registrationStatus: "pending_admin_approval",
        approvedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await userIndexRef.set({
        uid: authUser.uid,
        cpf,
        name,
        nome: name,
        email,
        photoUrl,
        fotoUrl: photoUrl,
        FOTO_URL_OU_ID: photoUrl,
        gender,
        sexo: gender,
        role,
        tenantId,
        active,
        isDriver,
        isUser,
        mustChangePass: false,
        inviteStatus: "used",
        inviteUsedAt: admin.firestore.FieldValue.serverTimestamp(),
        inviteChosenProfileType: profileType,
        registrationStatus: "pending_admin_approval",
        approvedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await inviteDoc.ref.set({
        active: false,
        status: "used",
        chosenProfileType: profileType,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        usedByUid: authUser.uid,
    }, { merge: true });
    return {
        ok: true,
        tenantId,
        cpf,
        email,
        uid: authUser.uid,
    };
});
/**
 * ✅ Cadastro rápido gestor com Google — cria igreja + vincula usuário Google como gestor, trial 30 dias.
 * Chamado após login Google quando o usuário ainda não tem igreja. Exige auth.
 */
function slugify(text) {
    return String(text || "")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_|_$/g, "") || "igreja";
}
exports.createChurchAndGestorWithGoogle = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    try {
        return await createChurchAndGestorWithGoogleImpl(data, context);
    }
    catch (e) {
        console.error("createChurchAndGestorWithGoogle:", e);
        if (e instanceof functions.https.HttpsError) {
            throw e;
        }
        const msg = e instanceof Error
            ? e.message
            : typeof e === "string"
                ? e
                : "Erro inesperado ao criar igreja.";
        throw new functions.https.HttpsError("failed-precondition", msg.length > 380 ? `${msg.slice(0, 380)}…` : msg);
    }
});
/** Núcleo compartilhado: cria igreja + trial + claims + users + membros/{uid} (gestor já validado). */
async function finalizeNewChurchForGestorCore(params) {
    const { uid, email, nome, cpfRaw, igrejaNome, igrejaDoc } = params;
    const baseSlug = slugify(igrejaNome);
    let slug = baseSlug;
    let idx = 0;
    while (true) {
        const byField = await db.collection("igrejas").where("slug", "==", slug).limit(1).get();
        const byDocId = await db.collection("igrejas").doc(slug).get();
        if (byField.empty && !byDocId.exists) {
            break;
        }
        idx++;
        slug = `${baseSlug}_${idx}`;
    }
    const tenantId = slug;
    const trialEndsAt = new Date();
    trialEndsAt.setDate(trialEndsAt.getDate() + 30);
    const trialTimestamp = admin.firestore.Timestamp.fromDate(trialEndsAt);
    const igrejaPayload = {
        nome: igrejaNome,
        name: igrejaNome,
        slug,
        /** Chave única da igreja no Firestore (= id do doc). Notícias, eventos e escalas ficam em subcoleções deste id. */
        igrejaId: tenantId,
        tenantId,
        churchId: tenantId,
        cnpjCpf: igrejaDoc || null,
        ativa: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("igrejas").doc(tenantId).set(igrejaPayload, { merge: true });
    // Padrão tenant: alias, cpf, email, name, nome, slug, updatedAt (logo não obrigatório no começo).
    // registrationComplete: false → exige completar cadastro da igreja no painel antes de qualquer lançamento.
    await db.collection("tenants").doc(tenantId).set({
        name: igrejaNome,
        nome: igrejaNome,
        slug,
        alias: slug,
        cpf: cpfRaw,
        email,
        registrationComplete: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.collection("subscriptions").add({
        igrejaId: tenantId,
        planId: "PRO",
        status: "TRIAL",
        trialEndsAt: trialTimestamp,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await admin.auth().setCustomUserClaims(uid, {
        role: "GESTOR",
        igrejaId: tenantId,
        active: true,
        isUser: true,
        isDriver: false,
    });
    await db.collection("users").doc(uid).set({
        uid,
        cpf: cpfRaw,
        name: nome,
        nome: nome,
        email,
        role: "GESTOR",
        igrejaId: tenantId,
        tenantId,
        ativo: true,
        active: true,
        mustChangePass: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const usersIndexRef = db.collection("tenants").doc(tenantId).collection("usersIndex").doc(cpfRaw);
    await usersIndexRef.set({
        uid,
        cpf: cpfRaw,
        name: nome,
        nome: nome,
        email,
        role: "GESTOR",
        tenantId,
        active: true,
        ativo: true,
        mustChangePass: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    /** Ficha única em membros com id = UID do Firebase (evita duplicar gestor como membros/{cpf}). */
    await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("membros")
        .doc(uid)
        .set({
        MEMBER_ID: uid,
        authUid: uid,
        NOME_COMPLETO: nome,
        nome,
        name: nome,
        EMAIL: email,
        email,
        CPF: cpfRaw,
        cpf: cpfRaw,
        FUNCAO: "adm",
        FUNCOES: ["adm"],
        CARGO: "Administrador",
        role: "adm",
        STATUS: "ativo",
        status: "ativo",
        GESTOR_SYNC: true,
        tenantId,
        igrejaId: tenantId,
        CRIADO_EM: admin.firestore.FieldValue.serverTimestamp(),
        ATUALIZADO_EM: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    try {
        await (0, churchWelcomeSeed_1.ensureChurchWelcomeSeed)(db, tenantId);
    }
    catch (e) {
        console.error("finalizeNewChurchForGestorCore ensureChurchWelcomeSeed:", e);
    }
    return {
        ok: true,
        igrejaSlug: slug,
        tenantId,
        trialEndsAt: trialEndsAt.toISOString(),
        message: "Igreja criada. Teste grátis por 30 dias com acesso total.",
    };
}
async function createChurchAndGestorWithGoogleImpl(data, context) {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login com Google ou Apple primeiro (mesma tela de cadastro rápido).");
    }
    const uid = context.auth.uid;
    const email = String(context.auth.token?.email || "").trim().toLowerCase();
    const displayName = String(context.auth.token?.name || "").trim();
    if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError("failed-precondition", "Sua conta não retornou e-mail verificado. No Google, permita o acesso ao e-mail ou use cadastro com e-mail e senha.");
    }
    const userSnapEarly = await db.collection("users").doc(uid).get();
    const prevIgreja = String(userSnapEarly.data()?.igrejaId ||
        userSnapEarly.data()?.tenantId ||
        "").trim();
    if (prevIgreja) {
        throw new functions.https.HttpsError("already-exists", "Esta conta já possui uma igreja vinculada. Use Entrar para acessar o painel.");
    }
    const igrejaNome = String(data?.igrejaNome || "").trim();
    const igrejaDoc = String(data?.igrejaDoc || "").trim();
    const nome = String(data?.nome || displayName || "").trim();
    const cpfRaw = normalizeCpf(String(data?.cpf || ""));
    if (!igrejaNome) {
        throw new functions.https.HttpsError("invalid-argument", "Informe o nome da igreja.");
    }
    if (!nome) {
        throw new functions.https.HttpsError("invalid-argument", "Informe seu nome.");
    }
    if (cpfRaw.length !== 11) {
        throw new functions.https.HttpsError("invalid-argument", "CPF deve ter 11 dígitos.");
    }
    return finalizeNewChurchForGestorCore({
        uid,
        email,
        nome,
        cpfRaw,
        igrejaNome,
        igrejaDoc,
    });
}
/**
 * Etapa 1 do onboarding: salva nome e CPF no users/{uid} sem igreja (perfil futuro gestor).
 */
exports.registerGestorProfile = functions.region("us-central1").https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login primeiro.");
        }
        const uid = context.auth.uid;
        const email = String(context.auth.token?.email || "").trim().toLowerCase();
        if (!email || !email.includes("@")) {
            throw new functions.https.HttpsError("failed-precondition", "É necessário um e-mail na conta. Use Google com e-mail liberado ou cadastro por e-mail e senha.");
        }
        const userSnapEarly = await db.collection("users").doc(uid).get();
        const prevIgreja = String(userSnapEarly.data()?.igrejaId ||
            userSnapEarly.data()?.tenantId ||
            "").trim();
        if (prevIgreja) {
            throw new functions.https.HttpsError("already-exists", "Esta conta já possui uma igreja vinculada.");
        }
        const displayName = String(context.auth.token?.name || "").trim();
        const nome = String(data?.nome || displayName || "").trim();
        const cpfRaw = normalizeCpf(String(data?.cpf || ""));
        if (!nome) {
            throw new functions.https.HttpsError("invalid-argument", "Informe seu nome completo.");
        }
        if (cpfRaw.length !== 11) {
            throw new functions.https.HttpsError("invalid-argument", "CPF deve ter 11 dígitos.");
        }
        await db.collection("users").doc(uid).set({
            uid,
            email,
            name: nome,
            nome,
            cpf: cpfRaw,
            role: "GESTOR",
            ativo: true,
            active: true,
            mustChangePass: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true };
    }
    catch (e) {
        console.error("registerGestorProfile:", e);
        if (e instanceof functions.https.HttpsError) {
            throw e;
        }
        const msg = e instanceof Error ? e.message : "Erro ao salvar perfil.";
        throw new functions.https.HttpsError("failed-precondition", msg.length > 380 ? `${msg.slice(0, 380)}…` : msg);
    }
});
/**
 * Etapa 2: cria igreja usando nome/CPF já salvos em users (após registerGestorProfile).
 */
exports.createChurchForOnboardingGestor = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login primeiro.");
        }
        const uid = context.auth.uid;
        const email = String(context.auth.token?.email || "").trim().toLowerCase();
        if (!email || !email.includes("@")) {
            throw new functions.https.HttpsError("failed-precondition", "É necessário um e-mail na conta.");
        }
        const userSnapEarly = await db.collection("users").doc(uid).get();
        const prev = userSnapEarly.data();
        const prevIgreja = String(prev?.igrejaId || prev?.tenantId || "").trim();
        if (prevIgreja) {
            throw new functions.https.HttpsError("already-exists", "Esta conta já possui uma igreja vinculada.");
        }
        const nome = String(prev?.nome || prev?.name || "").trim();
        const cpfRaw = normalizeCpf(String(prev?.cpf || ""));
        if (!nome) {
            throw new functions.https.HttpsError("failed-precondition", "Complete seu nome e CPF na etapa anterior (perfil de gestor).");
        }
        if (cpfRaw.length !== 11) {
            throw new functions.https.HttpsError("failed-precondition", "CPF inválido no perfil. Refaça a etapa de dados pessoais.");
        }
        const igrejaNome = String(data?.igrejaNome || "").trim();
        const igrejaDoc = String(data?.igrejaDoc || "").trim();
        if (!igrejaNome) {
            throw new functions.https.HttpsError("invalid-argument", "Informe o nome da igreja.");
        }
        return await finalizeNewChurchForGestorCore({
            uid,
            email,
            nome,
            cpfRaw,
            igrejaNome,
            igrejaDoc,
        });
    }
    catch (e) {
        console.error("createChurchForOnboardingGestor:", e);
        if (e instanceof functions.https.HttpsError) {
            throw e;
        }
        const msg = e instanceof Error
            ? e.message
            : typeof e === "string"
                ? e
                : "Erro inesperado ao criar igreja.";
        throw new functions.https.HttpsError("failed-precondition", msg.length > 380 ? `${msg.slice(0, 380)}…` : msg);
    }
});
/**
 * ✅ ONE-OFF — Acrescenta perfil GESTOR ao RAIHOM na igreja Brasil para Cristo.
 * Cadastro em members já existe; a função cria/atualiza Auth, usersIndex e só faz merge do perfil em members.
 */
const SEED_GESTOR_PARAM = (0, params_1.defineString)("SEED_GESTOR_SECRET", { default: "" });
exports.seedGestorBrasilParaCristo = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const secret = String(SEED_GESTOR_PARAM.value() || "").trim();
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const isMaster = !!context.auth && (roleCaller === "MASTER" || context.auth?.token?.email === "raihom@gmail.com");
    const secretMatch = secret && String(data?.secret || "") === secret;
    if (!context.auth && !secretMatch) {
        throw new functions.https.HttpsError("unauthenticated", "Login ou secret obrigatório");
    }
    if (!isMaster && !secretMatch) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito");
    }
    const tenantId = "brasilparacristo_sistema";
    const cpf = "94536368191";
    const email = "raihom@gmail.com";
    const password = "ca341982";
    const name = "RAIHOM SEVERINO BARBOSA";
    const role = "GESTOR";
    const dataNascimento = "18/10/1982";
    const mae = "MARIA DE FATIMA SEVERINA BARBOSA";
    let authUser = null;
    try {
        authUser = await admin.auth().getUserByEmail(email);
    }
    catch (_) {
        authUser = null;
    }
    if (!authUser) {
        authUser = await admin.auth().createUser({
            email,
            password,
            displayName: name,
            emailVerified: false,
        });
    }
    else {
        await admin.auth().updateUser(authUser.uid, { password, displayName: name });
    }
    await admin.auth().setCustomUserClaims(authUser.uid, {
        role,
        igrejaId: tenantId,
        active: true,
        isUser: true,
        isDriver: false,
    });
    const usersIndexRef = db.collection("tenants").doc(tenantId).collection("usersIndex").doc(cpf);
    await usersIndexRef.set({
        uid: authUser.uid,
        cpf,
        name,
        nome: name,
        email,
        role,
        tenantId,
        active: true,
        isUser: true,
        isDriver: false,
        mustChangePass: false,
        dataNascimento: dataNascimento,
        mae: mae,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Já existe cadastro em members — só acrescentar perfil gestor (merge para não sobrescrever)
    const membersRef = db.collection("tenants").doc(tenantId).collection("members").doc(cpf);
    await membersRef.set({
        role,
        profile: "gestor",
        perfil: "GESTOR",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.collection("users").doc(authUser.uid).set({
        uid: authUser.uid,
        cpf,
        name,
        email,
        role,
        igrejaId: tenantId,
        active: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        ok: true,
        tenantId,
        cpf,
        email,
        uid: authUser.uid,
        role,
        message: "Usuário GESTOR criado/atualizado. Use raihom@gmail.com e a senha informada para acessar a igreja Brasil para Cristo.",
    };
});
/**
 * Sincroniza apenas o usuário atual (raihom@gmail.com): custom claims + users + usersIndex.
 * Use quando você já é gestor no tenant mas o app não reconhece o vínculo (claims/users desatualizados).
 */
exports.syncGestorBrasilParaCristo = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const email = String(context.auth.token?.email || "").toLowerCase();
    if (email !== "raihom@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "Apenas o gestor Brasil para Cristo pode usar esta função.");
    }
    const tenantId = "brasilparacristo_sistema";
    const cpf = "94536368191";
    const gestorName = "RAIHOM SEVERINO BARBOSA";
    const uid = context.auth.uid;
    await admin.auth().setCustomUserClaims(uid, {
        role: "GESTOR",
        igrejaId: tenantId,
        active: true,
        isUser: true,
        isDriver: false,
    });
    await db.collection("users").doc(uid).set({
        uid,
        cpf,
        name: gestorName,
        nome: gestorName,
        email: email,
        role: "GESTOR",
        igrejaId: tenantId,
        tenantId,
        ativo: true,
        active: true,
        mustChangePass: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const usersIndexRef = db.collection("tenants").doc(tenantId).collection("usersIndex").doc(cpf);
    await usersIndexRef.set({
        uid,
        cpf,
        name: gestorName,
        nome: gestorName,
        email: email,
        role: "GESTOR",
        tenantId,
        active: true,
        ativo: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, message: "Acesso sincronizado. Faça logout e login de novo ou use o botão para atualizar." };
});
const MEMBER_DEFAULT_PASSWORD = "123456";
const MEMBRO_EMAIL_DOMAIN = "membro.gestaoyahweh.com.br";
/** Copia objetos em `igrejas/{tid}/membros/{from}/**` para `.../membros/{to}/**` (foto, assinatura…). */
async function copyIgrejaMembroStorageFolder(tenantId, fromFolderId, toFolderId) {
    if (!fromFolderId || !toFolderId || fromFolderId === toFolderId)
        return;
    try {
        const bucket = admin.storage().bucket();
        const prefix = `igrejas/${tenantId}/membros/${fromFolderId}/`;
        const [files] = await bucket.getFiles({ prefix });
        for (const f of files) {
            const rel = f.name.startsWith(prefix) ? f.name.slice(prefix.length) : "";
            if (!rel)
                continue;
            const dest = `igrejas/${tenantId}/membros/${toFolderId}/${rel}`;
            await bucket.file(f.name).copy(bucket.file(dest));
        }
    }
    catch (e) {
        console.warn("copyIgrejaMembroStorageFolder", tenantId, fromFolderId, toFolderId, e);
    }
}
/** Claims + `users/` + `usersIndex` por CPF após login Firebase criado (idempotente com merge). */
async function applyMemberAuthSideEffects(tenantId, authUid, memberData, authUser) {
    const status = String(memberData.STATUS || memberData.status || "").toLowerCase();
    const reallyAtivo = status === "ativo" || (status !== "pendente" && status !== "reprovado");
    const cpf = String(memberData.CPF || memberData.cpf || "").replace(/\D/g, "");
    const nome = String(memberData.NOME_COMPLETO || memberData.nome || memberData.name || "").trim();
    await admin.auth().setCustomUserClaims(authUid, {
        role: "membro",
        igrejaId: tenantId,
        tenantId,
        active: reallyAtivo,
        isUser: true,
        isDriver: false,
        pendingApproval: status === "pendente",
        // Firestore rules: troca de escala / confirmação usam CPF quando users/{uid}.cpf ainda vazio
        ...(cpf.length === 11 ? { cpf } : {}),
    });
    await db.collection("users").doc(authUid).set({
        email: String(authUser.email || "")
            .trim()
            .toLowerCase(),
        cpf: cpf.length === 11 ? cpf : "",
        igrejaId: tenantId,
        tenantId,
        role: "membro",
        nome,
        displayName: nome,
        nomeCompleto: nome,
        ativo: reallyAtivo,
    }, { merge: true });
    const indexPayload = {
        uid: authUid,
        cpf: cpf.length === 11 ? cpf : "",
        email: String(authUser.email || "")
            .trim()
            .toLowerCase(),
        name: nome,
        nome,
        tenantId,
        role: "membro",
        active: reallyAtivo,
        pendingApproval: status === "pendente",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (cpf.length === 11) {
        await db
            .collection("tenants")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(indexPayload, { merge: true });
        await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(indexPayload, { merge: true });
    }
}
/** Busca membro em igrejas/.../membros (id, authUid ou CPF), depois coleções legadas. */
async function findMemberDocument(tenantId, memberId) {
    const tid = String(tenantId || "").trim();
    const mid = String(memberId || "").trim();
    if (!tid || !mid)
        return null;
    const membrosCol = db.collection("igrejas").doc(tid).collection("membros");
    const direct = await membrosCol.doc(mid).get();
    if (direct.exists)
        return { ref: direct.ref, data: direct.data() || {} };
    const byAuth = await membrosCol.where("authUid", "==", mid).limit(1).get();
    if (!byAuth.empty) {
        const d = byAuth.docs[0];
        return { ref: d.ref, data: d.data() || {} };
    }
    const cpf = normalizeCpf(mid);
    if (cpf.length === 11) {
        let q = await membrosCol.where("CPF", "==", cpf).limit(1).get();
        if (!q.empty) {
            const d = q.docs[0];
            return { ref: d.ref, data: d.data() || {} };
        }
        q = await membrosCol.where("cpf", "==", cpf).limit(1).get();
        if (!q.empty) {
            const d = q.docs[0];
            return { ref: d.ref, data: d.data() || {} };
        }
        const byCpfDoc = await membrosCol.doc(cpf).get();
        if (byCpfDoc.exists)
            return { ref: byCpfDoc.ref, data: byCpfDoc.data() || {} };
    }
    const legacy = [
        db.collection("igrejas").doc(tid).collection("members").doc(mid),
        db.collection("tenants").doc(tid).collection("members").doc(mid),
    ];
    for (const ref of legacy) {
        const snap = await ref.get();
        if (snap.exists)
            return { ref, data: snap.data() || {} };
    }
    return null;
}
/**
 * Cria Firebase Auth (UID gerado pelo Firebase), grava users + usersIndex e move o doc de
 * `membros/{cpf|auto}` para `membros/{uid}` para id === UID. Senha padrão 123456.
 */
async function ensureMemberFirebaseAuth(tenantId, memberId, memberRef, memberData) {
    const existingUid = String(memberData.authUid || "").trim();
    if (existingUid) {
        try {
            const u = await admin.auth().getUser(existingUid);
            const curId = memberRef.id;
            let finalRef = memberRef;
            let migratedFrom;
            if (curId !== u.uid) {
                await copyIgrejaMembroStorageFolder(tenantId, curId, u.uid);
                const payload = {
                    ...memberData,
                    authUid: u.uid,
                    MEMBER_ID: u.uid,
                    legacyMemberDocId: curId,
                    // Mantém URLs legadas para evitar "sumiço" da foto se a cópia
                    // de Storage atrasar/falhar em algum ambiente.
                    photoStoragePath: `igrejas/${tenantId}/membros/${u.uid}/foto_perfil.jpg`,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                const newRef = memberRef.parent.doc(u.uid);
                // FieldValue.delete() exige set/update com merge:true (Firestore rejeita merge:false).
                await newRef.set(payload, { merge: true });
                await memberRef.delete();
                finalRef = newRef;
                migratedFrom = curId;
            }
            const snapEx = await finalRef.get();
            await applyMemberAuthSideEffects(tenantId, u.uid, snapEx.data() || memberData, u);
            return {
                uid: u.uid,
                email: u.email || "",
                alreadyHad: true,
                membroFirestoreId: finalRef.id,
                migratedFrom,
            };
        }
        catch {
            // authUid inválido — recria abaixo
        }
    }
    const emailRaw = String(memberData.EMAIL || memberData.email || "").trim();
    const cpf = String(memberData.CPF || memberData.cpf || "").replace(/\D/g, "");
    const nome = String(memberData.NOME_COMPLETO || memberData.nome || memberData.name || "").trim();
    let email = emailRaw.includes("@") ? emailRaw.toLowerCase() : "";
    if (!email && cpf.length === 11) {
        email = `${cpf}@${MEMBRO_EMAIL_DOMAIN}`;
    }
    if (!email) {
        throw new functions.https.HttpsError("invalid-argument", "Membro precisa de e-mail ou CPF para criar login.");
    }
    const oldDocId = memberRef.id;
    let authUser;
    try {
        authUser = await admin.auth().createUser({
            email,
            password: MEMBER_DEFAULT_PASSWORD,
            displayName: nome || undefined,
            emailVerified: false,
        });
    }
    catch (err) {
        const anyErr = err;
        if (anyErr?.code === "auth/email-already-exists") {
            authUser = await admin.auth().getUserByEmail(email);
            await admin.auth().updateUser(authUser.uid, { password: MEMBER_DEFAULT_PASSWORD });
        }
        else {
            throw new functions.https.HttpsError("internal", anyErr?.message || String(err) || "Erro ao criar usuário.");
        }
    }
    const authUid = authUser.uid;
    let finalRef = memberRef;
    if (oldDocId !== authUid) {
        await copyIgrejaMembroStorageFolder(tenantId, oldDocId, authUid);
        const merged = {
            ...memberData,
            authUid,
            MEMBER_ID: authUid,
            legacyMemberDocId: oldDocId,
            // Mantém URLs legadas para evitar perder foto/avatar durante migração de docId.
            photoStoragePath: `igrejas/${tenantId}/membros/${authUid}/foto_perfil.jpg`,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        const newRef = memberRef.parent.doc(authUid);
        await newRef.set(merged, { merge: true });
        await memberRef.delete();
        finalRef = newRef;
    }
    else {
        await finalRef.set({
            authUid,
            MEMBER_ID: authUid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    const snapFinal = await finalRef.get();
    await applyMemberAuthSideEffects(tenantId, authUid, snapFinal.data() || memberData, authUser);
    return {
        uid: authUid,
        email: authUser.email || email,
        alreadyHad: false,
        membroFirestoreId: finalRef.id,
        migratedFrom: oldDocId !== authUid ? oldDocId : undefined,
    };
}
/**
 * Gestor: cria primeiro o Firebase Auth (UID) para depois gravar `igrejas/{tid}/membros/{uid}`.
 * CPF continua só como campo no documento — não como id do doc.
 */
exports.createMemberAuthAccountForGestor = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const emailRaw = String(data?.email || "").trim().toLowerCase();
    const password = String(data?.password || "").trim();
    const displayName = String(data?.displayName || "").trim();
    const cpf = normalizeCpf(String(data?.cpf || ""));
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
    }
    const callerUid = context.auth.uid;
    const can = await canManageTenant(callerUid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!can) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para cadastrar membros nesta igreja.");
    }
    let email = emailRaw.includes("@") ? emailRaw : "";
    if (!email && cpf.length === 11) {
        email = `${cpf}@${MEMBRO_EMAIL_DOMAIN}`;
    }
    if (!email) {
        throw new functions.https.HttpsError("invalid-argument", "Informe e-mail ou CPF com 11 dígitos para criar o login.");
    }
    const pwd = password.length >= 6 ? password : MEMBER_DEFAULT_PASSWORD;
    try {
        const authUser = await admin.auth().createUser({
            email,
            password: pwd,
            displayName: displayName || undefined,
            emailVerified: false,
        });
        return { ok: true, uid: authUser.uid, email: authUser.email };
    }
    catch (err) {
        const anyErr = err;
        if (anyErr?.code === "auth/email-already-exists") {
            throw new functions.https.HttpsError("already-exists", "Este e-mail já possui conta. Use outro e-mail ou vincule o cadastro existente.");
        }
        throw new functions.https.HttpsError("internal", anyErr?.message || String(err) || "Erro ao criar login.");
    }
});
/**
 * Cria login (Firebase Auth) após cadastro em igrejas/{tenantId}/membros (público ou interno).
 * E-mail da pessoa + senha 123456. Pendente: bloqueado no app até aprovação do gestor.
 */
exports.createMemberLoginFromPublic = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const tenantId = String(data?.tenantId || "").trim();
    const memberId = String(data?.memberId || "").trim();
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId são obrigatórios.");
    }
    const found = await findMemberDocument(tenantId, memberId);
    if (!found) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado em igrejas/.../membros.");
    }
    const memberData = found.data;
    const status = String(memberData.STATUS || memberData.status || "").toLowerCase();
    if (memberData.authUid) {
        const uid = String(memberData.authUid).trim();
        let authUser;
        try {
            authUser = await admin.auth().getUser(uid);
        }
        catch {
            throw new functions.https.HttpsError("failed-precondition", "Campo authUid no cadastro não corresponde a uma conta no Firebase Auth.");
        }
        const snap = await found.ref.get();
        await applyMemberAuthSideEffects(tenantId, uid, snap.data() || memberData, authUser);
        const em = String(memberData.EMAIL || memberData.email || authUser.email || "").trim();
        return {
            ok: true,
            uid,
            email: em,
            message: "Login sincronizado.",
            membroFirestoreId: found.ref.id,
        };
    }
    if (status === "reprovado") {
        throw new functions.https.HttpsError("failed-precondition", "Cadastro reprovado.");
    }
    /** Cadastro público pendente: Auth + senha 123456 só após o gestor aprovar (`setMemberApproved`). */
    const publicSignup = memberData.PUBLIC_SIGNUP === true || memberData.public_signup === true;
    if (publicSignup && status === "pendente") {
        return {
            ok: true,
            deferredUntilApproval: true,
            membroFirestoreId: found.ref.id,
            message: "Cadastro recebido. O login será criado quando o gestor aprovar (senha inicial 123456).",
        };
    }
    const result = await ensureMemberFirebaseAuth(tenantId, memberId, found.ref, memberData);
    const isAtivo = status === "ativo" || (status !== "pendente" && status !== "reprovado");
    const msg = isAtivo
        ? "Login criado. Senha: 123456. O membro já pode acessar o painel."
        : "Login criado. Senha: 123456. Aguarde aprovação do gestor para acessar o painel.";
    return {
        ok: true,
        uid: result.uid,
        email: result.email,
        message: msg,
        created: !result.alreadyHad,
        membroFirestoreId: result.membroFirestoreId,
        migratedFromDocId: result.migratedFrom || null,
    };
});
/**
 * Membro autenticado: move o doc de `membros/{cpf|…}` para `membros/{authUid}` quando o campo
 * [authUid] do cadastro coincide com o UID do token (seguro — não expõe migração no callable público).
 */
exports.alignMemberDocToAuthUid = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const memberDocHint = String(data?.memberId || data?.cpf || "").trim();
    if (!tenantId || !memberDocHint) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId (ou cpf) são obrigatórios.");
    }
    const uid = context.auth.uid;
    const found = await findMemberDocument(tenantId, memberDocHint);
    if (!found) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado.");
    }
    const au = String(found.data.authUid || "").trim();
    if (au !== uid) {
        throw new functions.https.HttpsError("permission-denied", "Este cadastro não está vinculado ao seu login.");
    }
    if (found.ref.id === uid) {
        return { ok: true, membroFirestoreId: uid, migrated: false };
    }
    const r = await ensureMemberFirebaseAuth(tenantId, memberDocHint, found.ref, {
        ...found.data,
        authUid: uid,
    });
    return {
        ok: true,
        membroFirestoreId: r.membroFirestoreId,
        migrated: true,
        migratedFromDocId: r.migratedFrom || null,
    };
});
/** Resolve UID do Auth a partir do doc em membros (campo [authUid] ou id do documento). */
function resolveMemberAuthUidFromDoc(docId, data) {
    const fromField = String(data?.authUid || "").trim();
    if (fromField)
        return fromField;
    const id = String(docId || "").trim();
    if (/^[a-zA-Z0-9]{20,36}$/.test(id))
        return id;
    return null;
}
/**
 * Após corrigir o e-mail no Firestore: remove o utilizador Auth antigo e cria outro com o e-mail
 * atual do cadastro, migrando `membros/{id}` para `membros/{novoUid}`. Senha padrão 123456.
 * Quem pode: gestor da igreja ou o próprio membro (token == UID antigo).
 */
exports.recreateMemberAuthForNewEmail = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const memberDocId = String(data?.memberDocId || "").trim();
    if (!tenantId || !memberDocId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberDocId são obrigatórios.");
    }
    const found = await findMemberDocument(tenantId, memberDocId);
    if (!found) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado.");
    }
    const d = found.data;
    const newEmailRaw = String(d.EMAIL || d.email || "").trim().toLowerCase();
    if (!newEmailRaw.includes("@")) {
        return { ok: true, skipped: true, reason: "no-email-in-member-doc" };
    }
    let authSubjectUid = resolveMemberAuthUidFromDoc(found.ref.id, d);
    if (!authSubjectUid) {
        return { ok: true, skipped: true, reason: "no-auth-user" };
    }
    const callerUid = context.auth.uid;
    // O campo [authUid] pode ficar desatualizado; o id do documento `membros/{uid}` é o vínculo
    // correto quando coincide com o utilizador autenticado. Sem isto, getUserByEmail(novoEmail)
    // devolvia a própria conta e o código tratava como "e-mail em uso por outra conta".
    if (found.ref.id === callerUid) {
        authSubjectUid = callerUid;
    }
    const canManage = await canManageTenant(callerUid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    const isSelf = callerUid === authSubjectUid;
    if (!canManage && !isSelf) {
        throw new functions.https.HttpsError("permission-denied", "Apenas o próprio membro ou a equipe da igreja pode sincronizar o login com o e-mail.");
    }
    let authUser;
    try {
        authUser = await admin.auth().getUser(authSubjectUid);
    }
    catch {
        return { ok: true, skipped: true, reason: "auth-user-missing" };
    }
    const authEmail = String(authUser.email || "").trim().toLowerCase();
    if (authEmail === newEmailRaw) {
        const wrongField = String(d.authUid || "")
            .trim() !== authSubjectUid;
        if (wrongField) {
            await found.ref.set({
                authUid: authSubjectUid,
                MEMBER_ID: authSubjectUid,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        return { ok: true, unchanged: true, membroFirestoreId: found.ref.id };
    }
    let conflicting = null;
    try {
        conflicting = await admin.auth().getUserByEmail(newEmailRaw);
    }
    catch {
        conflicting = null;
    }
    if (conflicting && conflicting.uid !== authSubjectUid) {
        throw new functions.https.HttpsError("already-exists", "Este e-mail já está em uso por outra conta. Escolha outro e-mail.");
    }
    const status = String(d.STATUS || d.status || "").toLowerCase();
    const reallyAtivo = status === "ativo" || (status !== "pendente" && status !== "reprovado");
    const cpf = String(d.CPF || d.cpf || "").replace(/\D/g, "");
    const nome = String(d.NOME_COMPLETO || d.nome || d.name || "").trim();
    const oldDocId = found.ref.id;
    const oldUserSnap = await db.collection("users").doc(authSubjectUid).get();
    const oldUserData = oldUserSnap.exists ? oldUserSnap.data() || {} : {};
    const oldTenantUserSnap = await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("users")
        .doc(authSubjectUid)
        .get();
    const oldTenantUserData = oldTenantUserSnap.exists ? oldTenantUserSnap.data() || {} : {};
    const prevClaims = (authUser.customClaims || {});
    await admin.auth().deleteUser(authSubjectUid);
    let newAuth;
    try {
        newAuth = await admin.auth().createUser({
            email: newEmailRaw,
            password: MEMBER_DEFAULT_PASSWORD,
            displayName: nome || undefined,
            emailVerified: false,
        });
    }
    catch (err) {
        const anyErr = err;
        console.error("recreateMemberAuthForNewEmail createUser after delete", authSubjectUid, anyErr);
        throw new functions.https.HttpsError("internal", "Não foi possível criar o novo login. Contacte o suporte (conta antiga foi removida).");
    }
    const newUid = newAuth.uid;
    await copyIgrejaMembroStorageFolder(tenantId, oldDocId, newUid);
    const merged = {
        ...d,
        authUid: newUid,
        MEMBER_ID: newUid,
        EMAIL: newEmailRaw,
        email: newEmailRaw,
        // Mantém URLs legadas para evitar perder foto/avatar durante migração de UID.
        photoStoragePath: `igrejas/${tenantId}/membros/${newUid}/foto_perfil.jpg`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const newMembroRef = db.collection("igrejas").doc(tenantId).collection("membros").doc(newUid);
    await newMembroRef.set(merged, { merge: true });
    if (oldDocId !== newUid) {
        await found.ref.delete();
    }
    await admin.auth().setCustomUserClaims(newUid, {
        role: String(prevClaims.role || "membro"),
        igrejaId: tenantId,
        tenantId,
        active: prevClaims.active !== false && reallyAtivo,
        isUser: prevClaims.isUser !== false,
        isDriver: prevClaims.isDriver === true,
        pendingApproval: prevClaims.pendingApproval === true || status === "pendente",
    });
    try {
        await db.collection("users").doc(authSubjectUid).delete();
    }
    catch (e) {
        console.warn("recreateMemberAuth delete old users doc", e);
    }
    try {
        await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("users")
            .doc(authSubjectUid)
            .delete();
    }
    catch (e) {
        console.warn("recreateMemberAuth delete old igrejas/users", e);
    }
    await db
        .collection("users")
        .doc(newUid)
        .set({
        ...oldUserData,
        email: newEmailRaw,
        nome: nome || oldUserData.nome,
        displayName: nome || oldUserData.displayName,
        nomeCompleto: nome || oldUserData.nomeCompleto,
        tenantId,
        igrejaId: tenantId,
        cpf: cpf.length === 11 ? cpf : oldUserData.cpf || "",
    }, { merge: false });
    await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("users")
        .doc(newUid)
        .set({
        ...oldTenantUserData,
        email: newEmailRaw,
        nome: nome || oldTenantUserData.nome,
        displayName: nome || oldTenantUserData.displayName,
    }, { merge: false });
    if (cpf.length === 11) {
        const idx = {
            uid: newUid,
            cpf,
            email: newEmailRaw,
            name: nome,
            nome,
            tenantId,
            role: String(oldUserData.role || "membro"),
            active: reallyAtivo,
            pendingApproval: status === "pendente",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        await db.collection("tenants").doc(tenantId).collection("usersIndex").doc(cpf).set(idx, {
            merge: true,
        });
        await db.collection("igrejas").doc(tenantId).collection("usersIndex").doc(cpf).set(idx, {
            merge: true,
        });
    }
    const msg = "Login atualizado para o novo e-mail. Senha padrão: 123456 (o membro deve entrar de novo).";
    return {
        ok: true,
        recreated: true,
        previousUid: authSubjectUid,
        newUid,
        newEmail: newEmailRaw,
        membroFirestoreId: newUid,
        wasSelf: isSelf,
        message: msg,
    };
});
/**
 * Gestor pode alterar a senha de um membro (esqueci a senha / redefinir).
 */
exports.setMemberPassword = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const memberIdOrUid = String(data?.memberId || data?.uid || "").trim();
    const newPassword = String(data?.newPassword || "").trim();
    if (!tenantId || !memberIdOrUid || newPassword.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId, memberId/uid e newPassword (mín. 6) são obrigatórios.");
    }
    const email = String(context.auth.token?.email || "").trim().toLowerCase();
    const canManage = await canManageTenant(context.auth.uid, context.auth.token?.role, context.auth.token?.igrejaId || context.auth.token?.tenantId, tenantId);
    if (!canManage) {
        try {
            await db.collection("auditoria").add({
                acao: "security_password_reset_denied",
                resource: "setMemberPassword",
                details: `permission-denied tenant=${tenantId}`,
                usuario: email || context.auth.uid,
                uid: context.auth.uid,
                igrejaId: tenantId,
                data: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        catch (logErr) {
            console.error("setMemberPassword auditoria denied", logErr);
        }
        throw new functions.https.HttpsError("permission-denied", "Apenas gestor da igreja pode redefinir senha.");
    }
    /** Sempre preferir o authUid gravado no cadastro do membro (evita confundir docId com UID do Auth). */
    let uid = null;
    const found = await findMemberDocument(tenantId, memberIdOrUid);
    const authUidFromMember = String(found?.data?.authUid || "").trim();
    if (authUidFromMember) {
        uid = authUidFromMember;
    }
    else {
        try {
            await admin.auth().getUser(memberIdOrUid);
            uid = memberIdOrUid;
        }
        catch (_) {
            // não é um UID válido no Auth
        }
    }
    if (!uid) {
        throw new functions.https.HttpsError("not-found", "Membro sem login vinculado. Use \"Criar login\" primeiro.");
    }
    try {
        await admin.auth().updateUser(uid, { password: newPassword });
    }
    catch (err) {
        const anyErr = err;
        const code = String(anyErr?.code || "");
        const msg = String(anyErr?.message || err || "");
        console.error("setMemberPassword updateUser", code, msg);
        if (code === "auth/user-not-found") {
            /** UID obsoleto no Firestore (conta apagada no Auth): recria login como em ensureMemberFirebaseAuth e aplica a nova senha. */
            const foundForRecreate = await findMemberDocument(tenantId, memberIdOrUid);
            if (!foundForRecreate) {
                throw new functions.https.HttpsError("not-found", "Membro não encontrado.");
            }
            const clearedData = {
                ...foundForRecreate.data,
            };
            delete clearedData.authUid;
            try {
                const r = await ensureMemberFirebaseAuth(tenantId, foundForRecreate.ref.id, foundForRecreate.ref, clearedData);
                await admin.auth().updateUser(r.uid, { password: newPassword });
            }
            catch (recErr) {
                console.error("setMemberPassword recreate after user-not-found", recErr);
                if (recErr instanceof functions.https.HttpsError)
                    throw recErr;
                const re = recErr;
                throw new functions.https.HttpsError("failed-precondition", re?.message ||
                    "Não foi possível recriar o login. Verifique e-mail/CPF do membro ou use \"Criar login\".");
            }
            try {
                await db.collection("auditoria").add({
                    acao: "security_password_reset_success",
                    resource: "setMemberPassword",
                    details: "uid=recreated after auth/user-not-found",
                    usuario: email || context.auth.uid,
                    uid: context.auth.uid,
                    igrejaId: tenantId,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            catch (logErr) {
                console.error("setMemberPassword auditoria recreate", logErr);
            }
            return {
                ok: true,
                recreated: true,
                message: "Conta de login recriada e senha definida.",
            };
        }
        if (code === "auth/invalid-password" || code === "auth/weak-password") {
            throw new functions.https.HttpsError("invalid-argument", "Senha recusada pelas regras de segurança. Tente uma senha mais longa (ex.: 8+ caracteres com letras e números).");
        }
        throw new functions.https.HttpsError("failed-precondition", "Não foi possível alterar a senha agora. Tente outra senha ou contacte o suporte.");
    }
    try {
        await db.collection("auditoria").add({
            acao: "security_password_reset_success",
            resource: "setMemberPassword",
            details: `uid=${uid}`,
            usuario: email || context.auth.uid,
            uid: context.auth.uid,
            igrejaId: tenantId,
            data: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    catch (logErr) {
        console.error("setMemberPassword auditoria success", logErr);
    }
    return { ok: true, message: "Senha alterada." };
});
/**
 * Ao aprovar um membro pendente: vincula/cria usuário no Firebase Auth (senha 123456),
 * grava authUid no cadastro do membro e ativa o login (custom claims active: true, role: membro).
 */
exports.setMemberApproved = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const memberId = String(data?.memberId || "").trim();
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId são obrigatórios.");
    }
    const role = String(context.auth.token?.role || "").toUpperCase();
    const igrejaId = context.auth.token?.igrejaId || context.auth.token?.tenantId;
    const isGestor = ["ADMIN", "ADM", "GESTOR", "MASTER"].includes(role) &&
        (String(igrejaId) === tenantId || role === "MASTER");
    if (!isGestor) {
        throw new functions.https.HttpsError("permission-denied", "Apenas gestor pode aprovar.");
    }
    const found = await findMemberDocument(tenantId, memberId);
    if (!found) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado.");
    }
    const memberRef = found.ref;
    const memberData = { ...found.data, STATUS: "ativo", status: "ativo" };
    await memberRef.set({
        STATUS: "ativo",
        status: "ativo",
        aprovadoEm: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const after = await memberRef.get();
    const d = after.data() || {};
    let authUid = String(d.authUid || "").trim();
    if (!authUid) {
        const r = await ensureMemberFirebaseAuth(tenantId, memberId, memberRef, { ...d, STATUS: "ativo", status: "ativo" });
        authUid = r.uid;
    }
    try {
        await admin.auth().updateUser(authUid, { password: MEMBER_DEFAULT_PASSWORD });
    }
    catch (pwErr) {
        console.warn("setMemberApproved updateUser password", pwErr);
    }
    await admin.auth().setCustomUserClaims(authUid, {
        role: "membro",
        igrejaId: tenantId,
        tenantId,
        active: true,
        isUser: true,
        isDriver: false,
        pendingApproval: false,
    });
    await db.collection("users").doc(authUid).set({ ativo: true }, { merge: true });
    const cpf = String(d.CPF || d.cpf || "").replace(/\D/g, "");
    if (cpf.length === 11) {
        const idx = { active: true, pendingApproval: false };
        await db
            .collection("tenants")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(idx, { merge: true });
        await db
            .collection("igrejas")
            .doc(tenantId)
            .collection("usersIndex")
            .doc(cpf)
            .set(idx, { merge: true });
    }
    return {
        ok: true,
        uid: authUid,
        message: "Login ativado. Senha padrão: 123456 (o usuário pode trocar ao logar ou usar Esqueci a senha).",
    };
});
/**
 * Cria login Firebase (e-mail + senha 123456) para todos os membros sem authUid em igrejas/{id}/membros.
 * MASTER / raihom@gmail.com: todas as igrejas. GESTOR/ADM: informe tenantId da própria igreja.
 */
exports.bulkEnsureMembersAuth = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const roleCaller = String(context.auth.token?.role || "").toUpperCase();
    const callerEmail = String(context.auth.token?.email || "").trim().toLowerCase();
    const tenantIdFilter = String(data?.tenantId || "").trim();
    const ig = String(context.auth.token?.igrejaId || context.auth.token?.tenantId || "");
    const isMaster = roleCaller === "MASTER" ||
        callerEmail === "raihom@gmail.com" ||
        ["ADMIN", "ADM"].includes(roleCaller);
    const churchIds = [];
    if (tenantIdFilter) {
        const ex = await db.collection("igrejas").doc(tenantIdFilter).get();
        if (!ex.exists) {
            throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
        }
        if (isMaster) {
            churchIds.push(tenantIdFilter);
        }
        else if (["GESTOR", "ADMIN", "ADM"].includes(roleCaller)) {
            if (ig !== tenantIdFilter) {
                throw new functions.https.HttpsError("permission-denied", "Só pode processar a própria igreja.");
            }
            churchIds.push(tenantIdFilter);
        }
        else {
            throw new functions.https.HttpsError("permission-denied", "Sem permissão.");
        }
    }
    else {
        if (!isMaster) {
            throw new functions.https.HttpsError("invalid-argument", "Informe tenantId da igreja ou use conta MASTER para todas.");
        }
        const snap = await db.collection("igrejas").get();
        for (const d of snap.docs)
            churchIds.push(d.id);
    }
    let created = 0;
    let skipped = 0;
    let errors = 0;
    const errorsList = [];
    for (const tid of churchIds) {
        let membrosSnap;
        try {
            membrosSnap = await db.collection("igrejas").doc(tid).collection("membros").get();
        }
        catch {
            continue;
        }
        for (const doc of membrosSnap.docs) {
            const md = doc.data();
            if (md.authUid) {
                skipped++;
                continue;
            }
            try {
                const r = await ensureMemberFirebaseAuth(tid, doc.id, doc.ref, md);
                if (r.alreadyHad)
                    skipped++;
                else
                    created++;
            }
            catch (e) {
                errors++;
                const msg = e instanceof Error ? e.message : String(e);
                if (errorsList.length < 30)
                    errorsList.push(`${tid}/${doc.id}: ${msg}`);
            }
        }
    }
    return {
        ok: true,
        churches: churchIds.length,
        loginCriados: created,
        jaTinhamLogin: skipped,
        erros: errors,
        errorsList,
        message: `Igrejas: ${churchIds.length}. Novos logins: ${created}. Já existiam: ${skipped}. Erros: ${errors}. Senha padrão: 123456. Pendentes ficam bloqueados até aprovação.`,
    };
});
/**
 * Retorna o e-mail do membro para o cliente poder chamar sendPasswordResetEmail (Esqueci a senha por CPF ou e-mail).
 */
exports.getMemberEmailForReset = functions
    .region("us-central1")
    .https.onCall(async (data) => {
    const tenantId = String(data?.tenantId || "").trim();
    const cpfOrEmail = String(data?.cpfOrEmail || "").trim();
    if (!tenantId || !cpfOrEmail) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e cpfOrEmail são obrigatórios.");
    }
    const isEmail = cpfOrEmail.includes("@");
    let email = null;
    if (isEmail) {
        email = cpfOrEmail;
    }
    else {
        const cpfDigits = cpfOrEmail.replace(/\D/g, "");
        let q = await db.collection("igrejas").doc(tenantId).collection("membros").where("CPF", "==", cpfDigits).limit(1).get();
        if (q.empty) {
            q = await db.collection("igrejas").doc(tenantId).collection("membros").where("cpf", "==", cpfDigits).limit(1).get();
        }
        if (q.empty) {
            q = await db.collection("tenants").doc(tenantId).collection("members").where("CPF", "==", cpfDigits).limit(1).get();
        }
        if (!q.empty && q.docs[0].data()?.authUid) {
            email = q.docs[0].data()?.EMAIL || q.docs[0].data()?.email || null;
        }
    }
    if (!email) {
        throw new functions.https.HttpsError("not-found", "Nenhum membro encontrado com esse CPF ou e-mail.");
    }
    return { email };
});
/**
 * ✅ Garante acesso completo ao banco para o gestor Brasil para Cristo (CPF 94536368191, raihom@gmail.com).
 * Cria/atualiza: igrejas, tenants, usersIndex, users, publicCpfIndex, subscription e custom claims.
 * Chamar uma vez (como MASTER ou logado como raihom@gmail.com) para corrigir o acesso.
 */
exports.ensureBrasilParaCristoAccess = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const callerEmail = String(context.auth?.token?.email || "").toLowerCase();
    const isMaster = !!context.auth && (roleCaller === "MASTER");
    const isGestor = callerEmail === "raihom@gmail.com";
    const secret = String(SEED_GESTOR_PARAM.value() || "").trim();
    const secretMatch = !!secret && String(data?.secret || "") === secret;
    if (!context.auth && !secretMatch) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login (raihom@gmail.com ou Master) ou use o secret.");
    }
    if (!isMaster && !isGestor && !secretMatch) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao gestor ou MASTER.");
    }
    try {
        const tenantId = "brasilparacristo_sistema";
        const cpf = "94536368191";
        const email = "raihom@gmail.com";
        const name = "Brasil para Cristo";
        const gestorName = "RAIHOM SEVERINO BARBOSA";
        const igrejaPayload = {
            nome: name,
            name,
            slug: tenantId,
            ativa: true,
            email: email.toLowerCase(),
            gestorEmail: email.toLowerCase(),
            emailGestor: email.toLowerCase(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        await db.collection("igrejas").doc(tenantId).set(igrejaPayload, { merge: true });
        const tenantPayload = {
            name,
            nome: name,
            slug: tenantId,
            alias: tenantId,
            email: email.toLowerCase(),
            cpf,
            gestorNome: gestorName,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        await db.collection("tenants").doc(tenantId).set(tenantPayload, { merge: true });
        await db.doc(`publicCpfIndex/${cpf}`).set({
            tenantId,
            churchId: tenantId,
            name,
            slug: tenantId,
            cpf,
            email: email.toLowerCase(),
            gestorName,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        let authUser = null;
        try {
            authUser = await admin.auth().getUserByEmail(email);
        }
        catch (_) {
            authUser = null;
        }
        // Sempre grava usersIndex para CPF e e-mail encontrarem o perfil (resolveCpfToChurchPublic / resolveEmailToChurchPublic)
        const usersIndexRef = db.collection("tenants").doc(tenantId).collection("usersIndex").doc(cpf);
        await usersIndexRef.set({
            ...(authUser ? { uid: authUser.uid } : {}),
            cpf,
            name: gestorName,
            nome: gestorName,
            email: email.toLowerCase(),
            role: "GESTOR",
            tenantId,
            active: true,
            ativo: true,
            isUser: true,
            isDriver: false,
            mustChangePass: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        if (authUser) {
            await admin.auth().setCustomUserClaims(authUser.uid, {
                role: "GESTOR",
                igrejaId: tenantId,
                active: true,
                isUser: true,
                isDriver: false,
            });
            await db.collection("users").doc(authUser.uid).set({
                uid: authUser.uid,
                cpf,
                name: gestorName,
                nome: gestorName,
                email: email.toLowerCase(),
                role: "GESTOR",
                igrejaId: tenantId,
                tenantId,
                ativo: true,
                active: true,
                mustChangePass: false,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        const subSnap = await db
            .collection("subscriptions")
            .where("igrejaId", "==", tenantId)
            .orderBy("createdAt", "desc")
            .limit(1)
            .get();
        if (subSnap.empty) {
            const trialEndsAt = new Date();
            trialEndsAt.setDate(trialEndsAt.getDate() + 30);
            await db.collection("subscriptions").add({
                igrejaId: tenantId,
                planId: "PRO",
                status: "TRIAL",
                trialEndsAt: admin.firestore.Timestamp.fromDate(trialEndsAt),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        return {
            ok: true,
            tenantId,
            cpf,
            email,
            uid: authUser?.uid ?? null,
            message: authUser
                ? "Acesso garantido. Use CPF 94536368191 ou e-mail raihom@gmail.com em 'Carregar igreja' e faça login."
                : "Igreja e índice CPF criados. Crie o usuário Auth com seedGestorBrasilParaCristo (senha) para poder fazer login.",
        };
    }
    catch (e) {
        console.error("ensureBrasilParaCristoAccess error:", e);
        throw new functions.https.HttpsError("internal", e?.message || "Erro ao garantir acesso");
    }
});
const FROTA_COLLECTIONS = [
    "frota_manutencao",
    "frota_abastecimentos",
    "frota_motoristas",
    "frota_veiculos",
    "frota_licenses",
    "frota_combustiveis",
];
/** Coleções de frota + frotas que devem ser removidas do banco (default). */
const DEFAULT_COLLECTIONS_TO_CLEAN = [
    ...FROTA_COLLECTIONS,
    "frotas",
];
/**
 * ✅ ONE-OFF — Remove do banco (default) todas as coleções de frota.
 * Chamar após migrateFrotaToFrotasveiculo (logado como MASTER). Deleta documentos em lote.
 */
exports.cleanFrotaFromDefault = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const isMaster = !!context.auth &&
        (roleCaller === "MASTER" || context.auth?.token?.email === "raihom@gmail.com");
    if (!context.auth || !isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const batchSize = 500;
    const deleted = {};
    for (const collName of DEFAULT_COLLECTIONS_TO_CLEAN) {
        let total = 0;
        let snap = await db.collection(collName).limit(batchSize).get();
        while (!snap.empty) {
            const batch = db.batch();
            for (const doc of snap.docs) {
                batch.delete(doc.ref);
                total++;
            }
            await batch.commit();
            snap = await db.collection(collName).limit(batchSize).get();
        }
        deleted[collName] = total;
    }
    return { ok: true, deleted, message: "Coleções de frota removidas do banco (default)." };
});
/**
 * ✅ ONE-OFF — Corrige o banco: migra frota do (default) para frotasveiculo e apaga frota do (default).
 * Chamar uma vez (logado como MASTER). Ordem: 1) migra, 2) apaga do default.
 */
exports.corrigirBancoFrota = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const isMaster = !!context.auth &&
        (roleCaller === "MASTER" || context.auth?.token?.email === "raihom@gmail.com");
    if (!context.auth || !isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const migrated = {};
    const batchSize = 500;
    for (const collName of FROTA_COLLECTIONS) {
        const snap = await db.collection(collName).get();
        migrated[collName] = snap.size;
        if (!snap.empty) {
            let batch = dbFrota.batch();
            let count = 0;
            for (const doc of snap.docs) {
                batch.set(dbFrota.collection(collName).doc(doc.id), doc.data(), { merge: true });
                count++;
                if (count >= batchSize) {
                    await batch.commit();
                    batch = dbFrota.batch();
                    count = 0;
                }
            }
            if (count > 0)
                await batch.commit();
        }
    }
    const deleted = {};
    for (const collName of DEFAULT_COLLECTIONS_TO_CLEAN) {
        let total = 0;
        let snap = await db.collection(collName).limit(batchSize).get();
        while (!snap.empty) {
            const batch = db.batch();
            for (const doc of snap.docs)
                batch.delete(doc.ref);
            total += snap.size;
            await batch.commit();
            snap = await db.collection(collName).limit(batchSize).get();
        }
        deleted[collName] = total;
    }
    return {
        ok: true,
        migrated,
        deleted,
        message: "Banco corrigido: frota migrada para frotasveiculo e removida do (default).",
    };
});
/**
 * ✅ ONE-OFF — Migra dados de frota do banco (default) para frotasveiculo.
 * Chamar uma vez (logado como MASTER). Copia todas as coleções frota_*.
 */
exports.migrateFrotaToFrotasveiculo = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const isMaster = !!context.auth &&
        (roleCaller === "MASTER" || context.auth?.token?.email === "raihom@gmail.com");
    if (!context.auth || !isMaster) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const result = {};
    const batchSize = 500;
    for (const collName of FROTA_COLLECTIONS) {
        const snap = await db.collection(collName).get();
        result[collName] = snap.size;
        if (snap.empty)
            continue;
        let batch = dbFrota.batch();
        let count = 0;
        for (const doc of snap.docs) {
            const ref = dbFrota.collection(collName).doc(doc.id);
            batch.set(ref, doc.data(), { merge: true });
            count++;
            if (count >= batchSize) {
                await batch.commit();
                batch = dbFrota.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    return { ok: true, migrated: result, message: "Migração concluída." };
});
/**
 * ✅ ONE-OFF — Inclui RAIHOM como MASTER no banco frotasveiculo.
 * Chamar uma vez (logado como MASTER ou com secret). Cria documento em frotasveiculo/usuarios.
 */
exports.seedFrotaMaster = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const roleCaller = String(context.auth?.token?.role || "").toUpperCase();
    const isMaster = !!context.auth && (roleCaller === "MASTER" || context.auth?.token?.email === "raihom@gmail.com");
    const secret = String(SEED_GESTOR_PARAM.value() || "").trim();
    const secretMatch = secret && String(data?.secret || "") === secret;
    if (!context.auth && !secretMatch) {
        throw new functions.https.HttpsError("unauthenticated", "Login ou secret obrigatório");
    }
    if (!isMaster && !secretMatch) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito");
    }
    const cpf = "94536368191";
    const email = "raihom@gmail.com";
    const nome = "RAIHOM SEVERINO BARBOSA";
    const telefone = "62991705247";
    const role = "MASTER";
    await dbFrota.collection("usuarios").doc(email).set({
        cpf,
        email,
        nome,
        telefone,
        role,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await dbFrota.collection("usuarios").doc(cpf).set({
        cpf,
        email,
        nome,
        telefone,
        role,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Migração automática: copia frota_* do (default) para frotasveiculo (uma vez)
    const result = {};
    const batchSize = 500;
    for (const collName of FROTA_COLLECTIONS) {
        const snap = await db.collection(collName).get();
        result[collName] = snap.size;
        if (snap.empty)
            continue;
        let batch = dbFrota.batch();
        let count = 0;
        for (const doc of snap.docs) {
            const ref = dbFrota.collection(collName).doc(doc.id);
            batch.set(ref, doc.data(), { merge: true });
            count++;
            if (count >= batchSize) {
                await batch.commit();
                batch = dbFrota.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    return {
        ok: true,
        message: "MASTER incluído e dados de frota migrados para frotasveiculo.",
        databaseId: "frotasveiculo",
        migrated: result,
    };
});
/**
 * ✅ ONE-OFF — Mesmo seed por HTTP (para chamar direto pela URL e criar o banco).
 * GET ou POST com ?secret=SEU_SEED_GESTOR_SECRET (ou body.secret).
 * Defina SEED_GESTOR_SECRET no .env e abra a URL no navegador para popular frotasveiculo.
 */
exports.seedFrotaMasterHttp = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    const cors = () => {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");
    };
    if (req.method === "OPTIONS") {
        cors();
        res.status(204).send("");
        return;
    }
    cors();
    const secretParam = String(SEED_GESTOR_PARAM.value() || "").trim();
    const secret = req.query?.secret !== undefined
        ? String(req.query.secret)
        : (req.body && typeof req.body === "object" && req.body.secret) !== undefined
            ? String(req.body.secret)
            : "";
    if (!secretParam || secret !== secretParam) {
        res.status(403).json({ ok: false, error: "Secret inválido ou não configurado." });
        return;
    }
    const cpf = "94536368191";
    const email = "raihom@gmail.com";
    const nome = "RAIHOM SEVERINO BARBOSA";
    const telefone = "62991705247";
    const role = "MASTER";
    try {
        await dbFrota.collection("usuarios").doc(email).set({ cpf, email, nome, telefone, role, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        await dbFrota.collection("usuarios").doc(cpf).set({ cpf, email, nome, telefone, role, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        const result = {};
        const batchSize = 500;
        for (const collName of FROTA_COLLECTIONS) {
            const snap = await db.collection(collName).get();
            result[collName] = snap.size;
            if (!snap.empty) {
                let batch = dbFrota.batch();
                let count = 0;
                for (const doc of snap.docs) {
                    batch.set(dbFrota.collection(collName).doc(doc.id), doc.data(), { merge: true });
                    count++;
                    if (count >= batchSize) {
                        await batch.commit();
                        batch = dbFrota.batch();
                        count = 0;
                    }
                }
                if (count > 0)
                    await batch.commit();
            }
        }
        res.status(200).json({
            ok: true,
            message: "MASTER incluído e dados de frota migrados para frotasveiculo.",
            databaseId: "frotasveiculo",
            migrated: result,
        });
    }
    catch (err) {
        res.status(500).json({ ok: false, error: String(err) });
    }
});
/**
 * Retorna o perfil do usuário logado (users + subscription) para o painel.
 * Usado quando o cliente não consegue ler Firestore (ex.: domínio não autorizado, regras).
 */
exports.getUserProfile = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário");
    }
    try {
        const uid = context.auth.uid;
        const claims = (context.auth.token || {});
        let igrejaId = String(claims.igrejaId || claims.tenantId || "").trim();
        let role = String(claims.role || "").trim();
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.exists ? userSnap.data() || {} : {};
        if (!igrejaId)
            igrejaId = String(userData.igrejaId || userData.tenantId || "").trim();
        if (!role)
            role = String(userData.role || "").trim();
        if (!igrejaId)
            return { profile: null };
        const subSnap = await db
            .collection("subscriptions")
            .where("igrejaId", "==", igrejaId)
            .orderBy("createdAt", "desc")
            .limit(1)
            .get();
        let subData = null;
        if (!subSnap.empty && subSnap.docs[0])
            subData = subSnap.docs[0].data();
        return {
            profile: {
                igrejaId,
                role,
                cpf: String(userData.cpf || ""),
                active: userData.ativo === true,
                mustChangePass: userData.mustChangePass === true,
                mustCompleteRegistration: userData.mustCompleteRegistration === true,
                subscription: subData,
            },
        };
    }
    catch (e) {
        console.error("getUserProfile error:", e);
        throw new functions.https.HttpsError("internal", e?.message || "Erro ao carregar perfil");
    }
});
/**
 * Verifica se o usuário logado pode acessar o Painel Master (admin).
 * Usado quando o cliente não consegue ler Firestore (fallback no guard).
 */
exports.getAdminCheck = functions
    .region("us-central1")
    .https.onCall(async (_, context) => {
    if (!context.auth)
        return { allowed: false };
    const uid = context.auth.uid;
    const email = String((context.auth.token?.email || "")).toLowerCase();
    if (email === "raihom@gmail.com")
        return { allowed: true };
    const userSnap = await db.collection("users").doc(uid).get();
    const data = userSnap.exists ? userSnap.data() || {} : {};
    const role = String(data.role || data.nivel || "").toUpperCase();
    const nivel = String(data.nivel || "").toLowerCase();
    if (role === "ADM" || role === "ADMIN" || role === "MASTER" || nivel === "adm")
        return { allowed: true };
    const usuariosSnap = await db.collection("usuarios").doc(uid).get();
    const ndata = usuariosSnap.exists ? usuariosSnap.data() || {} : {};
    if (String(ndata.nivel || "").toLowerCase() === "adm")
        return { allowed: true };
    return { allowed: false };
});
/**
 * Permite ao usuário logado virar ADMIN informando a chave de setup (ADMIN_SETUP_KEY).
 * Configure ADMIN_SETUP_KEY no Google Cloud Console: Cloud Functions > bootstrapAdmin > Editar > Variáveis de ambiente.
 * Ou no arquivo .env na pasta functions: ADMIN_SETUP_KEY=sua_chave_secreta
 */
exports.bootstrapAdmin = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login para continuar.");
    }
    const email = String(context.auth.token?.email || "").toLowerCase();
    const setupKey = String(data?.setupKey || "").trim();
    const expectedKey = String(ADMIN_SETUP_KEY_PARAM.value() || "").trim();
    const isFirstAdminEmail = email === "raihom@gmail.com";
    if (!expectedKey && !isFirstAdminEmail) {
        throw new functions.https.HttpsError("failed-precondition", "ADMIN_SETUP_KEY não está configurada. Defina no Google Cloud Console > Cloud Functions > bootstrapAdmin > Variáveis de ambiente (ADMIN_SETUP_KEY).");
    }
    if (expectedKey && setupKey !== expectedKey) {
        throw new functions.https.HttpsError("permission-denied", "Chave de setup incorreta.");
    }
    const uid = context.auth.uid;
    const user = await admin.auth().getUser(uid);
    const claims = (user.customClaims || {});
    await admin.auth().setCustomUserClaims(uid, {
        ...claims,
        role: "ADMIN",
    });
    await db.collection("users").doc(uid).set({
        role: "ADMIN",
        email: context.auth.token?.email || user.email,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true };
});
/**
 * Reporta eventos de segurança para auditoria e alerta do painel master.
 * Uso: cliente chama quando detectar situação suspeita (acesso sem claim, tentativa negada, etc.).
 */
exports.reportSecurityEvent = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const uid = context.auth.uid;
    const email = String(context.auth.token?.email || "").trim().toLowerCase();
    const event = String(data?.event || "").trim();
    const resource = String(data?.resource || "").trim();
    const details = String(data?.details || "").trim();
    const severityRaw = String(data?.severity || "medium").trim().toLowerCase();
    const severity = ["low", "medium", "high", "critical"].includes(severityRaw) ? severityRaw : "medium";
    if (!event || !resource) {
        throw new functions.https.HttpsError("invalid-argument", "event e resource são obrigatórios.");
    }
    // Rate-limit simples por usuário para evitar spam de logs.
    const rateRef = db.collection("security_events_rate").doc(uid);
    const nowMs = Date.now();
    const rateSnap = await rateRef.get();
    const lastMs = Number((rateSnap.data() || {}).lastAtMs || 0);
    if (lastMs > 0 && nowMs - lastMs < 10000) {
        throw new functions.https.HttpsError("resource-exhausted", "Aguarde alguns segundos para reportar novamente.");
    }
    await rateRef.set({ lastAtMs: nowMs, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const canReadAdmin = await isAdminPanelActor(uid, context.auth.token?.role, email);
    const igrejaId = String(context.auth.token?.igrejaId || context.auth.token?.tenantId || "").trim();
    const payload = {
        acao: `security_${event}`,
        resource,
        details,
        severity,
        usuario: email || uid,
        uid,
        igrejaId,
        data: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection("auditoria").add(payload);
    if (severity === "high" || severity === "critical") {
        await db.collection("alertas").add({
            titulo: "Alerta de segurança",
            tipo: "security",
            severity,
            status: "novo",
            texto: `${event} em ${resource}`,
            detalhes: details,
            actorUid: uid,
            actorEmail: email,
            igrejaId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            canReadAdmin,
        });
    }
    return { ok: true };
});
/**
 * TEMP — seedPublicCpfIndex (remove depois)
 * Cria/atualiza: publicCpfIndex/{cpf}
 */
exports.seedPublicCpfIndex = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    const role = String(context.auth?.token?.role || "").toUpperCase();
    if (!context.auth || role != "MASTER") {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito ao MASTER");
    }
    const cpf = String(data?.cpf || "").replace(/\D/g, "");
    if (!cpf) {
        throw new functions.https.HttpsError("invalid-argument", "CPF vazio");
    }
    const name = String(data?.name || "Igreja Teste");
    const slug = String(data?.slug || "igreja-teste");
    const churchId = String(data?.churchId || "TESTE");
    const payload = {
        cpf,
        name,
        slug,
        churchId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.doc(`publicCpfIndex/${cpf}`).set(payload, { merge: true });
    return { ok: true, cpf, payload };
});
/**
 * PUBLIC — resolveCpfToChurchPublicHttp (HTTP)
 * GET:  /resolveCpfToChurchPublicHttp?cpf=...
 * POST: { "cpf": "..." }  (ou { "data": { "cpf": "..." } })
 */
exports.resolveCpfToChurchPublicHttp = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    try {
        const cpf = String((req.body && req.body.cpf) ||
            (req.body && req.body.data && req.body.data.cpf) ||
            (req.query.cpf) ||
            "").replace(/\D/g, "");
        if (!cpf) {
            res.status(400).json({ ok: false, reason: "CPF_VAZIO" });
            return;
        }
        const snap = await db.doc(`publicCpfIndex/${cpf}`).get();
        if (!snap.exists) {
            res.json({ ok: false, reason: "NAO_ENCONTRADO" });
            return;
        }
        res.json({ ok: true, church: snap.data() || {} });
        return;
    }
    catch (e) {
        console.error("resolveCpfToChurchPublicHttp ERROR:", e);
        res.status(500).json({ ok: false, error: e?.message || "ERR" });
        return;
    }
});
/**
 * PUBLIC — resolveCpfToChurchPublic (HTTP FINAL)
 * GET:  /resolveCpfToChurchPublic?cpf=...
 * POST: { "cpf": "..." }
 */
exports.resolveCpfToChurchPublicFinal = functions
    .region("us-central1")
    .https.onRequest(async (req, res) => {
    try {
        const cpf = String((req.body && req.body.cpf) ||
            (req.body && req.body.data && req.body.data.cpf) ||
            (req.query.cpf) ||
            "").replace(/\D/g, "");
        if (!cpf) {
            res.status(400).json({ ok: false, reason: "CPF_VAZIO" });
            return;
        }
        const snap = await db.doc(`publicCpfIndex/${cpf}`).get();
        if (!snap.exists) {
            res.json({ ok: false, reason: "NAO_ENCONTRADO" });
            return;
        }
        res.json({ ok: true, church: snap.data() || {} });
        return;
    }
    catch (e) {
        console.error("resolveCpfToChurchPublic ERROR:", e);
        res.status(500).json({ ok: false, error: e?.message || "ERR" });
        return;
    }
});
function parseTimeParts(raw) {
    const parts = String(raw || "").split(":");
    const hh = Math.min(23, Math.max(0, parseInt(parts[0] || "0", 10) || 0));
    const mm = Math.min(59, Math.max(0, parseInt(parts[1] || "0", 10) || 0));
    return { hh, mm };
}
/**
 * Escalas a partir de modelos (`escala_templates`) são geradas **apenas** no painel,
 * pelo gestor ou pelo líder do departamento (botão «Gerar» em Escala Geral).
 * Não há job agendado que preencha `igrejas/{id}/escalas` automaticamente.
 */
function nextWeekday(from, weekday) {
    let d = new Date(from.getFullYear(), from.getMonth(), from.getDate());
    while ((d.getDay() === 0 ? 7 : d.getDay()) !== weekday) {
        d = new Date(d.getTime() + 24 * 60 * 60 * 1000);
    }
    return d;
}
function collectEventDates(rec, weekday, time, interval, months, until) {
    const now = new Date();
    const { hh, mm } = parseTimeParts(time);
    const dates = [];
    let cur = nextWeekday(now, weekday);
    cur.setHours(hh, mm, 0, 0);
    const addIfValid = (d) => {
        if (d <= until)
            dates.push(new Date(d));
    };
    if (rec === "weekly" || rec === "biweekly") {
        const step = (interval || 1) * 7;
        while (cur <= until) {
            addIfValid(cur);
            cur = new Date(cur.getTime() + step * 24 * 60 * 60 * 1000);
        }
        return dates;
    }
    if (rec === "monthly") {
        while (cur <= until) {
            addIfValid(cur);
            cur = new Date(cur.getFullYear(), cur.getMonth() + 1, cur.getDate(), hh, mm);
        }
        return dates;
    }
    if (rec === "yearly") {
        while (cur <= until) {
            addIfValid(cur);
            cur = new Date(cur.getFullYear() + 1, cur.getMonth(), cur.getDate(), hh, mm);
        }
        return dates;
    }
    if (rec === "months" && months.length) {
        const year = now.getFullYear();
        for (const m of months) {
            const d = new Date(year, m - 1, cur.getDate(), hh, mm);
            if (d >= now && d <= until)
                dates.push(d);
        }
    }
    return dates;
}
exports.onScheduleCreate = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/escalas/{id}")
    .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const tenantId = context.params.tenantId;
    const title = String(data.title || "Escala");
    const deptId = String(data.departmentId || "");
    const deptName = String(data.departmentName || "");
    const time = String(data.time || "");
    const memberCpfs = Array.isArray(data.memberCpfs)
        ? data.memberCpfs.map((v) => String(v))
        : [];
    const date = data.date;
    const when = date ? date.toDate() : null;
    const dateTxt = when
        ? `${when.getDate().toString().padStart(2, "0")}/${(when.getMonth() + 1).toString().padStart(2, "0")}/${when.getFullYear()}`
        : "";
    const body = [
        title,
        dateTxt,
        time,
        deptName,
    ]
        .filter((v) => v && String(v).trim().length > 0)
        .join(" • ");
    await db
        .collection("igrejas")
        .doc(tenantId)
        .collection("notificacoes")
        .add({
        type: "escala",
        title: "Nova escala publicada",
        body,
        departmentId: deptId,
        memberCpfs,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
        await admin.messaging().send({
            topic: (0, pushNovoConteudo_1.topicPushNovo)(tenantId, "escala"),
            notification: {
                title: "Nova escala",
                body,
            },
            data: {
                tenantId,
                departmentId: deptId,
                scheduleId: context.params.id,
                type: "nova_escala",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
        });
    }
    catch (e) {
        console.error("FCM send error (nova escala / gypush):", e);
    }
});
/**
 * Antes: criava documentos em `noticias` a partir de `event_templates` (cultos semanais),
 * misturando rotina com o Feed de eventos especiais.
 *
 * Agora: **desativado** — a rotina fica só em **Eventos Fixos** (`event_templates` + agenda).
 * O Feed / mural mostram apenas eventos criados manualmente (cultos especiais, campanhas, etc.).
 */
exports.autoGenerateEvents = functions
    .region("us-central1")
    .pubsub.schedule("10 3 * * *")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    functions.logger.info("autoGenerateEvents: no-op — noticias/ feed is only for special events; weekly routine uses event_templates.");
    return null;
});
/**
 * Resolve tenant ID por slug ou nome (ex.: "brasil-para-cristo" ou "Brasil para Cristo").
 */
async function resolveTenantIdBySlugOrName(slugOrName) {
    const s = String(slugOrName || "").trim().toLowerCase();
    if (!s)
        return null;
    const sAsName = s.replace(/-/g, " ");
    const tenantsSnap = await db.collection("tenants").get();
    for (const doc of tenantsSnap.docs) {
        const d = doc.data();
        const slug = String(d.slug ?? d.alias ?? "").trim().toLowerCase();
        const name = String(d.name ?? d.nome ?? "").trim().toLowerCase();
        if (slug === s || slug === sAsName || name.includes(s) || name.includes(sAsName) || s.includes(name) || sAsName.includes(name))
            return doc.id;
    }
    return null;
}
/** Resolve ID do documento em igrejas por slug, nome ou id (ex.: brasil-para-cristo). */
async function resolveIgrejaIdBySlugOrName(slugOrName) {
    const s = String(slugOrName || "").trim().toLowerCase();
    if (!s)
        return null;
    const sAsName = s.replace(/-/g, " ");
    const igSnap = await db.collection("igrejas").get();
    for (const doc of igSnap.docs) {
        if (doc.id.toLowerCase() === s || doc.id.toLowerCase().includes(s))
            return doc.id;
        const d = doc.data();
        const slug = String(d.slug ?? d.alias ?? "").trim().toLowerCase();
        const name = String(d.name ?? d.nome ?? d.nomeFantasia ?? "").trim().toLowerCase();
        if (slug === s || slug === sAsName || name.includes(s) || name.includes(sAsName) || s.includes(name))
            return doc.id;
    }
    return null;
}
async function resolveChurchIdForMigration(targetTenantIdParam, targetSlugParam) {
    if (targetTenantIdParam) {
        const ig = await db.collection("igrejas").doc(targetTenantIdParam).get();
        if (ig.exists)
            return targetTenantIdParam;
        const tn = await db.collection("tenants").doc(targetTenantIdParam).get();
        if (tn.exists) {
            const ig2 = await db.collection("igrejas").doc(targetTenantIdParam).get();
            if (ig2.exists)
                return targetTenantIdParam;
        }
    }
    if (targetSlugParam) {
        let id = await resolveIgrejaIdBySlugOrName(targetSlugParam);
        if (id)
            return id;
        id = await resolveTenantIdBySlugOrName(targetSlugParam);
        if (id && (await db.collection("igrejas").doc(id).get()).exists)
            return id;
    }
    return null;
}
function stripUndefined(obj) {
    const out = {};
    for (const [k, v] of Object.entries(obj)) {
        if (v !== undefined)
            out[k] = v;
    }
    return out;
}
async function runSyncMembersFromUsers(payload) {
    const targetTenantIdParam = typeof payload.targetTenantId === "string" ? payload.targetTenantId.trim() : "";
    const targetSlugParam = typeof payload.targetSlug === "string" ? payload.targetSlug.trim() : "";
    const targetChurchId = await resolveChurchIdForMigration(targetTenantIdParam, targetSlugParam);
    const migrateAllToChurch = !!targetChurchId;
    const usersSnap = await db.collection("users").get();
    const igrejaIdSet = new Set((await db.collection("igrejas").get()).docs.map((d) => d.id));
    let totalWritten = 0;
    const tenantIdsWritten = new Set();
    const igrejaIdsWritten = new Set();
    let usersUpdated = 0;
    const writer = db.bulkWriter();
    writer.onWriteError((err) => {
        functions.logger.warn("syncMembers bulkWriter", err.message);
        return err.failedAttempts < 4;
    });
    for (const userDoc of usersSnap.docs) {
        const uid = userDoc.id;
        const u = userDoc.data() || {};
        let tenantId = String(u.tenantId ?? u.tenant_id ?? "").trim();
        let igrejaId = String(u.igrejaId ?? u.igreja_id ?? "").trim();
        if (migrateAllToChurch && targetChurchId) {
            tenantId = targetChurchId;
            igrejaId = targetChurchId;
        }
        else if (!tenantId && !igrejaId) {
            continue;
        }
        const nome = String(u.nome ?? u.name ?? u.displayName ?? u.NOME_COMPLETO ?? "").trim() || "Membro";
        const userEmail = String(u.email ?? u.Email ?? u.EMAIL ?? "").trim();
        const cpf = String(u.cpf ?? u.CPF ?? "").replace(/\D/g, "").trim();
        const photoUrl = String(u.photoUrl ?? u.fotoUrl ?? u.photoURL ?? u.avatarUrl ?? u.imageUrl ?? u.FOTO_URL_OU_ID ?? "").trim();
        const status = u.ativo === false || u.active === false ? "inativo" : "ativo";
        const sexo = String(u.SEXO ?? u.sexo ?? u.genero ?? "").trim();
        const dataNasc = u.DATA_NASCIMENTO ?? u.dataNascimento ?? u.birthDate ?? null;
        const memberPayload = {
            authUid: uid,
            NOME_COMPLETO: nome,
            nome,
            name: nome,
            EMAIL: userEmail,
            email: userEmail,
            CPF: cpf,
            cpf,
            STATUS: status,
            status,
            tenantId: tenantId || igrejaId,
            igrejaId: igrejaId || tenantId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            syncedFromUsersAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (sexo) {
            memberPayload.SEXO = sexo;
            memberPayload.sexo = sexo;
        }
        if (dataNasc !== undefined && dataNasc !== null) {
            memberPayload.DATA_NASCIMENTO = dataNasc;
            memberPayload.dataNascimento = dataNasc;
        }
        if (photoUrl && (photoUrl.startsWith("http://") || photoUrl.startsWith("https://"))) {
            memberPayload.FOTO_URL_OU_ID = photoUrl;
            memberPayload.fotoUrl = photoUrl;
            memberPayload.photoUrl = photoUrl;
        }
        const idsToSync = new Set();
        if (tenantId)
            idsToSync.add(tenantId);
        if (igrejaId)
            idsToSync.add(igrejaId);
        const payloadClean = stripUndefined(memberPayload);
        for (const churchId of idsToSync) {
            if (!churchId || !igrejaIdSet.has(churchId))
                continue;
            writer.set(db.collection("igrejas").doc(churchId).collection("membros").doc(uid), payloadClean, { merge: true });
            tenantIdsWritten.add(churchId);
            igrejaIdsWritten.add(churchId);
            totalWritten++;
        }
        if (migrateAllToChurch && targetChurchId) {
            try {
                await db.collection("users").doc(uid).set({ tenantId: targetChurchId, igrejaId: targetChurchId }, { merge: true });
                usersUpdated++;
            }
            catch {
                // ignora
            }
        }
    }
    await writer.close();
    const message = migrateAllToChurch && targetChurchId
        ? `Migração para a igreja concluída: ${usersSnap.size} usuários processados, ${totalWritten} documentos em igrejas/*/membros, ${usersUpdated} usuários atualizados.`
        : `Migração concluída: ${usersSnap.size} usuários processados, ${totalWritten} escritos em igrejas/*/membros.`;
    return {
        ok: true,
        usersProcessed: usersSnap.size,
        membersWritten: totalWritten,
        usersUpdated: migrateAllToChurch ? usersUpdated : undefined,
        targetTenantId: targetChurchId ?? undefined,
        tenantsUpdated: Array.from(tenantIdsWritten),
        igrejasUpdated: Array.from(igrejaIdsWritten),
        message,
    };
}
/**
 * Migração: sincroniza todos os usuários (users) para a tabela de membros da igreja
 * para igrejas/{id}/membros. Garante que cada igreja tenha seus
 * membros com nome, e-mail, foto (FOTO_URL_OU_ID) para o painel buscar corretamente.
 * Acesso: MASTER, ADMIN, ADM ou usuário raihom@gmail.com (admin/master do painel).
 *
 * Parâmetros opcionais em data:
 * - targetTenantId: string — ID do tenant de destino (todos os usuários são migrados para esta igreja).
 * - targetSlug: string — Slug ou nome da igreja (ex.: "brasil-para-cristo"). Usado se targetTenantId não for passado.
 * Quando targetTenantId ou targetSlug é informado: TODOS os usuários são escritos como membros dessa igreja
 * e seus documentos em users são atualizados com tenantId/igrejaId dessa igreja.
 */
exports.syncMembersFromUsers = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login.");
        }
        let role = String(context.auth.token?.role || "").toUpperCase();
        const email = String(context.auth.token?.email || "").trim().toLowerCase();
        let isAllowed = role === "MASTER" ||
            role === "ADMIN" ||
            role === "ADM" ||
            role === "GESTOR" ||
            email === "raihom@gmail.com";
        if (!isAllowed && context.auth.uid) {
            const userDoc = await db.collection("users").doc(context.auth.uid).get();
            const u = userDoc.data() || {};
            const roleFromDb = String(u.role ?? u.perfil ?? u.nivel ?? u.NIVEL ?? "").toUpperCase();
            if (roleFromDb)
                role = roleFromDb;
            isAllowed =
                role === "MASTER" ||
                    role === "ADMIN" ||
                    role === "ADM" ||
                    role === "GESTOR" ||
                    email === "raihom@gmail.com";
        }
        if (!isAllowed) {
            throw new functions.https.HttpsError("permission-denied", "Apenas MASTER, ADMIN, ADM ou GESTOR pode executar a migração. Seu perfil: " + (role || "(não definido)") + ". Defina o perfil no cadastro de usuários ou nos custom claims do Firebase Auth.");
        }
        const payload = (data && typeof data === "object") ? data : {};
        return await runSyncMembersFromUsers(payload);
    }
    catch (err) {
        if (err instanceof functions.https.HttpsError)
            throw err;
        const msg = err instanceof Error ? err.message : String(err);
        const stack = err instanceof Error ? err.stack : undefined;
        functions.logger.error("syncMembersFromUsers error", { message: msg, stack });
        throw new functions.https.HttpsError("internal", `Erro na migração: ${msg}`);
    }
});
/**
 * Migração completa: (1) igrejas/{id}/members → membros; (2) users → igrejas/{id}/membros.
 * Processa todas as igrejas na coleção igrejas (não depende de tenants).
 */
exports.migrateMembersFull = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
    try {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Faça login.");
        }
        let role = String(context.auth.token?.role || "").toUpperCase();
        const email = String(context.auth.token?.email || "").trim().toLowerCase();
        let isAllowed = role === "MASTER" ||
            role === "ADMIN" ||
            role === "ADM" ||
            role === "GESTOR" ||
            email === "raihom@gmail.com";
        if (!isAllowed && context.auth?.uid) {
            const userDoc = await db.collection("users").doc(context.auth.uid).get();
            const u = userDoc.data() || {};
            const roleFromDb = String(u.role ?? u.perfil ?? u.nivel ?? u.NIVEL ?? "").toUpperCase();
            if (roleFromDb)
                role = roleFromDb;
            isAllowed =
                role === "MASTER" ||
                    role === "ADMIN" ||
                    role === "ADM" ||
                    role === "GESTOR" ||
                    email === "raihom@gmail.com";
        }
        if (!isAllowed) {
            throw new functions.https.HttpsError("permission-denied", "Apenas MASTER, ADMIN, ADM ou GESTOR pode executar a migração completa.");
        }
        const payload = (data && typeof data === "object") ? data : {};
        const targetTenantIdParam = typeof payload.targetTenantId === "string" ? payload.targetTenantId.trim() : "";
        const targetSlugParam = typeof payload.targetSlug === "string" ? payload.targetSlug.trim() : "";
        const targetChurchId = await resolveChurchIdForMigration(targetTenantIdParam, targetSlugParam);
        let igrejaIds = [];
        if (targetChurchId) {
            igrejaIds = [targetChurchId];
        }
        else {
            const igSnap = await db.collection("igrejas").get();
            igrejaIds = igSnap.docs.map((d) => d.id);
        }
        let membersToMembrosCount = 0;
        for (const id of igrejaIds) {
            try {
                membersToMembrosCount += await migrateIgrejaMembersToMembrosForChurch(id);
            }
            catch (e) {
                functions.logger.warn("migrateMembersFull igreja", id, e);
            }
        }
        const syncPayload = {};
        if (targetChurchId)
            syncPayload.targetTenantId = targetChurchId;
        else if (targetSlugParam)
            syncPayload.targetSlug = targetSlugParam;
        const syncResult = await runSyncMembersFromUsers(syncPayload);
        const usersProcessed = syncResult.usersProcessed;
        const membersWritten = syncResult.membersWritten;
        const usersUpdated = syncResult.usersUpdated;
        const message = `Migração completa: ${membersToMembrosCount} doc(s) members→membros, ` +
            `${usersProcessed} usuários processados, ${membersWritten} em igrejas/*/membros.` +
            (usersUpdated != null ? ` ${usersUpdated} users atualizados com igreja.` : "");
        return {
            ok: true,
            consolidatedCount: membersToMembrosCount,
            usersProcessed,
            membersWritten,
            usersUpdated: usersUpdated ?? undefined,
            message,
        };
    }
    catch (err) {
        if (err instanceof functions.https.HttpsError)
            throw err;
        const msg = err instanceof Error ? err.message : String(err);
        functions.logger.error("migrateMembersFull error", { message: msg, stack: err instanceof Error ? err.stack : "" });
        throw new functions.https.HttpsError("internal", `Erro na migração completa: ${msg}`);
    }
});
/**
 * Copia igrejas/{id}/members → igrejas/{id}/membros (merge). Admin SDK ignora regras de segurança.
 */
async function migrateIgrejaMembersToMembrosForChurch(igrejaId) {
    const churchRef = db.collection("igrejas").doc(igrejaId);
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
        const batch = db.batch();
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
async function callerCanMigrateIgrejaMembers(context, churchId) {
    if (!context.auth?.uid)
        return false;
    const email = String(context.auth.token?.email || "").trim().toLowerCase();
    if (email === "raihom@gmail.com")
        return true;
    let role = String(context.auth.token?.role || "").toUpperCase();
    const tid = String(context.auth.token?.igrejaId || context.auth.token?.tenantId || "").trim();
    if (role === "MASTER" || role === "ADMIN" || role === "ADM")
        return true;
    if ((role === "GESTOR" || role === "ADMINISTRADOR") && tid === churchId)
        return true;
    const userDoc = await db.collection("users").doc(context.auth.uid).get();
    const u = userDoc.data() || {};
    const roleDb = String(u.role ?? u.perfil ?? "").toUpperCase();
    if (roleDb)
        role = roleDb;
    const ig = String(u.igrejaId ?? u.tenantId ?? "").trim();
    if (role === "MASTER" || role === "ADMIN" || role === "ADM")
        return true;
    if (role === "GESTOR" && ig === churchId)
        return true;
    return false;
}
/**
 * Migração automática members → membros para uma igreja (gestor da igreja ou master).
 * Chamada ao abrir o painel da igreja.
 */
exports.ensureMigrateMembersToMembros = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const payload = (data && typeof data === "object") ? data : {};
    const tenantId = String(payload.tenantId || payload.igrejaId || "").trim();
    if (!tenantId) {
        throw new functions.https.HttpsError("invalid-argument", "Informe tenantId (id da igreja).");
    }
    const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
    if (!igrejaSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Igreja não encontrada.");
    }
    const ok = await callerCanMigrateIgrejaMembers(context, tenantId);
    if (!ok) {
        throw new functions.https.HttpsError("permission-denied", "Apenas gestor desta igreja ou master pode executar.");
    }
    const copied = await migrateIgrejaMembersToMembrosForChurch(tenantId);
    functions.logger.info("ensureMigrateMembersToMembros", { tenantId, copied });
    return { ok: true, tenantId, copied, message: copied > 0 ? `${copied} registro(s) copiados de members para membros.` : "Nada a migrar (members vazio ou já sincronizado)." };
});
/**
 * A cada 30 min: todas as igrejas com subcoleção members copiam para membros (idempotente).
 */
exports.scheduledMigrateIgrejaMembersToMembros = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .pubsub.schedule("every 30 minutes")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const igrejas = await db.collection("igrejas").get();
    let totalCopied = 0;
    let churchesTouched = 0;
    for (const doc of igrejas.docs) {
        try {
            const n = await migrateIgrejaMembersToMembrosForChurch(doc.id);
            if (n > 0) {
                totalCopied += n;
                churchesTouched++;
                functions.logger.info("scheduledMigrate: church", { id: doc.id, copied: n });
            }
        }
        catch (e) {
            functions.logger.warn("scheduledMigrate: skip church", doc.id, e);
        }
    }
    functions.logger.info("scheduledMigrateIgrejaMembersToMembros done", {
        igrejas: igrejas.size,
        churchesTouched,
        totalCopied,
    });
    return null;
});
/**
 * Diária: gera lançamentos de receita recorrente (competência yyyy-MM) no caixa, idempotente — alinhado ao app.
 */
exports.scheduledGerarReceitasRecorrentesPendentes = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .pubsub.schedule("every day 03:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
    const igrejas = await db.collection("igrejas").get();
    let total = 0;
    let churchesTouched = 0;
    for (const doc of igrejas.docs) {
        try {
            const n = await (0, receitasRecorrentesScheduled_1.gerarReceitasRecorrentesPendentesForTenant)(doc.id);
            if (n > 0) {
                total += n;
                churchesTouched++;
                functions.logger.info("scheduledGerarReceitas: church", { id: doc.id, criados: n });
            }
        }
        catch (e) {
            functions.logger.warn("scheduledGerarReceitas: skip church", doc.id, e);
        }
    }
    functions.logger.info("scheduledGerarReceitasRecorrentesPendentes done", {
        igrejas: igrejas.size,
        churchesTouched,
        totalCriados: total,
    });
    return null;
});
/**
 * MASTER/ADM: migra members → membros em todas as igrejas (uma chamada).
 */
exports.migrateAllIgrejasMembersToMembros = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Faça login.");
    }
    const email = String(context.auth.token?.email || "").trim().toLowerCase();
    let role = String(context.auth.token?.role || "").toUpperCase();
    if (!["MASTER", "ADMIN", "ADM"].includes(role) && email !== "raihom@gmail.com") {
        const userDoc = await db.collection("users").doc(context.auth.uid).get();
        const u = userDoc.data() || {};
        role = String(u.role ?? "").toUpperCase();
    }
    if (!["MASTER", "ADMIN", "ADM"].includes(role) && email !== "raihom@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "Apenas MASTER ou ADM.");
    }
    const igrejas = await db.collection("igrejas").get();
    let totalCopied = 0;
    let touched = 0;
    for (const doc of igrejas.docs) {
        const n = await migrateIgrejaMembersToMembrosForChurch(doc.id);
        if (n > 0) {
            totalCopied += n;
            touched++;
        }
    }
    return {
        ok: true,
        igrejas: igrejas.size,
        churchesWithData: touched,
        totalCopied,
        message: `Migrados ${totalCopied} documento(s) em ${touched} igreja(s).`,
    };
});
function maskNomePublico(nome) {
    const parts = String(nome || "")
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (parts.length === 0)
        return "";
    if (parts.length === 1) {
        const p0 = parts[0];
        return p0.length > 0 ? `${p0.charAt(0)}***` : "";
    }
    const last = parts[parts.length - 1];
    return `${parts[0]} ${last.length > 0 ? last.charAt(0) : ""}.`;
}
function memberActiveFromData(m) {
    const statusRaw = m.STATUS ?? m.status ?? m.ativo ?? m.active;
    if (typeof statusRaw === "boolean")
        return statusRaw;
    if (typeof statusRaw === "string") {
        const s = statusRaw.toLowerCase().trim();
        if (["inativo", "inactive", "false", "0", "desligado", "bloqueado"].includes(s))
            return false;
        if (["ativo", "active", "true", "1", "membro"].includes(s))
            return true;
    }
    if (typeof statusRaw === "number" && statusRaw === 0)
        return false;
    return true;
}
function carteiraValidityHint(m) {
    const perm = m.CARTEIRA_PERMANENTE === true || String(m.CARTEIRA_PERMANENTE || "").toLowerCase() === "true";
    if (perm)
        return "Permanente";
    const v = m.CARTEIRA_VALIDADE;
    if (v && typeof v.toDate === "function") {
        try {
            const d = v.toDate();
            if (d && !Number.isNaN(d.getTime())) {
                return d.toISOString().slice(0, 10);
            }
        }
        catch {
            /* ignore */
        }
    }
    return "";
}
/**
 * Validação pública de carteirinha (QR): confere se o membro existe e está ativo — sem expor dados sensíveis.
 * Não exige autenticação. Usa Admin SDK.
 */
exports.validateCarteirinhaPublic = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data) => {
    const payload = data && typeof data === "object" ? data : {};
    const tenantId = String(payload.tenantId || payload.igrejaId || payload.igreja || "").trim();
    const memberId = String(payload.memberId || payload.id || payload.membro || "").trim();
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "Informe tenantId e memberId.");
    }
    const igrejaSnap = await db.collection("igrejas").doc(tenantId).get();
    if (!igrejaSnap.exists) {
        return {
            ok: true,
            found: false,
            active: false,
            churchName: "",
            titularMascarado: "",
            validityHint: "",
            message: "Igreja não encontrada.",
        };
    }
    const church = igrejaSnap.data() || {};
    const churchName = String(church.nome || church.name || church.slug || tenantId);
    const paths = [
        db.collection("igrejas").doc(tenantId).collection("membros").doc(memberId),
        db.collection("igrejas").doc(tenantId).collection("members").doc(memberId),
    ];
    let snap = null;
    for (const ref of paths) {
        const s = await ref.get();
        if (s.exists) {
            snap = s;
            break;
        }
    }
    if (!snap || !snap.exists) {
        return {
            ok: true,
            found: false,
            active: false,
            churchName,
            titularMascarado: "",
            validityHint: "",
            message: "Credencial não encontrada nesta igreja.",
        };
    }
    const m = (snap.data() || {});
    const active = memberActiveFromData(m);
    const nomeFull = String(m.NOME_COMPLETO || m.nome || m.name || "").trim();
    const titularMascarado = maskNomePublico(nomeFull);
    const validityHint = carteiraValidityHint(m);
    return {
        ok: true,
        found: true,
        active,
        churchName,
        titularMascarado,
        validityHint,
        message: active
            ? "Credencial localizada e situação ativa no sistema."
            : "Credencial localizada, porém o cadastro não está ativo.",
    };
});
/**
 * Novo cadastro em igrejas/{tenantId}/membros: envia push para tópico admin.
 */
exports.onNewMember = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/membros/{membroId}")
    .onCreate(async (snap, context) => {
    const data = (snap.data() || {});
    const nome = String(data.NOME_COMPLETO || data.nome || data.name || "Novo membro").trim();
    const tenantId = String(context.params.tenantId || "").trim();
    const membroId = String(context.params.membroId || "").trim();
    try {
        await admin.messaging().send({
            topic: "admin",
            notification: {
                title: "⚡ Novo Cadastro!",
                body: `${nome} acabou de se cadastrar pelo site público.`,
            },
            data: {
                type: "new_member",
                tenantId,
                memberId: membroId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
        });
    }
    catch (err) {
        functions.logger.error("onNewMember notify error", {
            tenantId,
            memberId: membroId,
            message: err instanceof Error ? err.message : String(err),
        });
    }
    const publicSignup = data.PUBLIC_SIGNUP === true || data.public_signup === true;
    const emailTo = String(data.EMAIL || data.email || "")
        .trim()
        .toLowerCase();
    if (publicSignup && emailTo.includes("@")) {
        let churchName = "";
        let slugForUrl = String(data.slug || data.alias || "").trim();
        try {
            const ig = await db.collection("igrejas").doc(tenantId).get();
            const igd = ig.data() || {};
            churchName = String(igd.nome || igd.name || "").trim();
            if (!slugForUrl) {
                slugForUrl = String(igd.slug || igd.alias || tenantId).trim();
            }
        }
        catch (e) {
            functions.logger.warn("onNewMember church fetch for email", e);
        }
        const memberName = String(data.NOME_COMPLETO || data.nome || data.name || "").trim();
        try {
            await (0, publicSignupEmail_1.trySendPublicSignupConfirmationEmail)({
                to: emailTo,
                memberName: memberName || "Membro",
                churchName: churchName || "Igreja",
                protocol: membroId,
                slugForUrl: slugForUrl || tenantId,
            });
        }
        catch (e) {
            functions.logger.error("onNewMember public signup email", e);
        }
    }
    return null;
});
/**
 * Compatibilidade legado: novo cadastro em igrejas/{tenantId}/members.
 */
exports.onNewMemberLegacy = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/members/{membroId}")
    .onCreate(async (snap, context) => {
    const data = (snap.data() || {});
    const nome = String(data.NOME_COMPLETO || data.nome || data.name || "Novo membro").trim();
    const tenantId = String(context.params.tenantId || "").trim();
    const membroId = String(context.params.membroId || "").trim();
    try {
        await admin.messaging().send({
            topic: "admin",
            notification: {
                title: "⚡ Novo Cadastro!",
                body: `${nome} acabou de se cadastrar pelo site público.`,
            },
            data: {
                type: "new_member",
                tenantId,
                memberId: membroId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
        });
    }
    catch (err) {
        functions.logger.error("onNewMemberLegacy notify error", {
            tenantId,
            memberId: membroId,
            message: err instanceof Error ? err.message : String(err),
        });
    }
    const publicSignupL = data.PUBLIC_SIGNUP === true || data.public_signup === true;
    const emailToL = String(data.EMAIL || data.email || "")
        .trim()
        .toLowerCase();
    if (publicSignupL && emailToL.includes("@")) {
        let churchNameL = "";
        let slugForUrlL = String(data.slug || data.alias || "").trim();
        try {
            const igL = await db.collection("igrejas").doc(tenantId).get();
            const igdL = igL.data() || {};
            churchNameL = String(igdL.nome || igdL.name || "").trim();
            if (!slugForUrlL) {
                slugForUrlL = String(igdL.slug || igdL.alias || tenantId).trim();
            }
        }
        catch (e) {
            functions.logger.warn("onNewMemberLegacy church fetch for email", e);
        }
        const memberNameL = String(data.NOME_COMPLETO || data.nome || data.name || "").trim();
        try {
            await (0, publicSignupEmail_1.trySendPublicSignupConfirmationEmail)({
                to: emailToL,
                memberName: memberNameL || "Membro",
                churchName: churchNameL || "Igreja",
                protocol: membroId,
                slugForUrl: slugForUrlL || tenantId,
            });
        }
        catch (e) {
            functions.logger.error("onNewMemberLegacy public signup email", e);
        }
    }
    return null;
});
/**
 * Trigger legado: antes gerava `thumb_<nome>.jpg` em todo o bucket (membros, eventos, etc.).
 * Mantido exportado para não quebrar deploy; **não** cria ficheiros — política: um ficheiro canónico por upload + limpeza no cliente.
 */
exports.generateThumbnail = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 10, memory: "256MB" })
    .storage.object()
    .onFinalize(async () => null);
/**
 * Incrementa acessos ao domínio (Flutter web) em `config/analytics.daily[YYYY-MM-DD]`.
 * Chamada sem login — usada pelo site; o Painel Master lê o mesmo documento.
 */
exports.recordDomainDailyHit = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 10, memory: "128MB" })
    .https.onCall(async (data) => {
    const payload = data && typeof data === "object" ? data : {};
    let dateKey = String(payload.dateKey || "").trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
        dateKey = new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });
    }
    const ref = db.doc("config/analytics");
    await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const prev = (snap.data()?.daily || {});
        const cur = typeof prev[dateKey] === "number"
            ? prev[dateKey]
            : parseInt(String(prev[dateKey] ?? "0"), 10) || 0;
        const next = { ...prev, [dateKey]: cur + 1 };
        t.set(ref, {
            daily: next,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            lastHitSource: "flutter_web",
        }, { merge: true });
    });
    return { ok: true, dateKey };
});
var shareEvento_1 = require("./shareEvento");
Object.defineProperty(exports, "shareEvento", { enumerable: true, get: function () { return shareEvento_1.shareEvento; } });
var certificadosLote_1 = require("./certificadosLote");
Object.defineProperty(exports, "gerarCertificadosEmLote", { enumerable: true, get: function () { return certificadosLote_1.gerarCertificadosEmLote; } });
var processarCertificadosLote_1 = require("./processarCertificadosLote");
Object.defineProperty(exports, "processarCertificadosLote", { enumerable: true, get: function () { return processarCertificadosLote_1.processarCertificadosLote; } });
var pastoralComms_1 = require("./pastoralComms");
Object.defineProperty(exports, "sendSegmentedPush", { enumerable: true, get: function () { return pastoralComms_1.sendSegmentedPush; } });
Object.defineProperty(exports, "archivePastoralMessage", { enumerable: true, get: function () { return pastoralComms_1.archivePastoralMessage; } });
Object.defineProperty(exports, "updatePastoralMessage", { enumerable: true, get: function () { return pastoralComms_1.updatePastoralMessage; } });
Object.defineProperty(exports, "resendPastoralMessage", { enumerable: true, get: function () { return pastoralComms_1.resendPastoralMessage; } });
Object.defineProperty(exports, "resendDevotionalEnvio", { enumerable: true, get: function () { return pastoralComms_1.resendDevotionalEnvio; } });
Object.defineProperty(exports, "deleteDevotionalEnvio", { enumerable: true, get: function () { return pastoralComms_1.deleteDevotionalEnvio; } });
Object.defineProperty(exports, "notifySchedulePublished", { enumerable: true, get: function () { return pastoralComms_1.notifySchedulePublished; } });
Object.defineProperty(exports, "onEscalaImpedimentoNotifyLeaders", { enumerable: true, get: function () { return pastoralComms_1.onEscalaImpedimentoNotifyLeaders; } });
Object.defineProperty(exports, "respondScheduleSwap", { enumerable: true, get: function () { return pastoralComms_1.respondScheduleSwap; } });
Object.defineProperty(exports, "onEscalaTrocaInviteTarget", { enumerable: true, get: function () { return pastoralComms_1.onEscalaTrocaInviteTarget; } });
Object.defineProperty(exports, "dailyBirthdayTopicPush", { enumerable: true, get: function () { return pastoralComms_1.dailyBirthdayTopicPush; } });
Object.defineProperty(exports, "dayBeforeScaleReminder", { enumerable: true, get: function () { return pastoralComms_1.dayBeforeScaleReminder; } });
Object.defineProperty(exports, "rollingScaleRemindersConfirmed", { enumerable: true, get: function () { return pastoralComms_1.rollingScaleRemindersConfirmed; } });
Object.defineProperty(exports, "hourlyDevotionalBroadcast", { enumerable: true, get: function () { return pastoralComms_1.hourlyDevotionalBroadcast; } });
var storageCleanupOnFirestoreDelete_1 = require("./storageCleanupOnFirestoreDelete");
Object.defineProperty(exports, "onIgrejaMembroDeleteCleanupStorage", { enumerable: true, get: function () { return storageCleanupOnFirestoreDelete_1.onIgrejaMembroDeleteCleanupStorage; } });
Object.defineProperty(exports, "onIgrejaNoticiaDeleteCleanupStorage", { enumerable: true, get: function () { return storageCleanupOnFirestoreDelete_1.onIgrejaNoticiaDeleteCleanupStorage; } });
Object.defineProperty(exports, "onIgrejaPatrimonioDeleteCleanupStorage", { enumerable: true, get: function () { return storageCleanupOnFirestoreDelete_1.onIgrejaPatrimonioDeleteCleanupStorage; } });
var pushNovoConteudo_2 = require("./pushNovoConteudo");
Object.defineProperty(exports, "onNovoAvisoMuralPush", { enumerable: true, get: function () { return pushNovoConteudo_2.onNovoAvisoMuralPush; } });
Object.defineProperty(exports, "onNovoEventoNoticiaPush", { enumerable: true, get: function () { return pushNovoConteudo_2.onNovoEventoNoticiaPush; } });
var fornecedorAgendaReminders_1 = require("./fornecedorAgendaReminders");
Object.defineProperty(exports, "scheduledFornecedorAgendaReminders", { enumerable: true, get: function () { return fornecedorAgendaReminders_1.scheduledFornecedorAgendaReminders; } });
var churchMercadoPago_2 = require("./churchMercadoPago");
Object.defineProperty(exports, "saveChurchMercadoPagoCredentials", { enumerable: true, get: function () { return churchMercadoPago_2.saveChurchMercadoPagoCredentials; } });
Object.defineProperty(exports, "ensureChurchTreasuryAccountPresets", { enumerable: true, get: function () { return churchMercadoPago_2.ensureChurchTreasuryAccountPresets; } });
Object.defineProperty(exports, "createChurchDonationPix", { enumerable: true, get: function () { return churchMercadoPago_2.createChurchDonationPix; } });
Object.defineProperty(exports, "createChurchDonationPreference", { enumerable: true, get: function () { return churchMercadoPago_2.createChurchDonationPreference; } });
Object.defineProperty(exports, "pruneContribuicoesDizimoHistorico", { enumerable: true, get: function () { return churchMercadoPago_2.pruneContribuicoesDizimoHistorico; } });
//# sourceMappingURL=index.js.map