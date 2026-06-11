/**
 * Push FCM por tópico — avisos, eventos (path directo `igrejas/{churchId}/…`).
 * Tópicos: `gypush_{churchId}_{aviso|evento|escala|aniversario|gestores}`.
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
    | "aniversario"
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

function isEventoDoc(d: Record<string, unknown>): boolean {
  const typeRaw = String(d.type || "evento").trim().toLowerCase();
  return typeRaw === "evento" || typeRaw === "" || typeRaw === "event";
}

async function recordTenantNotification(
  tenantId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  try {
    await admin
      .firestore()
      .collection("igrejas")
      .doc(tenantId)
      .collection("notificacoes")
      .add({
        ...payload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (_) {
    /* opcional */
  }
}

/** Push FCM directo — um tópico por `igrejas/{churchId}`. */
export async function sendGyTopicPush(
  tenantId: string,
  kind: Parameters<typeof topicPushNovo>[1],
  build: (effectiveTenantId: string) => admin.messaging.Message,
): Promise<void> {
  const tid = String(tenantId || "").trim();
  if (!tid) return;
  await admin.messaging().send(build(tid));
}

/** @deprecated Use [sendGyTopicPush] — mantido para imports legados. */
export async function sendGyTopicPushCluster(
  tenantId: string,
  kind: Parameters<typeof topicPushNovo>[1],
  build: (effectiveTenantId: string) => admin.messaging.Message,
): Promise<void> {
  await sendGyTopicPush(tenantId, kind, build);
}

async function sendNovoAvisoMuralPush(
  tenantId: string,
  postId: string,
  d: Record<string, unknown>,
): Promise<void> {
  const title = clip(String(d.title || d.titulo || "Novo aviso"), 80) || "Novo aviso";
  const rawBody = String(d.text || d.body || d.mensagem || "").trim();
  const body = clip(rawBody, 140) || title;
  await sendGyTopicPush(tenantId, "aviso", (churchId) =>
    buildGyTopicMessage({
      topic: topicPushNovo(churchId, "aviso"),
      title: "📢 Novo aviso",
      body,
      data: {
        type: "novo_aviso",
        tenantId: churchId,
        postId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      module: "aviso",
    }),
  );
  await recordTenantNotification(tenantId, {
    type: "novo_aviso",
    title: "Novo aviso",
    body,
    postId,
  });
}

function isPublishedFeedDoc(d: Record<string, unknown>): boolean {
  const state = String(d.publishState || "").trim().toLowerCase();
  if (state === "uploading" || state === "draft") return false;
  if (state === "published" || state === "success") return true;
  if (d.publicado === true) return true;
  const status = String(d.status || "").trim().toLowerCase();
  return status === "publicado";
}

export const onNovoAvisoMuralPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{id}")
  .onCreate(async (snap, context) => {
    const tenantId = context.params.tenantId as string;
    const d = snap.data() || {};
    if (!isPublishedFeedDoc(d as Record<string, unknown>)) return null;
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

export const onNovoAvisoMuralPublishedPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{id}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (isPublishedFeedDoc(before as Record<string, unknown>)) return null;
    if (!isPublishedFeedDoc(after as Record<string, unknown>)) return null;
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
  if (!isEventoDoc(d)) return;
  const title = clip(String(d.title || d.titulo || "Novo evento"), 80) || "Novo evento";
  const startAt = d.startAt as admin.firestore.Timestamp | undefined;
  let extra = "";
  if (startAt && typeof startAt.toDate === "function") {
    const dt = startAt.toDate();
    extra = ` • ${dt.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`;
  }
  const body = clip(`${title}${extra}`, 180);
  await sendGyTopicPush(tenantId, "evento", (churchId) =>
    buildGyTopicMessage({
      topic: topicPushNovo(churchId, "evento"),
      title: "📅 Novo evento",
      body,
      data: {
        type: "novo_evento",
        tenantId: churchId,
        postId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      module: "evento",
    }),
  );
  await recordTenantNotification(tenantId, {
    type: "novo_evento",
    title: "Novo evento",
    body,
    postId,
  });
}

export const onNovoEventoNoticiaPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{id}")
  .onCreate(async (snap, context) => {
    const d = snap.data() || {};
    if (!isEventoDoc(d)) return null;
    if (!isPublishedFeedDoc(d as Record<string, unknown>)) return null;

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

export const onNovoEventoNoticiaPublishedPush = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{id}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    if (!isEventoDoc(after)) return null;
    if (isPublishedFeedDoc(before as Record<string, unknown>)) return null;
    if (!isPublishedFeedDoc(after as Record<string, unknown>)) return null;
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
