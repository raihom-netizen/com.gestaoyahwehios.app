/**
 * Padroniza cada igreja: tudo em `igrejas/{canonicalId}/…` (membros, finance, chats, etc.).
 * Idempotente — igrejas existentes e novas.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { provisionChurchTenant } from "./churchTenantProvisioning";
import { runSyncChurchClusterDataFromRichest } from "./syncChurchClusterData";
import { resolveCanonicalChurchDocId } from "./churchCanonicalResolve";

function db() {
  return admin.firestore();
}

/** Copia `igrejas/{id}/members` → `igrejas/{canonical}/membros` (merge). */
export async function migrateMembersSubcollectionToMembros(
  igrejaId: string,
): Promise<number> {
  const canonical = await resolveCanonicalChurchDocId(igrejaId);
  const target = canonical || igrejaId;
  const churchRef = db().collection("igrejas").doc(target);
  const probe = await churchRef.collection("members").limit(1).get();
  if (probe.empty) return 0;

  const FieldPath = admin.firestore.FieldPath;
  let total = 0;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = churchRef.collection("members").orderBy(FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db().batch();
    for (const d of snap.docs) {
      batch.set(churchRef.collection("membros").doc(d.id), d.data() || {}, { merge: true });
      total++;
    }
    await batch.commit();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }
  return total;
}

export type ChurchTenantConsolidationResult = {
  ok: boolean;
  tenantId: string;
  canonicalId: string;
  provision?: Record<string, unknown>;
  clusterSync?: Record<string, unknown>;
  membersMigrated: number;
  source: string;
};

/** Uma chamada: aliases + doc raiz + subcoleções no canónico + members→membros. */
export async function runChurchTenantConsolidation(
  tenantId: string,
  options?: { source?: string; forceCluster?: boolean },
): Promise<ChurchTenantConsolidationResult> {
  const seed = String(tenantId || "").trim();
  if (!seed) {
    throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatório.");
  }

  const canonical = await resolveCanonicalChurchDocId(seed);
  const source = String(options?.source || "runChurchTenantConsolidation");

  const provision = await provisionChurchTenant(canonical, {
    source: `${source}:provision`,
  });

  let clusterSync: Record<string, unknown> = { skipped: true };
  try {
    clusterSync = await runSyncChurchClusterDataFromRichest(canonical, {
      force: options?.forceCluster === true,
    });
  } catch (e) {
    clusterSync = {
      ok: false,
      error: e instanceof Error ? e.message : String(e),
    };
  }

  const membersMigrated = await migrateMembersSubcollectionToMembros(canonical);

  return {
    ok: true,
    tenantId: seed,
    canonicalId: canonical,
    provision: provision as unknown as Record<string, unknown>,
    clusterSync,
    membersMigrated,
    source,
  };
}
