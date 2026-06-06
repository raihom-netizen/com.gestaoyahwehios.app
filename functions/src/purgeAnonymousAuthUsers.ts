import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { isPlatformOperatorToken } from "./masterPlatformAuth";

/** Provedores válidos — nunca apagar quem tem um destes. */
const VALID_PROVIDER_IDS = new Set([
  "password",
  "google.com",
  "apple.com",
  "phone",
]);

export type PurgeAnonymousAuthResult = {
  scanned: number;
  deleted: number;
  skipped: number;
  firestoreUsersDeleted: number;
  errors: string[];
  dryRun: boolean;
};

/** Utilizador só anónimo (Auth): sem e-mail/telefone e sem provedor real. */
export function isAnonymousOnlyAuthUser(
  user: admin.auth.UserRecord,
): boolean {
  const email = String(user.email ?? "").trim();
  if (email.length > 0) return false;

  const phone = String(user.phoneNumber ?? "").trim();
  if (phone.length > 0) return false;

  const providers = user.providerData ?? [];
  if (providers.length === 0) return true;

  return !providers.some((p) =>
    VALID_PROVIDER_IDS.has(String(p.providerId ?? "").trim()),
  );
}

async function deleteFirestoreUserDocIfOrphan(
  uid: string,
  dryRun: boolean,
): Promise<boolean> {
  const ref = admin.firestore().collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) return false;

  const data = snap.data() ?? {};
  const docEmail = String(data.email ?? "").trim();
  const cpf = String(data.cpf ?? "").replace(/\D/g, "");
  const role = String(data.role ?? "").trim().toUpperCase();
  if (docEmail.length > 0 || cpf.length >= 11) return false;
  if (
    role === "MASTER" ||
    role === "ADM" ||
    role === "ADMIN" ||
    role === "GESTOR"
  ) {
    return false;
  }

  if (!dryRun) {
    await ref.delete();
  }
  return true;
}

/**
 * Remove todos os utilizadores Firebase Auth **somente anónimos**.
 * Mantém Gmail, Apple, e-mail/senha e telefone.
 */
export async function purgeAnonymousAuthUsersCore(options?: {
  dryRun?: boolean;
  maxDelete?: number;
}): Promise<PurgeAnonymousAuthResult> {
  const dryRun = options?.dryRun === true;
  const maxDelete =
    typeof options?.maxDelete === "number" && options.maxDelete > 0
      ? Math.min(options.maxDelete, 5000)
      : 5000;

  const result: PurgeAnonymousAuthResult = {
    scanned: 0,
    deleted: 0,
    skipped: 0,
    firestoreUsersDeleted: 0,
    errors: [],
    dryRun,
  };

  let pageToken: string | undefined;
  const pendingDelete: string[] = [];
  const deletedUids: string[] = [];

  const flushDeletes = async () => {
    while (pendingDelete.length > 0 && result.deleted < maxDelete) {
      const chunk = pendingDelete.splice(
        0,
        Math.min(1000, maxDelete - result.deleted),
      );
      if (chunk.length === 0) break;

      if (dryRun) {
        result.deleted += chunk.length;
        deletedUids.push(...chunk);
        continue;
      }

      try {
        const del = await admin.auth().deleteUsers(chunk);
        result.deleted += del.successCount;
        deletedUids.push(...chunk.slice(0, del.successCount));
        for (const e of del.errors) {
          result.errors.push(`${e.index}: ${e.error.message}`);
        }
      } catch (e) {
        result.errors.push(e instanceof Error ? e.message : String(e));
      }
    }
  };

  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const user of page.users) {
      if (result.deleted + pendingDelete.length >= maxDelete) break;
      result.scanned += 1;

      if (!isAnonymousOnlyAuthUser(user)) {
        result.skipped += 1;
        continue;
      }

      pendingDelete.push(user.uid);
      if (pendingDelete.length >= 1000) {
        await flushDeletes();
      }
    }

    if (result.deleted + pendingDelete.length >= maxDelete) {
      pageToken = undefined;
    } else {
      pageToken = page.pageToken;
    }
  } while (pageToken);

  await flushDeletes();

  for (const uid of deletedUids) {
    try {
      const removed = await deleteFirestoreUserDocIfOrphan(uid, dryRun);
      if (removed) result.firestoreUsersDeleted += 1;
    } catch (e) {
      result.errors.push(
        `users/${uid}: ${e instanceof Error ? e.message : String(e)}`,
      );
    }
  }

  return result;
}

/**
 * Callable — só operador master (Console / painel).
 * `dryRun: true` — conta sem apagar.
 */
export const purgeAnonymousAuthUsers = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Faça login como master.",
      );
    }

    const token = context.auth.token as Record<string, unknown>;
    if (!isPlatformOperatorToken(token)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Só o operador master pode limpar utilizadores anónimos.",
      );
    }

    const dryRun = data?.dryRun === true;
    const maxDelete =
      typeof data?.maxDelete === "number" ? data.maxDelete : undefined;

    const result = await purgeAnonymousAuthUsersCore({ dryRun, maxDelete });
    functions.logger.info("purgeAnonymousAuthUsers", result);
    return result;
  });
