import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Remove mensagens de chat expiradas (texto ~30d, mídia ~3d — campo expiresAt)
 * e apaga o ficheiro no Storage quando existir storagePath.
 */
export const pruneExpiredChurchChatMessages = functions
  .region("us-central1")
  .pubsub.schedule("every 6 hours")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const now = admin.firestore.Timestamp.now();
    let snap;
    try {
      snap = await db
        .collectionGroup("messages")
        .where("expiresAt", "<", now)
        .limit(500)
        .get();
    } catch (e) {
      functions.logger.warn("churchChatRetention: query falhou (índice?)", e);
      return null;
    }
    if (snap.empty) {
      functions.logger.info("churchChatRetention: nada a expirar");
      return null;
    }
    let deleted = 0;
    for (const doc of snap.docs) {
      const d = doc.data() as { storagePath?: string };
      const path = String(d.storagePath || "").trim();
      if (path) {
        try {
          await bucket.file(path).delete({ ignoreNotFound: true });
        } catch (e) {
          functions.logger.warn("churchChatRetention: storage delete", { path, e });
        }
      }
      try {
        await doc.ref.delete();
        deleted++;
      } catch (e) {
        functions.logger.warn("churchChatRetention: firestore delete", { id: doc.id, e });
      }
    }
    functions.logger.info(`churchChatRetention: removidas ${deleted} mensagens`);
    return null;
  });
