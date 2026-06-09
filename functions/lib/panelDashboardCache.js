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
exports.scheduledRefreshPanelCaches = exports.warmChurchTenantCaches = exports.getChurchPanelSnapshot = exports.onChurchPedidoOracaoWritePanelDashboard = exports.onChurchVisitanteWritePanelDashboard = exports.onChurchDepartamentoWritePanelDashboard = exports.onChurchNoticiaWritePanelDashboard = exports.onChurchAvisoWritePanelDashboard = exports.onChurchMembroWritePanelDashboard = exports.onChurchMembroWriteSyncBirthIndex = void 0;
exports.recomputePanelDashboardSummary = recomputePanelDashboardSummary;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const membersDirectoryCache_1 = require("./membersDirectoryCache");
const panelMediaPrefetch_1 = require("./panelMediaPrefetch");
const tenantCallableResolve_1 = require("./tenantCallableResolve");
const churchClusterAnchors_1 = require("./churchClusterAnchors");
const churchRootCountersMirror_1 = require("./churchRootCountersMirror");
const panelStatisticsCache_1 = require("./panelStatisticsCache");
const panelPublicSiteCache_1 = require("./panelPublicSiteCache");
const RECOMPUTE_MIN_INTERVAL_MS = 45000;
const RECENT_AVISOS = 8;
const RECENT_EVENTOS = 8;
const MEMBERS_SCAN_LIMIT = 800;
const DEPT_SCAN_LIMIT = 120;
/** Painel: um único `igrejas/{churchId}` — sem cluster/alias. */
function clusterDocIdsForPanel(seed) {
    const t = String(seed || "").trim();
    return t ? [t] : [];
}
function memberGenderCategory(d) {
    const raw = pickString(d, ["SEXO", "sexo", "genero", "gender"]);
    const s = String(raw || "").toLowerCase().trim();
    if (!s)
        return "";
    if (s === "f" || s === "2" || s === "female")
        return "F";
    if (s.startsWith("mulh") || s.includes("femin") || s === "femea" || s === "fêmea")
        return "F";
    if (s === "m" || s === "1" || s === "male" || s === "h")
        return "M";
    if (s.startsWith("masc") || s.startsWith("hom"))
        return "M";
    if (s === "masculino")
        return "M";
    if (s === "feminino")
        return "F";
    return "";
}
function memberAgeYears(d) {
    const keys = [
        "DATA_NASCIMENTO",
        "dataNascimento",
        "birthDate",
        "nascimento",
        "data_nascimento",
    ];
    for (const k of keys) {
        const raw = d[k];
        if (raw instanceof admin.firestore.Timestamp) {
            const birth = raw.toDate();
            const now = new Date();
            let age = now.getFullYear() - birth.getFullYear();
            const m = now.getMonth() - birth.getMonth();
            if (m < 0 || (m === 0 && now.getDate() < birth.getDate()))
                age--;
            return age;
        }
    }
    for (const k of ["IDADE", "idade", "age"]) {
        const v = d[k];
        if (typeof v === "number" && v >= 0 && v < 130)
            return v;
    }
    return null;
}
function computeMemberDemographics(memberDocs) {
    let homens = 0;
    let mulheres = 0;
    let criancas = 0;
    for (const doc of memberDocs) {
        const d = doc.data();
        if (!memberIsActive(d))
            continue;
        const age = memberAgeYears(d);
        if (age != null && age < 13) {
            criancas++;
            continue;
        }
        const g = memberGenderCategory(d);
        if (g === "M")
            homens++;
        else if (g === "F")
            mulheres++;
    }
    return { homens, mulheres, criancas };
}
function memberDedupeKey(doc) {
    const d = doc.data();
    let cpf = canonicalCpf(pickString(d, ["CPF", "cpf"]));
    if (cpf.length !== 11) {
        const idDigits = normCpf(doc.id);
        if (idDigits.length >= 9 && idDigits.length <= 11) {
            cpf = canonicalCpf(idDigits);
        }
    }
    if (cpf.length === 11)
        return `cpf:${cpf}`;
    return `id:${doc.ref.path}`;
}
async function mergeMemberDocs(db, clusterIds) {
    const seen = new Set();
    const merged = [];
    for (const id of clusterIds) {
        try {
            const snap = await db
                .collection("igrejas")
                .doc(id)
                .collection("membros")
                .limit(MEMBERS_SCAN_LIMIT)
                .get();
            for (const doc of snap.docs) {
                const key = memberDedupeKey(doc);
                if (seen.has(key))
                    continue;
                seen.add(key);
                merged.push(doc);
            }
        }
        catch (e) {
            functions.logger.warn("panelDashboardCache: merge membros", { id, e });
        }
    }
    return merged;
}
async function mergeDepartmentDocs(db, clusterIds) {
    const seen = new Set();
    const merged = [];
    for (const id of clusterIds) {
        try {
            const snap = await db
                .collection("igrejas")
                .doc(id)
                .collection("departamentos")
                .limit(DEPT_SCAN_LIMIT)
                .get();
            for (const doc of snap.docs) {
                const data = doc.data();
                const name = String(data.name ?? data.nome ?? doc.id).trim().toLowerCase();
                const key = name || doc.id;
                if (seen.has(key))
                    continue;
                seen.add(key);
                merged.push(doc);
            }
        }
        catch (e) {
            functions.logger.warn("panelDashboardCache: merge departamentos", { id, e });
        }
    }
    return merged;
}
async function mergeRecentPosts(db, clusterIds, collection, orderField, limit) {
    const byId = new Map();
    for (const id of clusterIds) {
        try {
            const snap = await db
                .collection("igrejas")
                .doc(id)
                .collection(collection)
                .orderBy(orderField, "desc")
                .limit(limit)
                .get();
            for (const doc of snap.docs) {
                if (!byId.has(doc.id))
                    byId.set(doc.id, doc);
            }
        }
        catch (e) {
            functions.logger.warn(`panelDashboardCache: merge ${collection}`, { id, e });
        }
    }
    const docs = Array.from(byId.values());
    docs.sort((a, b) => {
        const av = a.data()[orderField];
        const bv = b.data()[orderField];
        const am = av instanceof admin.firestore.Timestamp ? av.toMillis() : 0;
        const bm = bv instanceof admin.firestore.Timestamp ? bv.toMillis() : 0;
        return bm - am;
    });
    return docs.slice(0, limit);
}
async function mergeUpcomingEventDocs(db, clusterIds) {
    const byId = new Map();
    for (const id of clusterIds) {
        try {
            const snap = await db
                .collection("igrejas")
                .doc(id)
                .collection("eventos")
                .where("type", "==", "evento")
                .orderBy("startAt", "asc")
                .limit(24)
                .get();
            for (const doc of snap.docs) {
                if (!byId.has(doc.id))
                    byId.set(doc.id, doc);
            }
        }
        catch (e) {
            functions.logger.warn("panelDashboardCache: merge upcoming eventos", { id, e });
        }
    }
    const docs = Array.from(byId.values());
    docs.sort((a, b) => {
        const av = a.data().startAt;
        const bv = b.data().startAt;
        const am = av instanceof admin.firestore.Timestamp ? av.toMillis() : 0;
        const bm = bv instanceof admin.firestore.Timestamp ? bv.toMillis() : 0;
        return am - bm;
    });
    return docs.slice(0, 24);
}
async function loadBirthdayMemberDocsCluster(db, clusterIds) {
    const seen = new Set();
    const merged = [];
    const month = new Date().getMonth() + 1;
    for (const id of clusterIds) {
        try {
            const membrosCol = db.collection("igrejas").doc(id).collection("membros");
            const snap = await membrosCol
                .where("birthMonth", "==", month)
                .limit(120)
                .get();
            for (const doc of snap.docs) {
                const key = memberDedupeKey(doc);
                if (seen.has(key))
                    continue;
                seen.add(key);
                merged.push(doc);
            }
        }
        catch (e) {
            functions.logger.warn("panelDashboardCache: birthMonth cluster", { id, e });
        }
    }
    return merged;
}
async function richestChurchData(db, clusterIds) {
    let best;
    let bestScore = -1;
    for (const id of clusterIds) {
        try {
            const snap = await db.collection("igrejas").doc(id).get();
            if (!snap.exists)
                continue;
            const data = snap.data();
            let score = Object.keys(data).length;
            const depts = data.departamentos ?? data.departments;
            if (Array.isArray(depts))
                score += depts.length * 4;
            if (pickString(data, ["slug", "slugId", "alias"]))
                score += 20;
            if (pickString(data, ["name", "nome"]))
                score += 10;
            if (score > bestScore) {
                bestScore = score;
                best = data;
            }
        }
        catch (_) { }
    }
    return best;
}
async function safeCount(q) {
    try {
        const agg = await q.count().get();
        return agg.data().count;
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: count falhou", { e });
        return 0;
    }
}
async function sumCountsAcrossCluster(db, clusterIds, counter) {
    let total = 0;
    for (const id of clusterIds) {
        try {
            total += await counter(db.collection("igrejas").doc(id));
        }
        catch (_) { }
    }
    return total;
}
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
        "imagem_url",
        "imagemUrl",
        "fotoUrl",
        "FOTO_URL_OU_ID",
        "foto_url",
        "coverUrl",
        "capaUrl",
        "coverImageUrl",
        "bannerUrl",
        "fotoURL",
        "FOTO_URL",
        "imageUrl",
        "photoUrl",
        "foto",
        "FOTO",
        "avatarUrl",
        "profilePhotoUrl",
        "photoMedium",
        "photoThumb",
        "logoProcessedUrl",
    ];
    for (const k of keys) {
        const v = data[k];
        if (typeof v === "string" && v.trim().startsWith("http")) {
            return v.trim();
        }
    }
    return "";
}
function pickAvisoCoverUrl(data) {
    const direct = pickPhotoUrl(data);
    if (direct)
        return direct;
    const lists = [data.photoUrls, data.photos, data.images, data.fotos];
    for (const raw of lists) {
        if (!Array.isArray(raw))
            continue;
        for (const e of raw) {
            if (typeof e === "string" && e.trim().startsWith("http"))
                return e.trim();
            if (e && typeof e === "object") {
                const m = e;
                const u = pickPhotoUrl(m);
                if (u)
                    return u;
            }
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
function canonicalCpf(digits) {
    const d = normCpf(digits);
    if (!d)
        return "";
    if (d.length > 11)
        return d.substring(d.length - 11);
    if (d.length < 11)
        return d.padStart(11, "0");
    return d;
}
function memberIsActive(data) {
    const st = pickString(data, ["STATUS", "status"]).toLowerCase();
    return !st || st === "ativo";
}
function parseBirthMd(data) {
    const keys = [
        "DATA_NASCIMENTO",
        "dataNascimento",
        "birthDate",
        "nascimento",
        "data_nascimento",
    ];
    for (const k of keys) {
        const raw = data[k];
        if (raw instanceof admin.firestore.Timestamp) {
            const dt = raw.toDate();
            return { month: dt.getMonth() + 1, day: dt.getDate() };
        }
        if (raw instanceof Date) {
            return { month: raw.getMonth() + 1, day: raw.getDate() };
        }
    }
    return null;
}
function lightMember(doc) {
    const d = doc.data();
    const birth = parseBirthMd(d);
    const revRaw = d.fotoUrlCacheRevision ?? d.photoCacheRevision;
    const fotoUrlCacheRevision = typeof revRaw === "number" && Number.isFinite(revRaw)
        ? Math.floor(revRaw)
        : 0;
    const cpf = canonicalCpf(pickString(d, ["CPF", "cpf"]) || normCpf(doc.id));
    const telefone = pickString(d, [
        "TELEFONES",
        "telefones",
        "TELEFONE",
        "telefone",
        "whatsapp",
        "WHATSAPP",
        "celular",
        "CELULAR",
        "phone",
    ]) || null;
    return {
        memberDocId: doc.id,
        displayName: pickString(d, ["NOME_COMPLETO", "nome", "name"]) || "Membro",
        photoUrl: pickPhotoUrl(d) || null,
        fotoUrlCacheRevision,
        authUid: pickString(d, ["authUid", "firebaseUid", "uid", "userId"]) || null,
        cpfDigits: cpf || null,
        birthMonth: birth?.month ?? null,
        birthDay: birth?.day ?? null,
        telefone,
    };
}
function lightPost(doc, kind) {
    const d = doc.data();
    const title = String(d.title ?? d.titulo ?? d.name ?? "").trim();
    const base = {
        id: doc.id,
        title: title || (kind === "evento" ? "Evento" : "Aviso"),
        createdAt: d.createdAt ?? null,
        startAt: d.startAt ?? null,
        commentsCount: typeof d.commentsCount === "number" ? d.commentsCount : 0,
        type: String(d.type ?? ""),
    };
    if (kind === "aviso") {
        base.coverPhotoUrl = pickAvisoCoverUrl(d) || null;
        base.textPreview = String(d.text ?? d.conteudo ?? d.body ?? "")
            .trim()
            .substring(0, 240);
    }
    return base;
}
function weekMdSet(now) {
    const out = new Set();
    for (let i = 0; i < 7; i++) {
        const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
        out.add(`${d.getMonth() + 1}-${d.getDate()}`);
    }
    return out;
}
function computeBirthdayBuckets(memberDocs) {
    const now = new Date();
    const todayKey = `${now.getMonth() + 1}-${now.getDate()}`;
    const weekKeys = weekMdSet(now);
    const month = now.getMonth() + 1;
    const hoje = [];
    const semana = [];
    const mes = [];
    for (const doc of memberDocs) {
        const d = doc.data();
        if (!memberIsActive(d))
            continue;
        const birth = parseBirthMd(d);
        if (!birth)
            continue;
        const key = `${birth.month}-${birth.day}`;
        const lite = lightMember(doc);
        if (key === todayKey) {
            hoje.push(lite);
        }
        else if (weekKeys.has(key)) {
            semana.push(lite);
        }
        if (birth.month === month) {
            mes.push(lite);
        }
    }
    const sortByMd = (a, b) => {
        const am = Number(a.birthMonth ?? 0) * 32 + Number(a.birthDay ?? 0);
        const bm = Number(b.birthMonth ?? 0) * 32 + Number(b.birthDay ?? 0);
        return am - bm;
    };
    hoje.sort(sortByMd);
    semana.sort(sortByMd);
    mes.sort(sortByMd);
    return {
        birthdaysToday: hoje.slice(0, 48),
        birthdaysWeek: [...hoje, ...semana].slice(0, 64),
        birthdaysMonth: mes.slice(0, 80),
    };
}
/** Aniversariantes: query indexada por `birthMonth` (V4) — evita scan de todos os membros. */
async function loadBirthdayMemberDocs(membrosCol) {
    const month = new Date().getMonth() + 1;
    try {
        const snap = await membrosCol.where("birthMonth", "==", month).limit(120).get();
        if (snap.size > 0)
            return snap.docs;
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: birthMonth query", { e });
    }
    return [];
}
function cpfsFromDepartment(data) {
    const out = [];
    const add = (v) => {
        const c = canonicalCpf(String(v ?? ""));
        if (c.length === 11 && !out.includes(c))
            out.push(c);
    };
    const raw = data.leaderCpfs ?? data.leader_cpfs ?? data.liderCpfs ?? data.lider_cpfs;
    if (Array.isArray(raw)) {
        for (const e of raw)
            add(e);
    }
    add(data.leaderCpf);
    add(data.leader_cpf);
    add(data.LIDER_CPF);
    add(data.viceLeaderCpf);
    add(data.vice_leader_cpf);
    return out;
}
function leaderUidsFromDepartment(data) {
    const out = [];
    const add = (v) => {
        const s = String(v ?? "").trim();
        if (s.length >= 8 && !out.includes(s))
            out.push(s);
    };
    const raw = data.leaderUids ?? data.leader_uids;
    if (Array.isArray(raw)) {
        for (const e of raw)
            add(e);
    }
    add(data.leaderUid);
    add(data.leader_uid);
    add(data.viceLeaderUid);
    return out;
}
function foldFuncaoKey(raw) {
    let s = raw.trim().toLowerCase();
    const pairs = {
        "ã": "a",
        "â": "a",
        "á": "a",
        "à": "a",
        "é": "e",
        "ê": "e",
        "í": "i",
        "ó": "o",
        "ô": "o",
        "õ": "o",
        "ú": "u",
        "ç": "c",
    };
    for (const [a, b] of Object.entries(pairs)) {
        s = s.split(a).join(b);
    }
    return s;
}
const DEFAULT_CORPO_ADMIN_ROLES = [
    "pastor",
    "pastora",
    "secretario",
    "secretaria",
    "tesoureiro",
    "tesoureira",
];
function configuredCorpoAdminRoles(churchData) {
    if (!churchData)
        return DEFAULT_CORPO_ADMIN_ROLES;
    let raw = churchData.corpoAdminRoles;
    if (!Array.isArray(raw) && churchData.config && typeof churchData.config === "object") {
        raw = churchData.config.corpoAdminRoles;
    }
    if (!Array.isArray(raw) || raw.length === 0)
        return DEFAULT_CORPO_ADMIN_ROLES;
    const out = [];
    for (const e of raw) {
        const s = foldFuncaoKey(String(e));
        if (s)
            out.push(s);
    }
    return out.length > 0 ? out : DEFAULT_CORPO_ADMIN_ROLES;
}
function isCorpoAdminRole(raw, configured) {
    const k = foldFuncaoKey(raw);
    if (!k)
        return false;
    for (const c of configured) {
        const cc = foldFuncaoKey(c);
        if (k === cc)
            return true;
        if (k.startsWith(cc) && cc.length >= 4)
            return true;
    }
    return false;
}
function memberCorpoRoles(data, configured) {
    const seen = new Set();
    const out = [];
    const tryAdd = (raw) => {
        const t = raw.trim();
        if (!t || !isCorpoAdminRole(t, configured))
            return;
        const k = foldFuncaoKey(t);
        if (seen.has(k))
            return;
        seen.add(k);
        out.push(k);
    };
    tryAdd(pickString(data, ["FUNCAO", "funcao", "CARGO", "role"]));
    const flist = data.FUNCOES ?? data.funcoes;
    if (Array.isArray(flist)) {
        for (const x of flist)
            tryAdd(String(x));
    }
    return out;
}
function corpoSortRank(roles) {
    if (roles.length === 0)
        return 0;
    let max = 0;
    for (const r of roles) {
        const k = foldFuncaoKey(r);
        let rank = 50;
        if (k.startsWith("pastor"))
            rank = 300;
        else if (k.startsWith("secretar"))
            rank = 200;
        else if (k.startsWith("tesour"))
            rank = 100;
        if (rank > max)
            max = rank;
    }
    return max;
}
function computeLeaders(deptDocs, membersByCpf, authUidToCpf) {
    const leaderToDepts = new Map();
    for (const d of deptDocs) {
        const data = d.data();
        const deptName = String(data.name ?? data.nome ?? d.id).trim();
        for (const cpf of cpfsFromDepartment(data)) {
            const list = leaderToDepts.get(cpf) ?? [];
            list.push(deptName);
            leaderToDepts.set(cpf, list);
        }
        for (const uid of leaderUidsFromDepartment(data)) {
            const cpf = authUidToCpf.get(uid);
            if (!cpf)
                continue;
            const list = leaderToDepts.get(cpf) ?? [];
            list.push(deptName);
            leaderToDepts.set(cpf, list);
        }
    }
    const out = [];
    for (const [cpf, depts] of leaderToDepts.entries()) {
        const mem = membersByCpf.get(cpf);
        if (!mem)
            continue;
        const lite = lightMember(mem);
        lite.deptNames = depts;
        out.push(lite);
    }
    out.sort((a, b) => String(a.displayName ?? "")
        .toLowerCase()
        .localeCompare(String(b.displayName ?? "").toLowerCase()));
    return out.slice(0, 48);
}
function computeCorpoAdmin(memberDocs, configuredRoles) {
    const out = [];
    for (const doc of memberDocs) {
        const d = doc.data();
        if (!memberIsActive(d))
            continue;
        const roles = memberCorpoRoles(d, configuredRoles);
        if (roles.length === 0)
            continue;
        const lite = lightMember(doc);
        lite.corpoRoles = roles;
        out.push(lite);
    }
    out.sort((a, b) => {
        const ra = corpoSortRank(a.corpoRoles || []);
        const rb = corpoSortRank(b.corpoRoles || []);
        if (ra !== rb)
            return rb - ra;
        return String(a.displayName ?? "")
            .toLowerCase()
            .localeCompare(String(b.displayName ?? "").toLowerCase());
    });
    return out.slice(0, 36);
}
/**
 * Resumo leve do painel + blocos do início (aniversariantes, líderes, corpo, avisos).
 * Grava em `igrejas/{tenantId}/_panel_cache/dashboard_summary`.
 */
async function recomputePanelDashboardSummary(tenantId) {
    const db = admin.firestore();
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(String(tenantId || "").trim());
    const tid = canonical || String(tenantId || "").trim();
    if (!tid)
        return;
    const clusterIds = clusterDocIdsForPanel(tid);
    const scanIds = clusterIds.length > 0 ? clusterIds : [tid];
    const churchRef = db.collection("igrejas").doc(tid);
    const cacheCol = churchRef.collection("_panel_cache");
    const lockRef = cacheCol.doc("_dashboard_recompute_lock");
    const summaryRef = cacheCol.doc("dashboard_summary");
    const nowMs = Date.now();
    const lockSnap = await lockRef.get();
    if (lockSnap.exists) {
        const last = lockSnap.data()?.lastRun;
        if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_INTERVAL_MS) {
            return;
        }
    }
    await lockRef.set({ lastRun: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    const richestChurch = await richestChurchData(db, scanIds);
    const corpoRolesConfigured = configuredCorpoAdminRoles(richestChurch);
    const [pendingMembers, newVisitors, openPrayers, avisosDocs, eventosDocs, eventosProximosDocs, membrosMerged, deptMerged, birthdayMonthDocs,] = await Promise.all([
        sumCountsAcrossCluster(db, scanIds, (ref) => safeCount(ref.collection("membros").where("status", "==", "pendente"))),
        sumCountsAcrossCluster(db, scanIds, (ref) => safeCount(ref.collection("visitantes").where("status", "==", "Novo"))),
        sumCountsAcrossCluster(db, scanIds, (ref) => safeCount(ref.collection("pedidosOracao").where("respondida", "==", false))),
        mergeRecentPosts(db, scanIds, "avisos", "createdAt", RECENT_AVISOS),
        mergeRecentPosts(db, scanIds, "eventos", "startAt", RECENT_EVENTOS),
        mergeUpcomingEventDocs(db, scanIds),
        mergeMemberDocs(db, scanIds),
        mergeDepartmentDocs(db, scanIds),
        loadBirthdayMemberDocsCluster(db, scanIds),
    ]);
    const membersTotal = membrosMerged.length;
    const membersByCpf = new Map();
    const authUidToCpf = new Map();
    for (const doc of membrosMerged) {
        const d = doc.data();
        let cpf = canonicalCpf(pickString(d, ["CPF", "cpf"]));
        if (cpf.length !== 11) {
            const idDigits = normCpf(doc.id);
            if (idDigits.length >= 9 && idDigits.length <= 11) {
                cpf = canonicalCpf(idDigits);
            }
        }
        if (cpf.length === 11) {
            membersByCpf.set(cpf, doc);
            const uid = pickString(d, ["authUid", "firebaseUid", "uid", "userId"]);
            if (uid)
                authUidToCpf.set(uid, cpf);
        }
    }
    const birthdaySource = birthdayMonthDocs.length > 0 ? birthdayMonthDocs : membrosMerged;
    const birthdayBuckets = computeBirthdayBuckets(birthdaySource);
    const homeLeaders = computeLeaders(deptMerged, membersByCpf, authUidToCpf);
    const homeCorpoAdmin = computeCorpoAdmin(membrosMerged, corpoRolesConfigured);
    const nowMsEvt = Date.now();
    const upcomingDocs = eventosProximosDocs.filter((d) => {
        const st = d.data().startAt;
        if (st instanceof admin.firestore.Timestamp) {
            return st.toMillis() >= nowMsEvt - 86400000;
        }
        return true;
    }).slice(0, 12);
    const summaryPayload = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        schemaVersion: 2,
        pendingMembersCount: pendingMembers,
        newVisitorsCount: newVisitors,
        openPrayerRequestsCount: openPrayers,
        membersTotalCount: membersTotal,
        recentAvisos: avisosDocs.map((d) => lightPost(d, "aviso")),
        recentEventos: eventosDocs.map((d) => lightPost(d, "evento")),
        upcomingEventos: upcomingDocs.map((d) => lightPost(d, "evento")),
        ...birthdayBuckets,
        homeLeaders,
        homeCorpoAdmin,
    };
    await summaryRef.set(summaryPayload, { merge: false });
    try {
        await (0, churchRootCountersMirror_1.mirrorDashboardCacheAlias)(cacheCol, summaryPayload);
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: alias dashboard", { tenantId: tid, e });
    }
    const activeMembersCount = membrosMerged.filter((d) => memberIsActive(d.data())).length;
    let saldoAtual = 0;
    try {
        const finSnap = await cacheCol.doc("finance_summary").get();
        const fin = finSnap.data();
        saldoAtual = Number(fin?.saldoAtual ?? fin?.saldo_atual ?? 0);
    }
    catch (_) { }
    const demographics = computeMemberDemographics(membrosMerged);
    try {
        await (0, churchRootCountersMirror_1.writeDashboardCacheMain)(churchRef, {
            totalMembros: membersTotal,
            ativos: activeMembersCount,
            visitantes: newVisitors,
            saldo: saldoAtual,
            homens: demographics.homens,
            mulheres: demographics.mulheres,
            criancas: demographics.criancas,
            eventos: eventosDocs.length + upcomingDocs.length,
            avisos: avisosDocs.length,
        });
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: _dashboard_cache", { tenantId: tid, e });
    }
    try {
        await (0, churchRootCountersMirror_1.mirrorChurchCountersToRoot)(churchRef, {
            membersCount: membersTotal,
            membersTotalCount: membersTotal,
            activeMembersCount,
            eventsCount: eventosDocs.length + upcomingDocs.length,
            avisosCount: avisosDocs.length,
            departmentsCount: deptMerged.length,
            pendingMembersCount: pendingMembers,
            newVisitorsCount: newVisitors,
            openPrayerRequestsCount: openPrayers,
            birthdaysTodayCount: birthdayBuckets.birthdaysToday.length,
            upcomingEventsCount: upcomingDocs.length,
        });
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: mirror root counters", { tenantId: tid, e });
    }
    await cacheCol.doc("dashboard_current").set({
        totalMembers: membersTotal,
        birthdaysToday: birthdayBuckets.birthdaysToday.length,
        totalUpcomingEvents: upcomingDocs.length,
        pendingMembers,
        newVisitors,
        openPrayerRequests: openPrayers,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, membersDirectoryCache_1.recomputeMembersDirectoryFromDocs)(tid, membrosMerged, membersTotal);
    try {
        await (0, panelMediaPrefetch_1.recomputePanelMediaPrefetch)(tid);
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: media_prefetch", { tenantId: tid, e });
    }
    try {
        await (0, panelStatisticsCache_1.writePanelStatisticsCache)(tid, {
            membersTotalCount: membersTotal,
            activeMembersCount,
            pendingMembersCount: pendingMembers,
            newVisitorsCount: newVisitors,
            openPrayerRequestsCount: openPrayers,
            birthdaysTodayCount: birthdayBuckets.birthdaysToday.length,
            birthdaysWeekCount: birthdayBuckets.birthdaysWeek.length,
            birthdaysMonthCount: birthdayBuckets.birthdaysMonth.length,
            avisosCount: avisosDocs.length,
            eventsCount: eventosDocs.length,
            upcomingEventsCount: upcomingDocs.length,
            departmentsCount: deptMerged.length,
        });
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: statistics_summary", { tenantId: tid, e });
    }
    try {
        await (0, panelPublicSiteCache_1.recomputePanelPublicSiteCache)(tid);
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: public_site", { tenantId: tid, e });
    }
    functions.logger.info("panelDashboardCache: atualizado", {
        tenantId: tid,
        pendingMembers,
        membersTotal,
        leaders: homeLeaders.length,
        corpo: homeCorpoAdmin.length,
        birthdaysToday: birthdayBuckets.birthdaysToday.length,
    });
}
function scheduleRecompute(tenantId) {
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(tenantId);
    recomputePanelDashboardSummary(canonical || tenantId).catch((e) => {
        functions.logger.error("panelDashboardCache: recompute", { tenantId, e });
    });
}
const dashboardTrigger = (path) => functions
    .region("us-central1")
    .firestore.document(path)
    .onWrite((_, context) => {
    scheduleRecompute(context.params.tenantId);
    return null;
});
/** Mantém `birthMonth` / `birthDay` indexados para queries de aniversariantes. */
exports.onChurchMembroWriteSyncBirthIndex = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/membros/{memberId}")
    .onWrite(async (change) => {
    const after = change.after;
    if (!after.exists)
        return;
    const d = after.data();
    const birth = parseBirthMd(d);
    if (!birth)
        return;
    const patch = {};
    if (d.birthMonth !== birth.month)
        patch.birthMonth = birth.month;
    if (d.birthDay !== birth.day)
        patch.birthDay = birth.day;
    if (Object.keys(patch).length === 0)
        return;
    await after.ref.update(patch);
});
exports.onChurchMembroWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/membros/{docId}");
/** Atualiza só `recentAvisos` no cache (rápido) — evita recompute completo a cada aviso. */
async function patchRecentAvisosInDashboard(tenantId) {
    const tid = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(String(tenantId || "").trim());
    if (!tid)
        return;
    const db = admin.firestore();
    const clusterIds = clusterDocIdsForPanel(tid);
    const scanIds = clusterIds.length > 0 ? clusterIds : [tid];
    const summaryRef = db
        .collection("igrejas")
        .doc(tid)
        .collection("_panel_cache")
        .doc("dashboard_summary");
    const avisosDocs = await mergeRecentPosts(db, scanIds, "avisos", "createdAt", RECENT_AVISOS);
    const recentAvisos = avisosDocs.map((d) => lightPost(d, "aviso"));
    await summaryRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        recentAvisos,
    }, { merge: true });
}
exports.onChurchAvisoWritePanelDashboard = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{docId}")
    .onWrite(async (_, context) => {
    const tenantId = context.params.tenantId;
    try {
        await patchRecentAvisosInDashboard(tenantId);
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: patch avisos, fallback recompute", {
            tenantId,
            e,
        });
        scheduleRecompute(tenantId);
    }
    return null;
});
/** Atualiza só blocos de eventos no cache (rápido) — publicar evento no app nativo não dispara recompute pesado. */
async function patchRecentEventosInDashboard(tenantId) {
    const tid = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(String(tenantId || "").trim());
    if (!tid)
        return;
    const db = admin.firestore();
    const clusterIds = clusterDocIdsForPanel(tid);
    const scanIds = clusterIds.length > 0 ? clusterIds : [tid];
    const summaryRef = db
        .collection("igrejas")
        .doc(tid)
        .collection("_panel_cache")
        .doc("dashboard_summary");
    const [eventosDocs, eventosProximosDocs] = await Promise.all([
        mergeRecentPosts(db, scanIds, "eventos", "startAt", RECENT_EVENTOS),
        mergeUpcomingEventDocs(db, scanIds),
    ]);
    const recentEventos = eventosDocs.map((d) => lightPost(d, "evento"));
    const nowMsEvt = Date.now();
    const upcomingEventos = eventosProximosDocs
        .filter((d) => {
        const st = d.data().startAt;
        if (st instanceof admin.firestore.Timestamp) {
            return st.toMillis() >= nowMsEvt - 86400000;
        }
        return true;
    })
        .slice(0, 12)
        .map((d) => lightPost(d, "evento"));
    await summaryRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        recentEventos,
        upcomingEventos,
    }, { merge: true });
}
exports.onChurchNoticiaWritePanelDashboard = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{docId}")
    .onWrite(async (_, context) => {
    const tenantId = context.params.tenantId;
    try {
        await patchRecentEventosInDashboard(tenantId);
    }
    catch (e) {
        functions.logger.warn("panelDashboardCache: patch eventos, fallback recompute", {
            tenantId,
            e,
        });
        scheduleRecompute(tenantId);
    }
    return null;
});
exports.onChurchDepartamentoWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/departamentos/{docId}");
exports.onChurchVisitanteWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/visitantes/{docId}");
exports.onChurchPedidoOracaoWritePanelDashboard = dashboardTrigger("igrejas/{tenantId}/pedidosOracao/{docId}");
/** Leitura rápida do painel (1 round-trip). Recalcula se o cache estiver ausente ou velho. */
exports.getChurchPanelSnapshot = functions
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
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(tenantId);
    const db = admin.firestore();
    const summaryRef = db
        .collection("igrejas")
        .doc(canonical)
        .collection("_panel_cache")
        .doc("dashboard_summary");
    const snap = await summaryRef.get();
    const staleMs = 6 * 60 * 1000;
    let summary = snap.data();
    const updated = summary?.updatedAt;
    const isStale = !snap.exists ||
        !updated ||
        Date.now() - updated.toMillis() > staleMs;
    const mediaRef = db
        .collection("igrejas")
        .doc(canonical)
        .collection("_panel_cache")
        .doc("media_prefetch");
    if (isStale) {
        await recomputePanelDashboardSummary(canonical);
        summary = (await summaryRef.get()).data();
    }
    let mediaPrefetch = (await mediaRef.get()).data();
    const mpUpdated = mediaPrefetch?.updatedAt;
    const mpStale = !mediaPrefetch ||
        !mpUpdated ||
        Date.now() - mpUpdated.toMillis() > staleMs;
    if (mpStale) {
        try {
            await (0, panelMediaPrefetch_1.recomputePanelMediaPrefetch)(canonical);
            mediaPrefetch = (await mediaRef.get()).data();
        }
        catch (e) {
            functions.logger.warn("getChurchPanelSnapshot: media_prefetch", { tenantId: canonical, e });
        }
    }
    const statsRef = db
        .collection("igrejas")
        .doc(canonical)
        .collection("_panel_cache")
        .doc("statistics_summary");
    const publicSiteRef = db
        .collection("igrejas")
        .doc(canonical)
        .collection("_panel_cache")
        .doc("public_site");
    let statistics = (await statsRef.get()).data();
    let publicSite = (await publicSiteRef.get()).data();
    const statsUpdated = statistics?.updatedAt;
    const psUpdated = publicSite?.updatedAt;
    const statsStale = !statistics ||
        !statsUpdated ||
        Date.now() - statsUpdated.toMillis() > staleMs;
    const psStale = !publicSite || !psUpdated || Date.now() - psUpdated.toMillis() > staleMs;
    if (statsStale || psStale) {
        await recomputePanelDashboardSummary(canonical);
        summary = (await summaryRef.get()).data();
        statistics = (await statsRef.get()).data();
        publicSite = (await publicSiteRef.get()).data();
    }
    return {
        ok: true,
        tenantId: canonical,
        summary: summary ?? {},
        statistics: statistics ?? {},
        publicSite: publicSite ?? {},
        mediaPrefetch: mediaPrefetch ?? {},
    };
});
/** Pré-aquece caches do painel (mobile: 1 chamada em vez de dezenas de queries). */
exports.warmChurchTenantCaches = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (data || {});
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(body.tenantId || ""));
    if (!tenantId) {
        throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const canonical = (0, churchClusterAnchors_1.resolveAnchoredCanonicalTenantId)(tenantId);
    await recomputePanelDashboardSummary(canonical);
    return { ok: true, tenantId: canonical, warmed: true };
});
/** Mantém `_panel_cache` fresco para apps nativos (leitura de 1 documento). */
exports.scheduledRefreshPanelCaches = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .pubsub.schedule("every 20 minutes")
    .onRun(async () => {
    const snap = await admin.firestore().collection("igrejas").select().get();
    let n = 0;
    for (const doc of snap.docs) {
        try {
            const cacheRef = doc.ref.collection("_panel_cache").doc("dashboard_summary");
            const cache = await cacheRef.get();
            const updated = cache.data()?.updatedAt;
            const staleMs = 18 * 60 * 1000;
            const isStale = !cache.exists ||
                !updated ||
                Date.now() - updated.toMillis() > staleMs;
            if (isStale) {
                await recomputePanelDashboardSummary(doc.id);
                n++;
            }
        }
        catch (e) {
            functions.logger.warn("scheduledRefreshPanelCaches", { tenantId: doc.id, e });
        }
    }
    if (n > 0) {
        functions.logger.info(`scheduledRefreshPanelCaches: ${n} igreja(s)`);
    }
    return null;
});
//# sourceMappingURL=panelDashboardCache.js.map