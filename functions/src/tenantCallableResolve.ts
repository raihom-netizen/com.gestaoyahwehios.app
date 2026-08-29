import * as functions from "firebase-functions/v1";
import { admin, fs } from "./adminDb";

/**
 * Operador global (master) — MESMA definição do `isMaster()` de
 * `firestore.rules`: e-mail na lista, CPF do master no doc `users/{uid}`, ou
 * `admins/{uid}` existente.
 *
 * Sem isto, `userCanAccessTenant` respondia `false` para o master em qualquer
 * igreja onde ele não fosse membro nem gestor — e `resolveTenantIdForCallable`
 * **descartava o `tenantId` enviado pelo painel** e caía no
 * `users/{uid}.igrejaId`. Resultado: o operador trocava de igreja no seletor,
 * o cabeçalho mudava, mas toda callable (diretório de membros, dashboard,
 * relatórios, PDFs) devolvia dados da igreja do perfil dele.
 */
const MASTER_EMAILS = new Set([
  "raihom@gmail.com",
  "isabellecardoso@gmail.com",
  "isabelle.cardoso@gmail.com",
]);
const MASTER_CPF = "94536368191";

export async function isMasterOperator(
  uid: string,
  email: string,
  token?: Record<string, unknown>,
): Promise<boolean> {
  const em = String(email || "").trim().toLowerCase();
  if (em && MASTER_EMAILS.has(em)) return true;

  // Claims do próprio token: não custa nenhuma leitura e cobre o caso de o
  // e-mail não vir no token (provedores que não o expõem).
  if (token) {
    if (token.platformMaster === true) return true;
    const claimEmail = String(token.email || "").trim().toLowerCase();
    if (claimEmail && MASTER_EMAILS.has(claimEmail)) return true;
    if (String(token.cpf || "").trim() === MASTER_CPF) return true;
  }

  const id = String(uid || "").trim();
  if (!id) return false;
  try {
    const adminDoc = await fs().collection("admins").doc(id).get();
    if (adminDoc.exists) return true;
  } catch (e) {
    functions.logger.warn("isMasterOperator: admins", { uid: id, e });
  }
  // O CPF do master pode estar só nos custom claims — em produção o
  // `users/{uid}` do operador não tem o campo.
  try {
    const tokenUser = await admin.auth().getUser(id);
    const claims = (tokenUser.customClaims || {}) as Record<string, unknown>;
    if (claims.platformMaster === true) return true;
    if (String(claims.cpf || "").trim() === MASTER_CPF) return true;
  } catch (e) {
    functions.logger.warn("isMasterOperator: claims", { uid: id, e });
  }
  try {
    const userSnap = await fs().collection("users").doc(id).get();
    const d = (userSnap.data() || {}) as Record<string, unknown>;
    for (const k of ["cpf", "CPF", "linkedCpf"]) {
      if (String(d[k] || "").trim() === MASTER_CPF) return true;
    }
  } catch (e) {
    functions.logger.warn("isMasterOperator: users", { uid: id, e });
  }
  return false;
}

/** Resolve igreja do utilizador (claims → body → users → membros). Mobile costuma falhar só com claims. */
export async function resolveTenantIdForCallable(
  auth: { uid: string; token?: Record<string, unknown> },
  dataTenantId?: string,
): Promise<string> {
  const uid = auth.uid;
  const email = String((auth.token?.email as string) || "")
    .trim()
    .toLowerCase();

  const fromBody = String(dataTenantId || "").trim();
  if (fromBody && (await userCanAccessTenant(uid, email, fromBody, auth.token))) {
    const ig = await fs().collection("igrejas").doc(fromBody).get();
    if (ig.exists) return fromBody;
  }

  try {
    const tokenUser = await admin.auth().getUser(uid);
    const claims = (tokenUser.customClaims || {}) as Record<string, unknown>;
    const fromClaims = String(claims.igrejaId || claims.tenantId || "").trim();
    if (fromClaims) {
      const ig = await fs().collection("igrejas").doc(fromClaims).get();
      if (ig.exists) return fromClaims;
    }
  } catch (e) {
    functions.logger.warn("resolveTenantIdForCallable: claims", { uid, e });
  }

  const userSnap = await fs().collection("users").doc(uid).get();
  if (userSnap.exists) {
    const d = userSnap.data() || {};
    const tid = String(d.igrejaId || d.tenantId || "").trim();
    if (tid) {
      const ig = await fs().collection("igrejas").doc(tid).get();
      if (ig.exists) return tid;
    }
  }

  try {
    const membrosCg = await fs()
      .collectionGroup("membros")
      .where("authUid", "==", uid)
      .limit(8)
      .get();
    for (const doc of membrosCg.docs) {
      const parts = doc.ref.path.split("/");
      if (parts[0] !== "igrejas" || parts[2] !== "membros") continue;
      const tid = parts[1];
      const ig = await fs().collection("igrejas").doc(tid).get();
      if (ig.exists) return tid;
    }
  } catch (e) {
    // Índice CG em falta não pode derrubar o resolve (usa fallback por e-mail abaixo).
    functions.logger.warn("resolveTenantIdForCallable: membros CG", { uid, e });
  }

  if (email) {
    for (const field of ["email", "gestorEmail", "emailGestor"]) {
      const q = await fs()
        .collection("igrejas")
        .where(field, "==", email)
        .limit(1)
        .get();
      if (!q.empty) return q.docs[0].id;
    }
  }

  return "";
}

export async function userCanAccessTenant(
  uid: string,
  email: string,
  tenantId: string,
  token?: Record<string, unknown>,
): Promise<boolean> {
  const tid = String(tenantId || "").trim();
  if (!tid) return false;
  const ig = await fs().collection("igrejas").doc(tid).get();
  if (!ig.exists) return false;

  // O operador global abre qualquer igreja no painel — é o que o seletor
  // «Trocar de igreja» faz. Esta verificação vem primeiro porque ele
  // tipicamente NÃO é membro nem gestor da igreja visitada.
  if (await isMasterOperator(uid, email, token)) return true;

  const byUid = await fs()
    .collection("igrejas")
    .doc(tid)
    .collection("membros")
    .doc(uid)
    .get();
  if (byUid.exists) return true;

  const tenantUser = await fs()
    .collection("igrejas")
    .doc(tid)
    .collection("users")
    .doc(uid)
    .get();
  if (tenantUser.exists) return true;

  const rootUser = await fs().collection("users").doc(uid).get();
  if (rootUser.exists) {
    const d = rootUser.data() || {};
    if (String(d.igrejaId || d.tenantId || "").trim() === tid) return true;
  }

  try {
    const cg = await fs()
      .collectionGroup("membros")
      .where("authUid", "==", uid)
      .limit(4)
      .get();
    for (const doc of cg.docs) {
      if (doc.ref.path.startsWith(`igrejas/${tid}/membros/`)) return true;
    }
  } catch (e) {
    functions.logger.warn("userCanAccessTenant: membros CG", { uid, e });
  }

  if (email) {
    const data = ig.data() || {};
    const em = email.toLowerCase();
    if (String(data.email || "").toLowerCase() === em) return true;
    if (String(data.gestorEmail || "").toLowerCase() === em) return true;
  }

  return false;
}
