/**
 * Espaço REAL ocupado por uma igreja no Cloud Storage.
 *
 * A `getChurchStorageUsage` que já existia não mede o bucket: conta documentos
 * do Firestore e estima 1 KB por documento. Para responder «quanto esta igreja
 * ocupa em arquivos» é preciso listar `igrejas/{id}/` e somar os tamanhos —
 * só o Admin SDK consegue, e é o que esta função faz.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { isMasterOperator, userCanAccessTenant } from "./tenantCallableResolve";

interface FootprintBucketGroup {
  label: string;
  bytes: number;
  files: number;
}

/** Agrupa por tipo a partir da extensão — o que o operador quer ver de relance. */
function groupOf(name: string): string {
  const n = name.toLowerCase();
  if (/\.(jpg|jpeg|png|webp|gif|heic|bmp)$/.test(n)) return "Imagens";
  if (/\.(mp4|mov|m4v|webm|avi|mkv)$/.test(n)) return "Vídeos";
  if (/\.(pdf)$/.test(n)) return "PDFs";
  if (/\.(mp3|m4a|aac|wav|ogg)$/.test(n)) return "Áudio";
  return "Outros";
}

export const getChurchStorageFootprint = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const uid = context.auth.uid;
    const email = String(
      ((context.auth.token as Record<string, unknown>)?.email as string) || "",
    )
      .trim()
      .toLowerCase();

    const tenantId = String((data || {}).tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "tenantId obrigatorio",
      );
    }

    const master = await isMasterOperator(
      uid,
      email,
      context.auth.token as Record<string, unknown>,
    );
    if (!master && !(await userCanAccessTenant(uid, email, tenantId))) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Sem permissao para esta igreja",
      );
    }

    const bucket = admin.storage().bucket();
    const prefix = `igrejas/${tenantId}/`;

    let totalBytes = 0;
    let totalFiles = 0;
    const groups: Record<string, FootprintBucketGroup> = {};

    try {
      const [files] = await bucket.getFiles({ prefix });
      for (const f of files) {
        const size = Number(f.metadata?.size ?? 0) || 0;
        totalBytes += size;
        totalFiles++;
        const g = groupOf(f.name);
        if (!groups[g]) groups[g] = { label: g, bytes: 0, files: 0 };
        groups[g].bytes += size;
        groups[g].files++;
      }
    } catch (e) {
      functions.logger.error("getChurchStorageFootprint", { tenantId, e });
      throw new functions.https.HttpsError(
        "internal",
        "Falha ao medir o Storage da igreja.",
      );
    }

    // Documentos do Firestore, para o cartão dar o quadro completo.
    let firestoreDocs = 0;
    try {
      const church = admin.firestore().collection("igrejas").doc(tenantId);
      const subs = ["membros", "eventos", "avisos", "financeiro", "patrimonio"];
      const counts = await Promise.all(
        subs.map((s) =>
          church
            .collection(s)
            .count()
            .get()
            .then((r) => r.data().count ?? 0)
            .catch(() => 0),
        ),
      );
      firestoreDocs = counts.reduce((a, b) => a + b, 0);
    } catch (e) {
      functions.logger.warn("getChurchStorageFootprint: firestore", { e });
    }

    return {
      ok: true,
      tenantId,
      totalBytes,
      totalFiles,
      firestoreDocs,
      groups: Object.values(groups).sort((a, b) => b.bytes - a.bytes),
    };
  });
