import * as admin from "firebase-admin";

function db() {
  return admin.firestore();
}

/** Doc canónico SaaS — só `igrejas/{docId}` directo (sem `church_aliases`). */
export async function resolveCanonicalChurchDocId(seed: string): Promise<string> {
  const raw = String(seed || "").trim();
  if (!raw) return raw;

  try {
    const doc = await db().collection("igrejas").doc(raw).get();
    if (doc.exists) return raw;
  } catch {
    /* ignore */
  }

  try {
    for (const k of ["churchId", "igrejaId", "tenantId", "canonicalTenantId"]) {
      const q = await db()
        .collection("igrejas")
        .where(k, "==", raw)
        .limit(1)
        .get();
      if (!q.empty) return q.docs[0].id;
    }
  } catch {
    /* ignore */
  }

  return raw;
}
