/**
 * Lembretes push — eventos da igreja ~24h e ~60min antes de `startAt`.
 * Respeita tópico `gypush_{churchId}_evento` (preferência pushEventos no app).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { topicPushNovo } from "./pushNovoConteudo";
import { buildGyTopicMessage } from "./notificationBranding";

const db = admin.firestore();

const MS_24H = 24 * 60 * 60 * 1000;
const MS_60M = 60 * 60 * 1000;
const WINDOW_MS = 14 * 60 * 1000;

function clip(s: string, max: number): string {
  const t = String(s || "").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 3))}...`;
}

function eventTitle(d: Record<string, unknown>): string {
  const t = String(d.title || d.titulo || "Evento").trim();
  return t || "Evento";
}

export const scheduledEventoReminders = functions
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
      const col = db.collection("igrejas").doc(tenantId).collection("eventos");

      let q: admin.firestore.QuerySnapshot;
      try {
        q = await col
          .where("startAt", ">=", admin.firestore.Timestamp.fromMillis(now))
          .where("startAt", "<=", admin.firestore.Timestamp.fromMillis(horizon))
          .get();
      } catch (e) {
        functions.logger.warn("eventoReminders query", { tenantId, e });
        continue;
      }

      for (const doc of q.docs) {
        const d = doc.data() as Record<string, unknown>;
        const ts = d.startAt as admin.firestore.Timestamp | undefined;
        if (!ts || typeof ts.toMillis !== "function") continue;
        const eventMs = ts.toMillis();
        const diffMs = eventMs - now;
        if (diffMs <= 0) continue;

        const title = clip(eventTitle(d), 80);
        const when = ts.toDate().toLocaleString("pt-BR", {
          timeZone: "America/Sao_Paulo",
        });

        const in24hWindow =
          diffMs >= MS_24H - WINDOW_MS && diffMs <= MS_24H + WINDOW_MS;
        if (in24hWindow && !d.eventReminder24hSentAt) {
          try {
            await admin.messaging().send(
              buildGyTopicMessage({
                topic: topicPushNovo(tenantId, "evento"),
                title: "📅 Evento amanhã",
                body: clip(`${title} • ${when}`, 160),
                data: {
                  type: "evento_reminder",
                  reminder: "24h",
                  tenantId,
                  eventoId: doc.id,
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                module: "evento",
              }),
            );
            await doc.ref.update({
              eventReminder24hSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            sent24++;
          } catch (e) {
            functions.logger.error("FCM 24h evento", { tenantId, id: doc.id, e });
          }
        }

        const in60Window =
          diffMs >= MS_60M - WINDOW_MS && diffMs <= MS_60M + WINDOW_MS;
        if (in60Window && !d.eventReminder60mSentAt) {
          try {
            await admin.messaging().send(
              buildGyTopicMessage({
                topic: topicPushNovo(tenantId, "evento"),
                title: "📅 Evento em 1 hora",
                body: clip(`${title} • ${when}`, 160),
                data: {
                  type: "evento_reminder",
                  reminder: "60m",
                  tenantId,
                  eventoId: doc.id,
                  click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                module: "evento",
              }),
            );
            await doc.ref.update({
              eventReminder60mSentAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            sent60++;
          } catch (e) {
            functions.logger.error("FCM 60m evento", { tenantId, id: doc.id, e });
          }
        }
      }
    }

    functions.logger.info("scheduledEventoReminders done", { sent24, sent60 });
    return null;
  });
