import * as admin from "firebase-admin";
import { resolveAnchoredCanonicalTenantId } from "./churchClusterAnchors";

function db() {
  return admin.firestore();
}

/** Doc canónico: `church_aliases` → campos do doc raiz → cluster ancorado. */
export async function resolveCanonicalChurchDocId(seed: string): Promise<string> {
  const raw = String(seed || "").trim();
  if (!raw) return raw;

  try {
    const aliasSnap = await db().collection("church_aliases").doc(raw).get();
    if (aliasSnap.exists) {
      const fromAlias = String(aliasSnap.data()?.canonicalId || "").trim();
      if (fromAlias) return resolveAnchoredCanonicalTenantId(fromAlias);
    }
  } catch {
    /* ignore */
  }

  try {
    const doc = await db().collection("igrejas").doc(raw).get();
    if (doc.exists) {
      const d = doc.data() || {};
      for (const k of ["canonicalTenantId", "igrejaId", "churchId", "tenantId"]) {
        const v = String(d[k] || "").trim();
        if (v) return resolveAnchoredCanonicalTenantId(v);
      }
    }
  } catch {
    /* ignore */
  }

  return resolveAnchoredCanonicalTenantId(raw);
}
