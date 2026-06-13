/**
 * Paths canónicos — tudo da igreja vive em `igrejas/{churchId}/…`.
 * A coleção raiz `tenants/` é legado (somente leitura de migração); **proibido gravar**.
 */
import type { Firestore, DocumentReference, DocumentSnapshot } from "firebase-admin/firestore";

export const CHURCH_COLLECTION = "igrejas";

export function churchDocRef(db: Firestore, churchId: string): DocumentReference {
  return db.collection(CHURCH_COLLECTION).doc(String(churchId || "").trim());
}

export function churchUsersIndexRef(
  db: Firestore,
  churchId: string,
  docId: string,
): DocumentReference {
  return churchDocRef(db, churchId).collection("usersIndex").doc(String(docId || "").trim());
}

export function churchMembrosRef(
  db: Firestore,
  churchId: string,
  docId: string,
): DocumentReference {
  return churchDocRef(db, churchId).collection("membros").doc(String(docId || "").trim());
}

/** Legado — não gravar; só fallback de leitura enquanto existir lixo antigo. */
export function legacyTenantDocRef(db: Firestore, churchId: string): DocumentReference {
  return db.collection("tenants").doc(String(churchId || "").trim());
}

export async function readChurchRootData(
  db: Firestore,
  churchId: string,
): Promise<Record<string, unknown>> {
  const canonical = await churchDocRef(db, churchId).get();
  if (canonical.exists) {
    return (canonical.data() ?? {}) as Record<string, unknown>;
  }
  const legacy = await legacyTenantDocRef(db, churchId).get();
  return legacy.exists ? ((legacy.data() ?? {}) as Record<string, unknown>) : {};
}

export async function readUsersIndexSnapshot(
  db: Firestore,
  churchId: string,
  docId: string,
): Promise<DocumentSnapshot> {
  const canonical = await churchUsersIndexRef(db, churchId, docId).get();
  if (canonical.exists) return canonical;
  return legacyTenantDocRef(db, churchId).collection("usersIndex").doc(docId).get();
}
