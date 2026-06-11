import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (v != null && String(v).trim()) return String(v).trim();
  }
  return "";
}

/** Chave canónica do doc `public_church_slugs/{key}` — igual à URL `/igreja/{slug}`. */
export function normalizePublicSlugKey(raw: string): string {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/[\s_]+/g, "-")
    .replace(/[^a-z0-9\-]/g, "")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/**
 * Índice global slug → churchId — 1 leitura no site público e cadastro membro.
 * Mantido por trigger + recomputes de cache público.
 */
export async function syncPublicChurchSlugIndexForChurch(
  tenantId: string,
  church?: Record<string, unknown>,
): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;

  const db = admin.firestore();
  let data = church;
  if (!data) {
    const snap = await db.collection("igrejas").doc(tid).get();
    if (!snap.exists) return;
    data = (snap.data() ?? {}) as Record<string, unknown>;
  }

  const slugKeys = new Set<string>();
  for (const k of ["slug", "slugId", "alias", "siteSlug", "churchSlug"]) {
    const v = pickString(data, [k]);
    if (v) slugKeys.add(normalizePublicSlugKey(v));
  }
  slugKeys.add(normalizePublicSlugKey(tid));

  const churchName = pickString(data, ["nome", "name", "NOME_IGREJA", "nomeIgreja"]);
  const logoUrl = pickString(data, ["logoUrl", "logo_url", "churchLogoUrl"]);

  const batch = db.batch();
  for (const key of slugKeys) {
    if (!key) continue;
    batch.set(
      db.collection("public_church_slugs").doc(key),
      {
        schemaVersion: 1,
        churchId: tid,
        slug: key,
        churchName,
        logoUrl: logoUrl || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
  functions.logger.info("publicChurchSlugIndex: synced", {
    tenantId: tid,
    keys: [...slugKeys],
  });
}

/** Trigger: slug/alias alterados ou igreja nova. */
export const onIgrejaWritePublicSlugIndex = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}")
  .onWrite(async (change, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    if (!tenantId) return;

    if (!change.after.exists) {
      return;
    }

    const after = change.after.data() as Record<string, unknown>;
    const before = change.before.exists
      ? (change.before.data() as Record<string, unknown>)
      : null;

    const slugFields = ["slug", "slugId", "alias", "siteSlug", "churchSlug", "nome", "name"];
    let changed = !change.before.exists;
    if (!changed && before) {
      for (const k of slugFields) {
        if (String(after[k] ?? "") !== String(before[k] ?? "")) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;

    try {
      await syncPublicChurchSlugIndexForChurch(tenantId, after);
    } catch (e) {
      functions.logger.warn("onIgrejaWritePublicSlugIndex", { tenantId, e });
    }
  });

/** Backfill master — todas as igrejas ou uma só. */
export const backfillPublicChurchSlugIndex = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth?.token?.email) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const email = String(context.auth.token.email).toLowerCase();
    if (email !== "raihom@gmail.com") {
      throw new functions.https.HttpsError("permission-denied", "Somente operador master.");
    }

    const db = admin.firestore();
    const one = String((data as { tenantId?: string })?.tenantId ?? "").trim();
    if (one) {
      await syncPublicChurchSlugIndexForChurch(one);
      return { ok: true, count: 1 };
    }

    let count = 0;
    let last: admin.firestore.QueryDocumentSnapshot | undefined;
    const page = 80;
    for (;;) {
      let q = db.collection("igrejas").orderBy(admin.firestore.FieldPath.documentId()).limit(page);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        await syncPublicChurchSlugIndexForChurch(doc.id, doc.data() as Record<string, unknown>);
        count += 1;
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < page) break;
    }
    return { ok: true, count };
  });
