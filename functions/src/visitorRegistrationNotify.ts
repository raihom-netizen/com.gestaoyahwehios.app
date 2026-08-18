/**
 * Push FCM quando há novo cadastro de visitante — só gestores da igreja
 * (pastor, admin, gestor, secretário). Espelha `memberRegistrationNotify.ts`.
 * Tópico: `gypush_{tenantSafe}_gestores` (inscrição no app por papel).
 */
import * as admin from "firebase-admin";
import { buildGyTopicMessage } from "./notificationBranding";
import { topicPushNovo, sendGyTopicPush, buildGyNotificationDeepLink } from "./pushNovoConteudo";

function getDb(): admin.firestore.Firestore {
  return admin.firestore();
}

export async function notifyGestoresNewVisitor(params: {
  tenantId: string;
  visitanteId: string;
  nome: string;
  telefone?: string;
  email?: string;
}): Promise<void> {
  const tenantId = String(params.tenantId || "").trim();
  const visitanteId = String(params.visitanteId || "").trim();
  const nome = String(params.nome || "Novo visitante").trim() || "Novo visitante";
  const telefone = String(params.telefone || "").trim();
  const email = String(params.email || "").trim();
  if (!tenantId || !visitanteId) return;

  const tituloVisitante = nome !== 'Novo visitante'
    ? 'Novo visitante: ' + nome
    : 'Novo visitante';
  const contactBits = [telefone, email].filter((s) => s.length > 0);
  const body = contactBits.length > 0
    ? `${nome} — ${contactBits.join(" · ")}. Toque para ver a ficha.`
    : `${nome} acabou de ser cadastrado(a). Toque para ver a ficha.`;

  await sendGyTopicPush(tenantId, "gestores", (churchId) =>
    buildGyTopicMessage({
      topic: topicPushNovo(churchId, "gestores"),
      title: "🙋 " + tituloVisitante,
      body,
      data: {
        type: "novo_visitante",
        tenantId: churchId,
        visitorId: visitanteId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        deepLink: buildGyNotificationDeepLink(churchId, `visitante/${visitanteId}`),
      },
      module: "visitante",
    }),
  );

  try {
    await getDb().collection("igrejas").doc(tenantId).collection("notificacoes").add({
      type: "novo_visitante",
      title: tituloVisitante,
      body,
      visitorId: visitanteId,
      visitorName: nome,
      visitorPhone: telefone || null,
      visitorEmail: email || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {
    /* in-app opcional */
  }
}
