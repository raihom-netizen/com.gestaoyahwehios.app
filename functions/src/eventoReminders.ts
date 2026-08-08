/**
 * Lembretes push — eventos/cultos da igreja ~24h e ~60min antes do horário.
 * Respeita tópico `gypush_{churchId}_evento` (preferência pushEventos no app).
 *
 * Cobre DUAS fontes:
 *  - coleção `eventos` (mural / feed) — campo `startAt`;
 *  - coleção `agenda` (cultos/eventos lançados direto na Agenda) — campo
 *    `startTime`, filtrado a categorias culto/evento (não dispara para
 *    compromisso interno de liderança etc.).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { topicPushNovo, buildGyNotificationDeepLink } from "./pushNovoConteudo";
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

/** Envia (se estiver na janela) os lembretes 24h/60m de UM documento. */
async function sendRemindersForDoc(
  tenantId: string,
  doc: admin.firestore.QueryDocumentSnapshot,
  eventMs: number,
  now: number,
  deepLinkPath: string,
): Promise<{ s24: number; s60: number }> {
  const d = doc.data() as Record<string, unknown>;
  const diffMs = eventMs - now;
  let s24 = 0;
  let s60 = 0;
  if (diffMs <= 0) return { s24, s60 };

  const title = clip(eventTitle(d), 80);
  const when = new Date(eventMs).toLocaleString("pt-BR", {
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
            deepLink: buildGyNotificationDeepLink(tenantId, deepLinkPath),
          },
          module: "evento",
        }),
      );
      await doc.ref.update({
        eventReminder24hSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      s24++;
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
            deepLink: buildGyNotificationDeepLink(tenantId, deepLinkPath),
          },
          module: "evento",
        }),
      );
      await doc.ref.update({
        eventReminder60mSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      s60++;
    } catch (e) {
      functions.logger.error("FCM 60m evento", { tenantId, id: doc.id, e });
    }
  }

  return { s24, s60 };
}

/** Só lembra a igreja de itens da Agenda que são culto/evento (não interno). */
function agendaDocIsChurchEvent(d: Record<string, unknown>): boolean {
  const cat = String(d.category || d.categoria || d.eventCategoryName || "")
    .toLowerCase();
  if (cat.includes("culto") || cat.includes("evento")) return true;
  // Sem categoria clara: publica no site/mural => é evento da igreja.
  if (d.publicSite === true) return true;
  return false;
}

export const scheduledEventoReminders = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub.schedule("every 10 minutes")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const now = Date.now();
    const horizon = now + 50 * 60 * 60 * 1000;
    const startTs = admin.firestore.Timestamp.fromMillis(now);
    const endTs = admin.firestore.Timestamp.fromMillis(horizon);
    const igrejasSnap = await db.collection("igrejas").get();
    let sent24 = 0;
    let sent60 = 0;

    for (const church of igrejasSnap.docs) {
      const tenantId = church.id;
      const base = db.collection("igrejas").doc(tenantId);

      // 1) Coleção `eventos` (mural/feed) — campo startAt.
      try {
        const q = await base
          .collection("eventos")
          .where("startAt", ">=", startTs)
          .where("startAt", "<=", endTs)
          .get();
        for (const doc of q.docs) {
          const ts = doc.data().startAt as
            | admin.firestore.Timestamp
            | undefined;
          if (!ts || typeof ts.toMillis !== "function") continue;
          const r = await sendRemindersForDoc(
            tenantId,
            doc,
            ts.toMillis(),
            now,
            `evento/${doc.id}`,
          );
          sent24 += r.s24;
          sent60 += r.s60;
        }
      } catch (e) {
        functions.logger.warn("eventoReminders eventos query", { tenantId, e });
      }

      // 2) Coleção `agenda` (cultos/eventos lançados direto) — campo startTime.
      try {
        const qa = await base
          .collection("agenda")
          .where("startTime", ">=", startTs)
          .where("startTime", "<=", endTs)
          .get();
        for (const doc of qa.docs) {
          const data = doc.data() as Record<string, unknown>;
          if (!agendaDocIsChurchEvent(data)) continue;
          const ts = data.startTime as admin.firestore.Timestamp | undefined;
          if (!ts || typeof ts.toMillis !== "function") continue;
          const r = await sendRemindersForDoc(
            tenantId,
            doc,
            ts.toMillis(),
            now,
            "agenda",
          );
          sent24 += r.s24;
          sent60 += r.s60;
        }
      } catch (e) {
        functions.logger.warn("eventoReminders agenda query", { tenantId, e });
      }
    }

    functions.logger.info("scheduledEventoReminders done", { sent24, sent60 });
    return null;
  });
