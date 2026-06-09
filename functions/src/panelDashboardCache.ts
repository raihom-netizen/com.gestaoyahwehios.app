import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { recomputeMembersDirectoryFromDocs } from "./membersDirectoryCache";
import { recomputePanelMediaPrefetch } from "./panelMediaPrefetch";
import { resolveTenantIdForCallable } from "./tenantCallableResolve";
import {
  addAnchoredCluster,
  resolveAnchoredCanonicalTenantId,
} from "./churchClusterAnchors";
import {
  mirrorChurchCountersToRoot,
  mirrorDashboardCacheAlias,
} from "./churchRootCountersMirror";
import { writePanelStatisticsCache } from "./panelStatisticsCache";
import { recomputePanelPublicSiteCache } from "./panelPublicSiteCache";

const RECOMPUTE_MIN_INTERVAL_MS = 45_000;
const RECENT_AVISOS = 8;
const RECENT_EVENTOS = 8;
const MEMBERS_SCAN_LIMIT = 800;
const DEPT_SCAN_LIMIT = 120;

function clusterDocIdsForPanel(seed: string): string[] {
  const out = new Set<string>();
  const t = String(seed || "").trim();
  if (!t) return [];
  out.add(t);
  addAnchoredCluster(t, out);
  return Array.from(out).filter(Boolean);
}

function memberDedupeKey(
  doc: admin.firestore.QueryDocumentSnapshot,
): string {
  const d = doc.data();
  let cpf = canonicalCpf(pickString(d, ["CPF", "cpf"]));
  if (cpf.length !== 11) {
    const idDigits = normCpf(doc.id);
    if (idDigits.length >= 9 && idDigits.length <= 11) {
      cpf = canonicalCpf(idDigits);
    }
  }
  if (cpf.length === 11) return `cpf:${cpf}`;
  return `id:${doc.ref.path}`;
}

async function mergeMemberDocs(
  db: admin.firestore.Firestore,
  clusterIds: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const seen = new Set<string>();
  const merged: admin.firestore.QueryDocumentSnapshot[] = [];
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
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(doc);
      }
    } catch (e) {
      functions.logger.warn("panelDashboardCache: merge membros", { id, e });
    }
  }
  return merged;
}

async function mergeDepartmentDocs(
  db: admin.firestore.Firestore,
  clusterIds: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const seen = new Set<string>();
  const merged: admin.firestore.QueryDocumentSnapshot[] = [];
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
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(doc);
      }
    } catch (e) {
      functions.logger.warn("panelDashboardCache: merge departamentos", { id, e });
    }
  }
  return merged;
}

async function mergeRecentPosts(
  db: admin.firestore.Firestore,
  clusterIds: string[],
  collection: "avisos" | "eventos",
  orderField: "createdAt" | "startAt",
  limit: number,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const byId = new Map<string, admin.firestore.QueryDocumentSnapshot>();
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
        if (!byId.has(doc.id)) byId.set(doc.id, doc);
      }
    } catch (e) {
      functions.logger.warn(`panelDashboardCache: merge ${collection}`, { id, e });
    }
  }
  const docs = Array.from(byId.values());
  docs.sort((a, b) => {
    const av = a.data()[orderField];
    const bv = b.data()[orderField];
    const am =
      av instanceof admin.firestore.Timestamp ? av.toMillis() : 0;
    const bm =
      bv instanceof admin.firestore.Timestamp ? bv.toMillis() : 0;
    return bm - am;
  });
  return docs.slice(0, limit);
}

async function mergeUpcomingEventDocs(
  db: admin.firestore.Firestore,
  clusterIds: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const byId = new Map<string, admin.firestore.QueryDocumentSnapshot>();
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
        if (!byId.has(doc.id)) byId.set(doc.id, doc);
      }
    } catch (e) {
      functions.logger.warn("panelDashboardCache: merge upcoming eventos", { id, e });
    }
  }
  const docs = Array.from(byId.values());
  docs.sort((a, b) => {
    const av = a.data().startAt;
    const bv = b.data().startAt;
    const am =
      av instanceof admin.firestore.Timestamp ? av.toMillis() : 0;
    const bm =
      bv instanceof admin.firestore.Timestamp ? bv.toMillis() : 0;
    return am - bm;
  });
  return docs.slice(0, 24);
}

