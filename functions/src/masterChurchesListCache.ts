import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { isPlatformOperatorToken } from "./masterPlatformAuth";

const STALE_MS = 10 * 60 * 1000;
const LIST_LIMIT = 80;
const RECOMPUTE_MIN_MS = 45_000;

function isMasterCaller(token: Record<string, unknown> | undefined): boolean {
  return isPlatformOperatorToken(token);
}

function pickString(data: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function lightChurchRow(
  id: string,
  data: Record<string, unknown>,
): Record<string, unknown> {
  const lic = data.license;
  let licenseExpiresAt: admin.firestore.Timestamp | null = null;
  if (data.licenseExpiresAt instanceof admin.firestore.Timestamp) {
    licenseExpiresAt = data.licenseExpiresAt;
  } else if (lic && typeof lic === "object") {
    const l = lic as Record<string, unknown>;
    if (l.expiresAt instanceof admin.firestore.Timestamp) {
      licenseExpiresAt = l.expiresAt;
    }
  }
  return {
    id,
    nome: pickString(data, ["nome", "name"]) || id,
    slug: pickString(data, ["slug", "slugId", "alias"]),
    status: pickString(data, ["status"]) || "ativa",
    plano: pickString(data, ["plano", "planId", "plan"]),
    planId: pickString(data, ["planId", "plano"]),
    logoUrl: pickString(data, ["logoUrl", "logo_url", "logoProcessedUrl"]),
    institutionalVideoUrl: pickString(data, [
      "institutionalVideoUrl",
      "videoInstitucionalUrl",
      "videoUrl",
    ]),
    adminBlocked: data.adminBlocked === true,
    isFree:
      data.isFree === true ||
      pickString(data, ["plano", "planId"]).toLowerCase() === "free",
    dataVencimento:
      data.dataVencimento ??
      data.vencimento ??
      licenseExpiresAt ??
      null,
    licenseExpiresAt,
    createdAt:
      data.createdAt ??
      data.created_at ??
      data.dataCadastro ??
      null,
    gestorEmail: pickString(data, ["gestorEmail", "emailGestor", "email"]),
    whatsappIgreja: pickString(data, [
      "whatsappIgreja",
      "whatsapp",
      "telefone",
      "telefoneIgreja",
    ]),
    removedByAdminAt: data.removedByAdminAt ?? null,
    license: lic && typeof lic === "object" ? lic : null,
  };
}

/** Índice leve para Lista Igrejas — `config/master_churches_index`. */
export async function recomputeMasterChurchesIndex(): Promise<void> {
  const db = admin.firestore();
  const lockRef = db.collection("config").doc("_master_churches_list_lock");
  const indexRef = db.collection("config").doc("master_churches_index");

  const nowMs = Date.now();
  const lockSnap = await lockRef.get();
  if (lockSnap.exists) {
    const last = lockSnap.data()?.lastRun as admin.firestore.Timestamp | undefined;
    if (last && nowMs - last.toMillis() < RECOMPUTE_MIN_MS) return;
  }
  await lockRef.set(
    { lastRun: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true },
  );

  let docs: admin.firestore.QueryDocumentSnapshot[] = [];
  try {
    const ordered = await db
      .collection("igrejas")
      .orderBy("createdAt", "desc")
      .limit(LIST_LIMIT)
      .get();
    docs = ordered.docs;
  } catch (e) {
    functions.logger.warn("masterChurchesList: orderBy createdAt", { e });
    const plain = await db.collection("igrejas").limit(LIST_LIMIT).get();
    docs = plain.docs;
  }

  const churches = docs.map((d) => lightChurchRow(d.id, d.data()));
  let total = churches.length;
  try {
    const cnt = await db.collection("igrejas").count().get();
    total = cnt.data().count;
  } catch (_) {}

  await indexRef.set(
    {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      schemaVersion: 1,
      total,
      churches,
    },
    { merge: false },
  );
}

export const getMasterChurchesList = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const token = (context.auth.token || {}) as Record<string, unknown>;
    if (!isMasterCaller(token)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Acesso apenas para administradores da plataforma",
      );
    }

    const db = admin.firestore();
    const indexRef = db.collection("config").doc("master_churches_index");
    const snap = await indexRef.get();
    const updated = snap.data()?.updatedAt as admin.firestore.Timestamp | undefined;
    const isStale =
      !snap.exists ||
      !updated ||
      Date.now() - updated.toMillis() > STALE_MS;

    if (isStale) {
      await recomputeMasterChurchesIndex();
    }

    const fresh = await indexRef.get();
    const data = fresh.data() ?? {};
    return {
      ok: true,
      total: data.total ?? 0,
      churches: data.churches ?? [],
      updatedAt: data.updatedAt ?? null,
    };
  });

export const scheduledRefreshMasterChurchesList = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 120, memory: "256MB" })
  .pubsub.schedule("every 60 minutes")
  .onRun(async () => {
    try {
      await recomputeMasterChurchesIndex();
      functions.logger.info("masterChurchesList: scheduled ok");
    } catch (e) {
      functions.logger.error("masterChurchesList: scheduled failed", { e });
    }
    return null;
  });
