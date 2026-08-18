import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import { buildGyTopicMessage } from "./notificationBranding";
import { buildGyNotificationDeepLink, sendGyTopicPush, topicPushNovo } from "./pushNovoConteudo";

export const onNovoPedidoOracao = functions.region("us-central1").firestore
  .document("igrejas/{tenantId}/pedidos_oracao/{pedidoId}")
  .onCreate(async (snap, context) => {
    const tenantId = String(context.params.tenantId || "").trim();
    const pedidoId = String(context.params.pedidoId || snap.id || "").trim();
    if (!tenantId || !pedidoId) return null;
    const db = admin.firestore();
    const dedupe = db.collection("igrejas").doc(tenantId).collection("internal_notif_state").doc(`prayer_${pedidoId}`);
    const claimed = await db.runTransaction(async (tx) => {
      const existing = await tx.get(dedupe);
      if (existing.exists) return false;
      tx.create(dedupe, { type: "novo_pedido_oracao", pedidoId, createdAt: admin.firestore.FieldValue.serverTimestamp() });
      return true;
    });
    if (!claimed) return null;
    const d = (snap.data() || {}) as Record<string, unknown>;
    const title = String(d.titulo || d.title || "Novo pedido de oração").trim();
    const requester = String(d.nome || d.name || "Alguém").trim();
    const request = String(d.pedido || d.descricao || d.description || "Novo pedido de oração").replace(/\s+/g, " ").trim();
    const body = `${requester}: ${request.length > 150 ? request.slice(0, 147) + "..." : request}`;
    const deepLink = buildGyNotificationDeepLink(tenantId, `oracoes/${pedidoId}`);
    await db.collection("igrejas").doc(tenantId).collection("notificacoes").doc(`prayer_${pedidoId}`).set({ type: "novo_pedido_oracao", tenantId, prayerId: pedidoId, title, body, deepLink, createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    await sendGyTopicPush(tenantId, "gestores", (churchId) => buildGyTopicMessage({
      topic: topicPushNovo(churchId, "gestores"), title, body, module: "generico",
      data: { type: "novo_pedido_oracao", tenantId: churchId, prayerId: pedidoId, deepLink, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    }));
    return null;
  });

