import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const MAX_PATHS = 48;
const SIGNED_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Renova URLs de leitura do Storage em lote (painel / site / chat).
 * Reduz dezenas de getDownloadURL no cliente quando o painel abre listas grandes.
 */
export const resolveStorageDisplayUrls = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Autenticação necessária.",
      );
    }
    const raw = data?.paths;
    if (!Array.isArray(raw)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "paths deve ser um array de strings.",
      );
    }
    const paths = raw
      .map((p: unknown) => String(p ?? "").trim().replace(/\\/g, "/"))
      .filter((p) => p.length > 4 && !p.includes(".."))
      .slice(0, MAX_PATHS);
    if (paths.length === 0) {
      return { urls: {} as Record<string, string> };
    }

    const bucket = admin.storage().bucket();
    const expires = Date.now() + SIGNED_TTL_MS;
    const urls: Record<string, string> = {};

    await Promise.all(
      paths.map(async (objectPath) => {
        try {
          const file = bucket.file(objectPath);
          const [signed] = await file.getSignedUrl({
            action: "read",
            expires,
          });
          if (signed) urls[objectPath] = signed;
        } catch (e) {
          functions.logger.warn("resolveStorageDisplayUrls: falha", {
            objectPath,
            e,
          });
        }
      }),
    );

    return { urls };
  });
