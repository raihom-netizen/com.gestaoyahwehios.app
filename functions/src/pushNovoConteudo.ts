/**
 * Push FCM por tópico quando há conteúdo novo (avisos, eventos na agenda, escalas).
 * Tópicos alinhados ao app: `gypush_{tenantIdSafe}_{aviso|evento|escala}`.
 * O app inscreve/desinscreve conforme `users/{uid}.pushAvisos`, `pushEventos`, `pushEscalas` (padrão true).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { buildGyTopicMessage } from "./notificationBranding";

function safeTid(t: string): string {
  return String(t || "").replace(/[^a-zA-Z0-9\-_.~%]/g, "_");
}

/** Mesmo formato usado no Flutter [FcmService.topicPushNovo]. */
export function topicPushNovo(
  tenantId: string,
  kind:
    | "aviso"
    | "evento"
    | "escala"
    | "fornecedor_agenda"
    | "gestores"
    | "financeiro",
): string {
  return `gypush_${safeTid(tenantId)}_${kind}`;
}

function clip(s: string, max: number): string {
  const t = String(s || "").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 3))}...`;
}

async function sendNovoAvisoMuralPush(
  tenantId: string,
  postId: string,
  d: Record<string, unknown>,
): Promise<void> {
  const title = clip(String(d.title || "Novo aviso"), 80) || "Novo aviso";
  const rawBody = String(d.text || d.body || d.mensagem || "").trim();
  const body = clip(rawBody, 140) || title;
  await admin.messaging().send(
    buildGyTopicMessage({
      topic: topicPushNovo(tenantId, "aviso"),
      title: "📢 Novo aviso",
      body,
      data: {
        type: "novo_aviso",
        tenantId,
        postId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      module: "aviso",
    }),
  );
}

export const onNovoAvisoMuralPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{id}")
  .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId as string;
    const d = snap.data() || {};
    if (String(d.publishState || "") === "uploading") return null;
    try {
      await sendNovoAvisoMuralPush(
        tenantId,
        context.params.id as string,
        d as Record<string, unknown>,
      );
    } catch (e) {
      functions.logger.error("onNovoAvisoMuralPush FCM", { tenantId, e });
    }
    return null;
  });

/** Push quando o aviso passa de `uploading` → `published` (publicação rápida no app). */
export const onNovoAvisoMuralPublishedPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{id}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (String(before.publishState || "") !== "uploading") return null;
    if (String(after.publishState || "") !== "published") return null;
    const tenantId = context.params.tenantId as string;
    try {
      await sendNovoAvisoMuralPush(
        tenantId,
        context.params.id as string,
        after as Record<string, unknown>,
      );
    } catch (e) {
      functions.logger.error("onNovoAvisoMuralPublishedPush FCM", { tenantId, e });
    }
    return null;
  });

async function sendNovoEventoNoticiaPush(
  tenantId: string,
  postId: string,
  d: Record<string, unknown>,
): Promise<void> {
  if (String(d.type || "").toLowerCase() !== "evento") return;
  const title = clip(String(d.title || "Novo evento"), 80) || "Novo evento";
  const startAt = d.startAt as admin.firestore.Timestamp | undefined;
  let extra = "";
  if (startAt && typeof startAt.toDate === "function") {
    const dt = startAt.toDate();
    extra = ` • ${dt.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`;
  }
  const body = clip(`${title}${extra}`, 180);
  await admin.messaging().send(
    buildGyTopicMessage({
      topic: topicPushNovo(tenantId, "evento"),
      title: "📅 Novo evento",
      body,
      data: {
        type: "novo_evento",
        tenantId,
        postId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      module: "evento",
    }),
  );
}

export const onNovoEventoNoticiaPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{id}")
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    if (String(d.type || "").toLowerCase() !== "evento") return null;
    if (String(d.publishState || "") === "uploading") return null;

    const tenantId = context.params.tenantId as string;
    try {
      await sendNovoEventoNoticiaPush(
        tenantId,
        context.params.id as string,
        d as Record<string, unknown>,
      );
    } catch (e) {
      functions.logger.error("onNovoEventoNoticiaPush FCM", { tenantId, e });
    }
    return null;
  });

/** Push quando o evento passa de `uploading` → `published` (fotos em segundo plano). */
export const onNovoEventoNoticiaPublishedPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{id}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (String(after.type || "").toLowerCase() !== "evento") return null;
    if (String(before.publishState || "") !== "uploading") return null;
    if (String(after.publishState || "") !== "published") return null;
    const tenantId = context.params.tenantId as string;
    try {
      await sendNovoEventoNoticiaPush(
        tenantId,
        context.params.id as string,
        after as Record<string, unknown>,
      );
    } catch (e) {
      functions.logger.error("onNovoEventoNoticiaPublishedPush FCM", {
        tenantId,
        e,
      });
    }
    return null;
  });
