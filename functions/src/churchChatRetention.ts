import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Remove mensagens de chat expiradas (campo expiresAt) e apaga Storage.
 *
 * App grava:
 * - texto ~30d (ChurchChatService.textRetention)
 * - mídia ~90d (ChurchChatService.mediaRetention) — NÃO 3 dias
 *
 * Mensagens antigas com expiresAt de 3 dias (legado) serão limpas quando
 * expirarem; novos envios já usam 90 dias.
 */
export const pruneExpiredChurchChatMessages = functions
  .region("us-central1")
  .pubsub.schedule("every 6 hours")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const now = admin.firestore.Timestamp.now();
    let deleted = 0;
    const maxRounds = 20;
    for (let round = 0; round < maxRounds; round++) {
      let snap;
      try {
        snap = await db
          .collectionGroup("messages")
          .where("expiresAt", "<", now)
          .limit(500)
          .get();
      } catch (e) {
        functions.logger.warn("churchChatRetention: query falhou (índice?)", e);
        break;
      }
      if (snap.empty) break;
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
      if (snap.size < 500) break;
    }
    if (deleted === 0) {
      functions.logger.info("churchChatRetention: nada a expirar");
    } else {
      functions.logger.info(`churchChatRetention: removidas ${deleted} mensagens`);
    }
    return null;
  });