async function loadBirthdayMemberDocsCluster(
  db: admin.firestore.Firestore,
  clusterIds: string[],
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const seen = new Set<string>();
  const merged: admin.firestore.QueryDocumentSnapshot[] = [];
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
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(doc);
      }
    } catch (e) {
      functions.logger.warn("panelDashboardCache: birthMonth cluster", { id, e });
    }
  }
  return merged;
}

async function richestChurchData(
  db: admin.firestore.Firestore,
  clusterIds: string[],
): Promise<Record<string, unknown> | undefined> {
  let best: Record<string, unknown> | undefined;
  let bestScore = -1;
  for (const id of clusterIds) {
    try {
      const snap = await db.collection("igrejas").doc(id).get();
      if (!snap.exists) continue;
      const data = snap.data() as Record<string, unknown>;
      let score = Object.keys(data).length;
      const depts = data.departamentos ?? data.departments;
      if (Array.isArray(depts)) score += depts.length * 4;
      if (pickString(data, ["slug", "slugId", "alias"])) score += 20;
      if (pickString(data, ["name", "nome"])) score += 10;
      if (score > bestScore) {
        bestScore = score;
        best = data;
      }
    } catch (_) {}
  }
  return best;
}

async function safeCount(q: admin.firestore.Query): Promise<number> {
  try {
    const agg = await q.count().get();
    return agg.data().count;
  } catch (e) {
    functions.logger.warn("panelDashboardCache: count falhou", { e });
    return 0;
  }
}

