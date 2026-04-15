/**
 * Lembretes push (FCM por tópico) para compromissos da agenda de fornecedores:
 * ~24h antes e ~60min antes, para gestor/secretário/tesoureiro/pastor (inscritos em topicPushNovo(..., fornecedor_agenda)).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { topicPushNovo } from "./pushNovoConteudo";

const db = admin.firestore();

const MS_24H = 24 * 60 * 60 * 1000;
const MS_60M = 60 * 60 * 1000;
/** Folga para o cron de 10 min não perder a janela. */
const WINDOW_MS = 14 * 60 * 1000;

function clip(s: string, max: number): string {
  const t = String(s || "").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 3))}...`;
}

export const scheduledFornecedorAgendaReminders = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub.schedule("every 10 minutes")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const now = Date.now();
    const horizon = now + 50 * 60 * 60 * 1000;

    const igrejasSnap = await db.collection("igrejas").get();
    let sent24 = 0;
    let sent60 = 0;

    for (const church of igrejasSnap.docs) {
      const tenantId = church.id;
      const compCol = db.collection("igrejas").doc(tenantId).collection("fornecedor_compromissos");

      let q: admin.firestore.QuerySnapshot;
      try {
        q = await compCol
          .where("dataVencimento", ">=", admin.firestore.Timestamp.fromMillis(now))
          .where("dataVencimento", "<=", admin.firestore.Timestamp.fromMillis(horizon))
          .get();
      } catch (e) {
        functions.logger.warn("fornecedorAgendaReminders query", { tenantId, e });
        continue;
      }

      for (const doc of q.docs) {
        const d = doc.data();
        const ts = d.dataVencimento as admin.firestore.Timestamp | undefined;
        if (!ts || typeof ts.toMillis !== "function") continue;
        const eventMs = ts.toMillis();
        const diffMs = eventMs - now;
        if (diffMs <= 0) continue;

        const titulo = clip(String(d.titulo || "Compromisso"), 80);
        const fornecedorId = String(d.fornecedorId || "").trim();

        const in24hWindow = diffMs >= MS_24H - WINDOW_MS && diffMs <= MS_24H + WINDOW_MS;
        if (in24hWindow && !d.reminder24hSentAt) {
          try {
            await admin.messaging().send({
              topic: topicPushNovo(tenantId, "fornecedor_agenda"),
              notification: {
                title: "Fornecedor — lembrete (24h)",
                body: clip(`${titulo}`, 160),
              },
              data: {
                type: "fornecedor_agenda_reminder",
                reminder: "24h",
                tenantId,
                fornecedorId,
                compromissoId: doc.id,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            });
            await doc.ref.update({
              reminder24hSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            sent24++;
          } catch (e) {
            functions.logger.error("FCM 24h fornecedor agenda", { tenantId, id: doc.id, e });
          }
        }

        const in60Window = diffMs >= MS_60M - WINDOW_MS && diffMs <= MS_60M + WINDOW_MS;
        if (in60Window && !d.reminder60mSentAt) {
          try {
            await admin.messaging().send({
              topic: topicPushNovo(tenantId, "fornecedor_agenda"),
              notification: {
                title: "Fornecedor — lembrete (1h)",
                body: clip(`${titulo}`, 160),
              },
              data: {
                type: "fornecedor_agenda_reminder",
                reminder: "60m",
                tenantId,
                fornecedorId,
                compromissoId: doc.id,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            });
            await doc.ref.update({
              reminder60mSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            sent60++;
          } catch (e) {
            functions.logger.error("FCM 60m fornecedor agenda", { tenantId, id: doc.id, e });
          }
        }
      }
    }

    functions.logger.info("scheduledFornecedorAgendaReminders done", { sent24, sent60 });
    return null;
  });
