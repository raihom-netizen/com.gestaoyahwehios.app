/**
 * Retencao de eventos temporarios.
 *
 * Eventos com validade nunca entram na Galeria. Depois de 24 horas da
 * validade, remove documento, subcolecoes e a pasta canonica no Storage.
 * Eventos permanentes (sem validUntil ou galleryPermanent=true) sao preservados.
 */
import * as functions from "firebase-functions/v1";
import { admin, fs, storageBucket } from "./adminDb";

const PAGE_SIZE = 200;

function safeSegment(value: unknown): string {
  return String(value ?? "")
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, "_");
}

export const scheduledCleanupExpiredTemporaryEvents = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .pubsub.schedule("every 6 hours")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 24 * 60 * 60 * 1000,
    );
    const snap = await fs()
      .collectionGroup("eventos")
      .where("validUntil", "<=", cutoff)
      .limit(PAGE_SIZE)
      .get();

    let deleted = 0;
    let skipped = 0;
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      if (String(data.type ?? "") !== "evento" || data.galleryPermanent === true) {
        skipped += 1;
        continue;
      }

      const tenantId = safeSegment(doc.ref.parent.parent?.id);
      const eventId = safeSegment(doc.id);
      if (!tenantId || !eventId) {
        skipped += 1;
        continue;
      }

      // Apaga primeiro a pasta para a limpeza nao depender apenas do trigger
      // onDelete. ignoreNotFound torna a operacao idempotente.
      await storageBucket()
        .deleteFiles({ prefix: `igrejas/${tenantId}/eventos/${eventId}/` })
        .catch((error) => {
          functions.logger.warn("eventExpirationCleanup storage", {
            tenantId,
            eventId,
            error,
          });
        });

      await fs().recursiveDelete(doc.ref);
      deleted += 1;
    }

    functions.logger.info("scheduledCleanupExpiredTemporaryEvents done", {
      cutoff: cutoff.toDate().toISOString(),
      found: snap.size,
      deleted,
      skipped,
    });
  });