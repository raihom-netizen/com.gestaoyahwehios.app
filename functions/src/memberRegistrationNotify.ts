/**
 * Push FCM quando há novo cadastro de membro — só gestores da igreja (pastor, admin, gestor, secretário).
 * Tópico: `gypush_{tenantSafe}_gestores` (inscrição no app por papel).
 */
import * as admin from "firebase-admin";
import { buildGyTopicMessage } from "./notificationBranding";
import { topicPushNovo, sendGyTopicPush } from "./pushNovoConteudo";

function getDb(): admin.firestore.Firestore {
  return admin.firestore();
}

export function isPublicMemberSignup(data: Record<string, unknown>): boolean {
  if (
    data.PUBLIC_SIGNUP === true ||
    data.publicSignup === true ||
    data.public_signup === true
  ) {
    return true;
  }
  const status = String(data.STATUS || data.status || "")
    .trim()
    .toLowerCase();
  return status.includes("pendente") || status.includes("aguard");
}

export async function notifyGestoresNewMember(params: {
  tenantId: string;
  membroId: string;
  nome: string;
  data: Record<string, unknown>;
}): Promise<void> {
  const tenantId = String(params.tenantId || "").trim();
  const membroId = String(params.membroId || "").trim();
  const nome = String(params.nome || "Novo membro").trim() || "Novo membro";
  if (!tenantId || !membroId) return;

  const publicSignup = isPublicMemberSignup(params.data);
  const body = publicSignup
    ? `${nome} cadastrou-se pelo site público. Toque para ver ou aprovar.`
    : `${nome} foi cadastrado(a) na igreja. Toque para ver a ficha.`;

  await sendGyTopicPush(tenantId, "gestores", (churchId) =>
    buildGyTopicMessage({
      topic: topicPushNovo(churchId, "gestores"),
      title: publicSignup ? "⚡ Novo cadastro (site)" : "👤 Novo membro",
      body,
      data: {
        type: "new_member",
        tenantId: churchId,
        memberId: membroId,
        publicSignup: publicSignup ? "1" : "0",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      module: "membro",
    }),
  );

  try {
    await getDb().collection("igrejas").doc(tenantId).collection("notificacoes").add({
      type: "novo_membro",
      title: publicSignup ? "Novo cadastro (site)" : "Novo membro",
      body,
      memberId: membroId,
      memberName: nome,
      publicSignup,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {
    /* in-app opcional */
  }
}