async function sumCountsAcrossCluster(
  db: admin.firestore.Firestore,
  clusterIds: string[],
  counter: (churchRef: admin.firestore.DocumentReference) => Promise<number>,
): Promise<number> {
  let total = 0;
  for (const id of clusterIds) {
    try {
      total += await counter(db.collection("igrejas").doc(id));
    } catch (_) {}
  }
  return total;
}

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function pickPhotoUrl(data: Record<string, unknown>): string {
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

function pickAvisoCoverUrl(data: Record<string, unknown>): string {
  const direct = pickPhotoUrl(data);
  if (direct) return direct;
  const lists = [data.photoUrls, data.photos, data.images, data.fotos];
  for (const raw of lists) {
    if (!Array.isArray(raw)) continue;
    for (const e of raw) {
      if (typeof e === "string" && e.trim().startsWith("http")) return e.trim();
      if (e && typeof e === "object") {
        const m = e as Record<string, unknown>;
        const u = pickPhotoUrl(m);
        if (u) return u;
      }
    }
  }
  return "";
}

function normCpf(raw: unknown): string {
  const d = String(raw ?? "").replace(/\D/g, "");
  if (!d) return "";
  if (d.length > 11) return d.substring(d.length - 11);
  if (d.length < 11) return d.padStart(11, "0");
  return d;
}

function canonicalCpf(digits: string): string {
  const d = normCpf(digits);
  if (!d) return "";
  if (d.length > 11) return d.substring(d.length - 11);
  if (d.length < 11) return d.padStart(11, "0");
  return d;
}

function memberIsActive(data: Record<string, unknown>): boolean {
  const st = pickString(data, ["STATUS", "status"]).toLowerCase();
  return !st || st === "ativo";
}

function parseBirthMd(
  data: Record<string, unknown>,
): { month: number; day: number } | null {
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

function lightMember(
  doc: admin.firestore.QueryDocumentSnapshot,
): Record<string, unknown> {
  const d = doc.data();
  const birth = parseBirthMd(d);
  const revRaw = d.fotoUrlCacheRevision ?? d.photoCacheRevision;
  const fotoUrlCacheRevision =
    typeof revRaw === "number" && Number.isFinite(revRaw)
      ? Math.floor(revRaw)
      : 0;
  const cpf = canonicalCpf(
    pickString(d, ["CPF", "cpf"]) || normCpf(doc.id),
  );
  const telefone =
    pickString(d, [
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
    displayName:
      pickString(d, ["NOME_COMPLETO", "nome", "name"]) || "Membro",
    photoUrl: pickPhotoUrl(d) || null,
    fotoUrlCacheRevision,
    authUid: pickString(d, ["authUid", "firebaseUid", "uid", "userId"]) || null,
    cpfDigits: cpf || null,
    birthMonth: birth?.month ?? null,
    birthDay: birth?.day ?? null,
    telefone,
  };
}

function lightPost(
  doc: admin.firestore.QueryDocumentSnapshot,
  kind: "aviso" | "evento",
): Record<string, unknown> {
  const d = doc.data();
  const title = String(d.title ?? d.titulo ?? d.name ?? "").trim();
  const base: Record<string, unknown> = {
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

function weekMdSet(now: Date): Set<string> {
  const out = new Set<string>();
  for (let i = 0; i < 7; i++) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
    out.add(`${d.getMonth() + 1}-${d.getDate()}`);
  }
  return out;
}

function computeBirthdayBuckets(
  memberDocs: admin.firestore.QueryDocumentSnapshot[],
) {
  const now = new Date();
  const todayKey = `${now.getMonth() + 1}-${now.getDate()}`;
  const weekKeys = weekMdSet(now);
  const month = now.getMonth() + 1;

  const hoje: Record<string, unknown>[] = [];
  const semana: Record<string, unknown>[] = [];
  const mes: Record<string, unknown>[] = [];

  for (const doc of memberDocs) {
    const d = doc.data();
    if (!memberIsActive(d)) continue;
    const birth = parseBirthMd(d);
    if (!birth) continue;
    const key = `${birth.month}-${birth.day}`;
    const lite = lightMember(doc);
    if (key === todayKey) {
      hoje.push(lite);
    } else if (weekKeys.has(key)) {
      semana.push(lite);
    }
    if (birth.month === month) {
      mes.push(lite);
    }
  }

  const sortByMd = (a: Record<string, unknown>, b: Record<string, unknown>) => {
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
async function loadBirthdayMemberDocs(
  membrosCol: admin.firestore.CollectionReference,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const month = new Date().getMonth() + 1;
  try {
    const snap = await membrosCol.where("birthMonth", "==", month).limit(120).get();
    if (snap.size > 0) return snap.docs;
  } catch (e) {
    functions.logger.warn("panelDashboardCache: birthMonth query", { e });
  }
  return [];
}

function cpfsFromDepartment(data: Record<string, unknown>): string[] {
  const out: string[] = [];
  const add = (v: unknown) => {
    const c = canonicalCpf(String(v ?? ""));
    if (c.length === 11 && !out.includes(c)) out.push(c);
  };
  const raw =
    data.leaderCpfs ?? data.leader_cpfs ?? data.liderCpfs ?? data.lider_cpfs;
  if (Array.isArray(raw)) {
    for (const e of raw) add(e);
  }
  add(data.leaderCpf);
  add(data.leader_cpf);
  add(data.LIDER_CPF);
  add(data.viceLeaderCpf);
  add(data.vice_leader_cpf);
  return out;
}

function leaderUidsFromDepartment(data: Record<string, unknown>): string[] {
  const out: string[] = [];
  const add = (v: unknown) => {
    const s = String(v ?? "").trim();
    if (s.length >= 8 && !out.includes(s)) out.push(s);
  };
  const raw = data.leaderUids ?? data.leader_uids;
  if (Array.isArray(raw)) {
    for (const e of raw) add(e);
  }
  add(data.leaderUid);
  add(data.leader_uid);
  add(data.viceLeaderUid);
  return out;
}

function foldFuncaoKey(raw: string): string {
  let s = raw.trim().toLowerCase();
  const pairs: Record<string, string> = {
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

function configuredCorpoAdminRoles(
  churchData: Record<string, unknown> | undefined,
): string[] {
  if (!churchData) return DEFAULT_CORPO_ADMIN_ROLES;
  let raw = churchData.corpoAdminRoles;
  if (!Array.isArray(raw) && churchData.config && typeof churchData.config === "object") {
    raw = (churchData.config as Record<string, unknown>).corpoAdminRoles;
  }
  if (!Array.isArray(raw) || raw.length === 0) return DEFAULT_CORPO_ADMIN_ROLES;
  const out: string[] = [];
  for (const e of raw) {
    const s = foldFuncaoKey(String(e));
    if (s) out.push(s);
  }
  return out.length > 0 ? out : DEFAULT_CORPO_ADMIN_ROLES;
}

function isCorpoAdminRole(raw: string, configured: string[]): boolean {
  const k = foldFuncaoKey(raw);
  if (!k) return false;
  for (const c of configured) {
    const cc = foldFuncaoKey(c);
    if (k === cc) return true;
    if (k.startsWith(cc) && cc.length >= 4) return true;
  }
  return false;
}

function memberCorpoRoles(
  data: Record<string, unknown>,
  configured: string[],
): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  const tryAdd = (raw: string) => {
    const t = raw.trim();
    if (!t || !isCorpoAdminRole(t, configured)) return;
    const k = foldFuncaoKey(t);
    if (seen.has(k)) return;
    seen.add(k);
    out.push(k);
  };
  tryAdd(pickString(data, ["FUNCAO", "funcao", "CARGO", "role"]));
  const flist = data.FUNCOES ?? data.funcoes;
  if (Array.isArray(flist)) {
    for (const x of flist) tryAdd(String(x));
  }
  return out;
}

function corpoSortRank(roles: string[]): number {
  if (roles.length === 0) return 0;
  let max = 0;
  for (const r of roles) {
    const k = foldFuncaoKey(r);
    let rank = 50;
    if (k.startsWith("pastor")) rank = 300;
    else if (k.startsWith("secretar")) rank = 200;
    else if (k.startsWith("tesour")) rank = 100;
    if (rank > max) max = rank;
  }
  return max;
}

function computeLeaders(
  deptDocs: admin.firestore.QueryDocumentSnapshot[],
  membersByCpf: Map<string, admin.firestore.QueryDocumentSnapshot>,
  authUidToCpf: Map<string, string>,
): Record<string, unknown>[] {
  const leaderToDepts = new Map<string, string[]>();
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
      if (!cpf) continue;
      const list = leaderToDepts.get(cpf) ?? [];
      list.push(deptName);
      leaderToDepts.set(cpf, list);
    }
  }

  const out: Record<string, unknown>[] = [];
  for (const [cpf, depts] of leaderToDepts.entries()) {
    const mem = membersByCpf.get(cpf);
    if (!mem) continue;
    const lite = lightMember(mem);
    lite.deptNames = depts;
    out.push(lite);
  }
  out.sort((a, b) =>
    String(a.displayName ?? "")
      .toLowerCase()
      .localeCompare(String(b.displayName ?? "").toLowerCase()),
  );
  return out.slice(0, 48);
}

function computeCorpoAdmin(
  memberDocs: admin.firestore.QueryDocumentSnapshot[],
  configuredRoles: string[],
): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  for (const doc of memberDocs) {
    const d = doc.data();
    if (!memberIsActive(d)) continue;
    const roles = memberCorpoRoles(d, configuredRoles);
    if (roles.length === 0) continue;
    const lite = lightMember(doc);
    lite.corpoRoles = roles;
    out.push(lite);
  }
  out.sort((a, b) => {
    const ra = corpoSortRank((a.corpoRoles as string[]) || []);
    const rb = corpoSortRank((b.corpoRoles as string[]) || []);
    if (ra !== rb) return rb - ra;
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
export async function recomputePanelDashboardSummary(tenantId: string): Promise<void> {
  const db = admin.firestore();
  const canonical = resolveAnchoredCanonicalTenantId(String(tenantId || "").trim());
  const tid = canonical || String(tenantId || "").trim();
  if (!tid) return;

  const clusterIds = clusterDocIdsForPanel(tid);
  const scanIds = clusterIds.length > 0 ? clusterIds : [tid];

  const churchRef = db.collection("igrejas").doc(tid);
  const cacheCol = churchRef.collection("_panel_cache");
  const lockRef = cacheCol.doc("_dashboard_recompute_lock");
  const summaryRef = cacheCol.doc("dashboard_summary");

  const nowMs = Date.now();
  const lockSnap = await lockRef.get();
  if (lockSnap.exists) {
    const last = lockSnap.data()?.lastRun as admin.firestore.Timestamp | undefined;
    if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_INTERVAL_MS) {
      return;
    }
  }
  await lockRef.set(
    { lastRun: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  const richestChurch = await richestChurchData(db, scanIds);
  const corpoRolesConfigured = configuredCorpoAdminRoles(richestChurch);

  const [
    pendingMembers,
    newVisitors,
    openPrayers,
    avisosDocs,
    eventosDocs,
    eventosProximosDocs,
    membrosMerged,
    deptMerged,
    birthdayMonthDocs,
  ] = await Promise.all([
    sumCountsAcrossCluster(db, scanIds, (ref) =>
      safeCount(ref.collection("membros").where("status", "==", "pendente")),
    ),
    sumCountsAcrossCluster(db, scanIds, (ref) =>
      safeCount(ref.collection("visitantes").where("status", "==", "Novo")),
    ),
    sumCountsAcrossCluster(db, scanIds, (ref) =>
      safeCount(ref.collection("pedidosOracao").where("respondida", "==", false)),
    ),
    mergeRecentPosts(db, scanIds, "avisos", "createdAt", RECENT_AVISOS),
    mergeRecentPosts(db, scanIds, "eventos", "startAt", RECENT_EVENTOS),
    mergeUpcomingEventDocs(db, scanIds),
    mergeMemberDocs(db, scanIds),
    mergeDepartmentDocs(db, scanIds),
    loadBirthdayMemberDocsCluster(db, scanIds),
  ]);

  const membersTotal = membrosMerged.length;

  const membersByCpf = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  const authUidToCpf = new Map<string, string>();
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
      if (uid) authUidToCpf.set(uid, cpf);
    }
  }

  const birthdaySource =
    birthdayMonthDocs.length > 0 ? birthdayMonthDocs : membrosMerged;
  const birthdayBuckets = computeBirthdayBuckets(birthdaySource);
  const homeLeaders = computeLeaders(deptMerged, membersByCpf, authUidToCpf);
  const homeCorpoAdmin = computeCorpoAdmin(membrosMerged, corpoRolesConfigured);

  const nowMsEvt = Date.now();
  const upcomingDocs = eventosProximosDocs.filter((d) => {
    const st = d.data().startAt;
    if (st instanceof admin.firestore.Timestamp) {
      return st.toMillis() >= nowMsEvt - 86_400_000;
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
    await mirrorDashboardCacheAlias(cacheCol, summaryPayload);
  } catch (e) {
    functions.logger.warn("panelDashboardCache: alias dashboard", { tenantId: tid, e });
  }

  const activeMembersCount = membrosMerged.filter((d) =>
    memberIsActive(d.data() as Record<string, unknown>),
  ).length;

  try {
    await mirrorChurchCountersToRoot(churchRef, {
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
  } catch (e) {
    functions.logger.warn("panelDashboardCache: mirror root counters", { tenantId: tid, e });
  }

  await cacheCol.doc("dashboard_current").set(
    {
      totalMembers: membersTotal,
      birthdaysToday: birthdayBuckets.birthdaysToday.length,
      totalUpcomingEvents: upcomingDocs.length,
      pendingMembers,
      newVisitors,
      openPrayerRequests: openPrayers,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await recomputeMembersDirectoryFromDocs(tid, membrosMerged, membersTotal);

  try {
    await recomputePanelMediaPrefetch(tid);
  } catch (e) {
    functions.logger.warn("panelDashboardCache: media_prefetch", { tenantId: tid, e });
  }

  try {
    await writePanelStatisticsCache(tid, {
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
  } catch (e) {
    functions.logger.warn("panelDashboardCache: statistics_summary", { tenantId: tid, e });
  }

  try {
    await recomputePanelPublicSiteCache(tid);
  } catch (e) {
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

function scheduleRecompute(tenantId: string) {
  const canonical = resolveAnchoredCanonicalTenantId(tenantId);
  recomputePanelDashboardSummary(canonical || tenantId).catch((e) => {
    functions.logger.error("panelDashboardCache: recompute", { tenantId, e });
  });
}

const dashboardTrigger = (path: string) =>
  functions
    .region("us-central1")
    .firestore.document(path)
    .onWrite((_, context) => {
      scheduleRecompute(context.params.tenantId as string);
      return null;
    });

/** Mantém `birthMonth` / `birthDay` indexados para queries de aniversariantes. */
export const onChurchMembroWriteSyncBirthIndex = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/membros/{memberId}")
  .onWrite(async (change) => {
    const after = change.after;
    if (!after.exists) return;
    const d = after.data() as Record<string, unknown>;
    const birth = parseBirthMd(d);
    if (!birth) return;
    const patch: Record<string, number> = {};
    if (d.birthMonth !== birth.month) patch.birthMonth = birth.month;
    if (d.birthDay !== birth.day) patch.birthDay = birth.day;
    if (Object.keys(patch).length === 0) return;
    await after.ref.update(patch);
  });

export const onChurchMembroWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/membros/{docId}",
);
/** Atualiza só `recentAvisos` no cache (rápido) — evita recompute completo a cada aviso. */
async function patchRecentAvisosInDashboard(tenantId: string): Promise<void> {
  const tid = resolveAnchoredCanonicalTenantId(String(tenantId || "").trim());
  if (!tid) return;
  const db = admin.firestore();
  const clusterIds = clusterDocIdsForPanel(tid);
  const scanIds = clusterIds.length > 0 ? clusterIds : [tid];
  const summaryRef = db
    .collection("igrejas")
    .doc(tid)
    .collection("_panel_cache")
    .doc("dashboard_summary");

  const avisosDocs = await mergeRecentPosts(
    db,
    scanIds,
    "avisos",
    "createdAt",
    RECENT_AVISOS,
  );
  const recentAvisos = avisosDocs.map((d) => lightPost(d, "aviso"));

  await summaryRef.set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      recentAvisos,
    },
    { merge: true },
  );
}

export const onChurchAvisoWritePanelDashboard = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{docId}")
  .onWrite(async (_, context) => {
    const tenantId = context.params.tenantId as string;
    try {
      await patchRecentAvisosInDashboard(tenantId);
    } catch (e) {
      functions.logger.warn("panelDashboardCache: patch avisos, fallback recompute", {
        tenantId,
        e,
      });
      scheduleRecompute(tenantId);
    }
    return null;
  });
/** Atualiza só blocos de eventos no cache (rápido) — publicar evento no app nativo não dispara recompute pesado. */
async function patchRecentEventosInDashboard(tenantId: string): Promise<void> {
  const tid = resolveAnchoredCanonicalTenantId(String(tenantId || "").trim());
  if (!tid) return;
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
        return st.toMillis() >= nowMsEvt - 86_400_000;
      }
      return true;
    })
    .slice(0, 12)
    .map((d) => lightPost(d, "evento"));

  await summaryRef.set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      recentEventos,
      upcomingEventos,
    },
    { merge: true },
  );
}

export const onChurchNoticiaWritePanelDashboard = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{docId}")
  .onWrite(async (_, context) => {
    const tenantId = context.params.tenantId as string;
    try {
      await patchRecentEventosInDashboard(tenantId);
    } catch (e) {
      functions.logger.warn("panelDashboardCache: patch eventos, fallback recompute", {
        tenantId,
        e,
      });
      scheduleRecompute(tenantId);
    }
    return null;
  });
export const onChurchDepartamentoWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/departamentos/{docId}",
);
export const onChurchVisitanteWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/visitantes/{docId}",
);
export const onChurchPedidoOracaoWritePanelDashboard = dashboardTrigger(
  "igrejas/{tenantId}/pedidosOracao/{docId}",
);

/** Leitura rápida do painel (1 round-trip). Recalcula se o cache estiver ausente ou velho. */
export const getChurchPanelSnapshot = functions
  .region("us-central1")
  .https.onCall(async (request, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {}) as Record<string, unknown>;
    const tenantId = await resolveTenantIdForCallable(
      { uid: context.auth.uid, token: context.auth.token as Record<string, unknown> },
      String(body.tenantId || ""),
    );
    if (!tenantId) {
      throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const canonical = resolveAnchoredCanonicalTenantId(tenantId);

    const db = admin.firestore();
    const summaryRef = db
      .collection("igrejas")
      .doc(canonical)
      .collection("_panel_cache")
      .doc("dashboard_summary");

    const snap = await summaryRef.get();
    const staleMs = 6 * 60 * 1000;
    let summary = snap.data();
    const updated = summary?.updatedAt as admin.firestore.Timestamp | undefined;
    const isStale =
      !snap.exists ||
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
    const mpUpdated = mediaPrefetch?.updatedAt as admin.firestore.Timestamp | undefined;
    const mpStale =
      !mediaPrefetch ||
      !mpUpdated ||
      Date.now() - mpUpdated.toMillis() > staleMs;
    if (mpStale) {
      try {
        await recomputePanelMediaPrefetch(canonical);
        mediaPrefetch = (await mediaRef.get()).data();
      } catch (e) {
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

    const statsUpdated = statistics?.updatedAt as admin.firestore.Timestamp | undefined;
    const psUpdated = publicSite?.updatedAt as admin.firestore.Timestamp | undefined;
    const statsStale =
      !statistics ||
      !statsUpdated ||
      Date.now() - statsUpdated.toMillis() > staleMs;
    const psStale =
      !publicSite || !psUpdated || Date.now() - psUpdated.toMillis() > staleMs;

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
export const warmChurchTenantCaches = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (data || {}) as Record<string, unknown>;
    const tenantId = await resolveTenantIdForCallable(
      { uid: context.auth.uid, token: context.auth.token as Record<string, unknown> },
      String(body.tenantId || ""),
    );
    if (!tenantId) {
      throw new functions.https.HttpsError("failed-precondition", "igrejaId ausente");
    }
    const canonical = resolveAnchoredCanonicalTenantId(tenantId);
    await recomputePanelDashboardSummary(canonical);
    return { ok: true, tenantId: canonical, warmed: true };
  });

/** Mantém `_panel_cache` fresco para apps nativos (leitura de 1 documento). */
export const scheduledRefreshPanelCaches = functions
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
        const updated = cache.data()?.updatedAt as admin.firestore.Timestamp | undefined;
        const staleMs = 18 * 60 * 1000;
        const isStale =
          !cache.exists ||
          !updated ||
          Date.now() - updated.toMillis() > staleMs;
        if (isStale) {
          await recomputePanelDashboardSummary(doc.id);
          n++;
        }
      } catch (e) {
        functions.logger.warn("scheduledRefreshPanelCaches", { tenantId: doc.id, e });
      }
    }
    if (n > 0) {
      functions.logger.info(`scheduledRefreshPanelCaches: ${n} igreja(s)`);
    }
    return null;
  });
