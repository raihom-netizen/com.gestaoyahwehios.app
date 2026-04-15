/**
 * Push FCM por tópico quando há conteúdo novo (avisos, eventos na agenda, escalas).
 * Tópicos alinhados ao app: `gypush_{tenantIdSafe}_{aviso|evento|escala}`.
 * O app inscreve/desinscreve conforme `users/{uid}.pushAvisos`, `pushEventos`, `pushEscalas` (padrão true).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

function safeTid(t: string): string {
  return String(t || "").replace(/[^a-zA-Z0-9\-_.~%]/g, "_");
}

/** Mesmo formato usado no Flutter [FcmService.topicPushNovo]. */
export function topicPushNovo(
  tenantId: string,
  kind: "aviso" | "evento" | "escala" | "fornecedor_agenda",
): string {
  return `gypush_${safeTid(tenantId)}_${kind}`;
}

function clip(s: string, max: number): string {
  const t = String(s || "").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 3))}...`;
}

export const onNovoAvisoMuralPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{id}")
  .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId as string;
    const d = snap.data() || {};
    const title = clip(String(d.title || "Novo aviso"), 80) || "Novo aviso";
    const rawBody = String(d.text || d.body || d.mensagem || "").trim();
    const body = clip(rawBody, 140) || title;
    try {
      await admin.messaging().send({
        topic: topicPushNovo(tenantId, "aviso"),
        notification: { title: "Novo aviso", body },
        data: {
          type: "novo_aviso",
          tenantId,
          postId: context.params.id,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      });
    } catch (e) {
      functions.logger.error("onNovoAvisoMuralPush FCM", { tenantId, e });
    }
  });

export const onNovoEventoNoticiaPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/noticias/{id}")
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    if (String(d.type || "").toLowerCase() !== "evento") return;

    const tenantId = context.params.tenantId as string;
    const title = clip(String(d.title || "Novo evento"), 80) || "Novo evento";
    const startAt = d.startAt as admin.firestore.Timestamp | undefined;
    let extra = "";
    if (startAt && typeof startAt.toDate === "function") {
      const dt = startAt.toDate();
      extra = ` • ${dt.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`;
    }
    const body = clip(`${title}${extra}`, 180);
    try {
      await admin.messaging().send({
        topic: topicPushNovo(tenantId, "evento"),
        notification: { title: "Novo evento", body },
        data: {
          type: "novo_evento",
          tenantId,
          postId: context.params.id,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      });
    } catch (e) {
      functions.logger.error("onNovoEventoNoticiaPush FCM", { tenantId, e });
    }
  });
