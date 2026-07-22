import * as functions from "firebase-functions/v1";
import { admin, fs } from "./adminDb";

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
  if (fromBody && (await userCanAccessTenant(uid, email, fromBody))) {
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
): Promise<boolean> {
  const tid = String(tenantId || "").trim();
  if (!tid) return false;
  const ig = await fs().collection("igrejas").doc(tid).get();
  if (!ig.exists) return false;

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
