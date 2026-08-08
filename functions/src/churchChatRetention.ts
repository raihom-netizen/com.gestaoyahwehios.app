import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/**
 * Remove mensagens de chat expiradas (campo expiresAt) e apaga Storage.
 *
 * App grava:
 * - texto: NUNCA grava expiresAt — permanente (não passa por esta função).
 * - mídia (foto/vídeo/áudio/sticker): 60d (ChurchChatService.mediaRetention).
 *
 * Mensagens de texto antigas (enviadas antes desta mudança) ainda podem ter
 * um expiresAt de ~30 dias gravado — essas continuam sendo removidas quando
 * vencerem, mas nenhum texto novo grava esse campo.
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
    let preserved = 0;
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
        const d = doc.data() as { storagePath?: string; type?: string };
        const path = String(d.storagePath || "").trim();
        const type = String(d.type || "").trim().toLowerCase();
        // TEXTO NUNCA é apagado por retenção — nem com expiresAt legado.
        // Só mídia (foto/vídeo/áudio/sticker/arquivo) expira em 60 dias.
        // Reconhece mídia por storagePath OU por type não-textual; na dúvida
        // (type vazio e sem path) trata como texto e PRESERVA.
        const isMedia =
          path !== "" ||
          (type !== "" &&
            type !== "text" &&
            type !== "texto" &&
            type !== "message" &&
            type !== "chat");
        if (!isMedia) {
          // Remove o expiresAt legado -> texto vira permanente e a query não
          // devolve o mesmo doc para sempre (senão reprocessaria em loop).
          try {
            await doc.ref.update({
              expiresAt: admin.firestore.FieldValue.delete(),
            });
            preserved++;
          } catch (e) {
            functions.logger.warn("churchChatRetention: preservar texto", { id: doc.id, e });
          }
          continue;
        }
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
    functions.logger.info(
      `churchChatRetention: midia removida=${deleted}, texto preservado=${preserved}`
    );
    return null;
  });
