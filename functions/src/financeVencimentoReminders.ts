/**
 * Lembretes push (FCM) de contas a pagar / a receber no Financeiro.
 * Destinatários: pastor, admin, gestor, tesoureiro (tópico `gypush_{tenant}_financeiro`).
 *
 * - 7h (SP): resumo do dia (vencimentos hoje + em atraso).
 * - A cada 10 min: janela ~24h antes do vencimento (item a item, deduplicado).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { topicPushNovo } from "./pushNovoConteudo";
import { buildGyTopicMessage } from "./notificationBranding";

const db = admin.firestore();
const TZ_BR = "America/Sao_Paulo";

const MS_24H = 24 * 60 * 60 * 1000;
const WINDOW_MS = 14 * 60 * 1000;

function financeTipoLower(d: Record<string, unknown>): string {
  return String(d.type || d.tipo || "").toLowerCase();
}

function isPendingPagamento(d: Record<string, unknown>): boolean {
  const tipo = financeTipoLower(d);
  if (tipo === "transferencia") return false;
  if (tipo.includes("saida") || tipo.includes("despesa")) {
    return d.pagamentoConfirmado === false;
  }
  return false;
}

function isPendingRecebimento(d: Record<string, unknown>): boolean {
  const tipo = financeTipoLower(d);
  if (tipo === "transferencia") return false;
  if (tipo.includes("entrada") || tipo.includes("receita")) {
    return d.recebimentoConfirmado === false;
  }
  return false;
}

function financeLancamentoDate(d: Record<string, unknown>): Date | null {
  const raw = d.date ?? d.dataCompetencia ?? d.createdAt;
  if (!raw) return null;
  if (typeof (raw as admin.firestore.Timestamp).toDate === "function") {
    return (raw as admin.firestore.Timestamp).toDate();
  }
  return null;
}

function ymdInTz(d: Date, tz: string): string {
  return d.toLocaleDateString("en-CA", { timeZone: tz });
}

function clip(s: string, max: number): string {
  const t = String(s || "").trim();
  if (t.length <= max) return t;
  return `${t.slice(0, Math.max(0, max - 3))}...`;
}

function lancamentoTitulo(d: Record<string, unknown>): string {
  return clip(
    String(d.descricao || d.description || d.categoria || d.title || "Lançamento"),
    72,
  );
}

/** Resumo diário 7h — vencimentos de hoje e itens em atraso (pendentes). */
export const scheduledFinanceDailyDigest = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub.schedule("0 7 * * *")
  .timeZone(TZ_BR)
  .onRun(async () => {
    const now = new Date();
    const todayYmd = ymdInTz(now, TZ_BR);

    const igrejasSnap = await db.collection("igrejas").get();
    let sent = 0;

    for (const church of igrejasSnap.docs) {
      const tenantId = church.id;
      try {
        const stateRef = db
          .collection("igrejas")
          .doc(tenantId)
          .collection("internal_notif_state")
          .doc("finance_daily_digest");
        const st = await stateRef.get();
        if (String(st.data()?.lastSentYmd || "").trim() === todayYmd) continue;

        const finCol = db.collection("igrejas").doc(tenantId).collection("finance");
        let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;
        let pagarHoje = 0;
        let receberHoje = 0;
        let pagarAtraso = 0;
        let receberAtraso = 0;

        for (;;) {
          const base = finCol.orderBy(admin.firestore.FieldPath.documentId()).limit(400);
          const snap = lastDoc ? await base.startAfter(lastDoc).get() : await base.get();
          if (snap.empty) break;

          for (const doc of snap.docs) {
            const d = doc.data() as Record<string, unknown>;
            const dt = financeLancamentoDate(d);
            if (!dt) continue;
            const ymd = ymdInTz(dt, TZ_BR);
            const isToday = ymd === todayYmd;
            const isPast = ymd < todayYmd;

            if (isPendingPagamento(d)) {
              if (isToday) pagarHoje += 1;
              else if (isPast) pagarAtraso += 1;
            }
            if (isPendingRecebimento(d)) {
              if (isToday) receberHoje += 1;
              else if (isPast) receberAtraso += 1;
            }
          }

          lastDoc = snap.docs[snap.docs.length - 1];
          if (snap.docs.length < 400) break;
        }

        const total = pagarHoje + receberHoje + pagarAtraso + receberAtraso;
        if (total === 0) {
          await stateRef.set(
            { lastSentYmd: todayYmd, skippedEmpty: true },
            { merge: true },
          );
          continue;
        }

        const parts: string[] = [];
        if (pagarHoje > 0) parts.push(`${pagarHoje} a pagar hoje`);
        if (receberHoje > 0) parts.push(`${receberHoje} a receber hoje`);
        if (pagarAtraso > 0) parts.push(`${pagarAtraso} a pagar em atraso`);
        if (receberAtraso > 0) parts.push(`${receberAtraso} a receber em atraso`);

        const body = clip(parts.join(" · "), 180);

        await admin.messaging().send(
          buildGyTopicMessage({
            topic: topicPushNovo(tenantId, "financeiro"),
            title: "💰 Financeiro — vencimentos",
            body,
            data: {
              type: "financeiro_vencimento_digest",
              tenantId,
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
            module: "financeiro",
          }),
        );

        await db.collection("igrejas").doc(tenantId).collection("notificacoes").add({
          type: "financeiro_vencimento_digest",
          title: "Financeiro — vencimentos",
          body,
          pagarHoje,
          receberHoje,
          pagarAtraso,
          receberAtraso,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await stateRef.set(
          { lastSentYmd: todayYmd, sentAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true },
        );
        sent += 1;
      } catch (e) {
        functions.logger.error("scheduledFinanceDailyDigest", { tenantId, e });
      }
    }

    functions.logger.info("scheduledFinanceDailyDigest done", { todayYmd, sent });
    return null;
  });

/** ~24h antes do vencimento — push item a item (deduplicado por doc). */
export const scheduledFinanceVencimento24h = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .pubsub.schedule("every 10 minutes")
  .timeZone(TZ_BR)
  .onRun(async () => {
    const now = Date.now();
    const horizon = now + 50 * 60 * 60 * 1000;

    const igrejasSnap = await db.collection("igrejas").get();
    let sentPay = 0;
    let sentRec = 0;

    for (const church of igrejasSnap.docs) {
      const tenantId = church.id;
      const finCol = db.collection("igrejas").doc(tenantId).collection("finance");

      let q: admin.firestore.QuerySnapshot;
      try {
        q = await finCol
          .where("date", ">=", admin.firestore.Timestamp.fromMillis(now))
          .where("date", "<=", admin.firestore.Timestamp.fromMillis(horizon))
          .get();
      } catch (e) {
        functions.logger.warn("financeVencimento24h query", { tenantId, e });
        continue;
      }

      for (const doc of q.docs) {
        const d = doc.data() as Record<string, unknown>;
        const ts = d.date as admin.firestore.Timestamp | undefined;
        if (!ts || typeof ts.toMillis !== "function") continue;
        const diffMs = ts.toMillis() - now;
        if (diffMs <= 0) continue;
        if (diffMs < MS_24H - WINDOW_MS || diffMs > MS_24H + WINDOW_MS) continue;

        const titulo = lancamentoTitulo(d);
        const isPay = isPendingPagamento(d);
        const isRec = isPendingRecebimento(d);
        if (!isPay && !isRec) continue;

        const sentField = isPay ? "pushVencimento24hPagarSentAt" : "pushVencimento24hReceberSentAt";
        if (d[sentField]) continue;

        try {
          await admin.messaging().send(
            buildGyTopicMessage({
              topic: topicPushNovo(tenantId, "financeiro"),
              title: isPay ? "💸 Conta a pagar — 24h" : "💵 Conta a receber — 24h",
              body: clip(`${titulo} vence amanhã.`, 160),
              data: {
                type: "financeiro_vencimento_24h",
                tenantId,
                financeId: doc.id,
                kind: isPay ? "pagar" : "receber",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
              module: "financeiro",
            }),
          );
          await doc.ref.update({
            [sentField]: admin.firestore.FieldValue.serverTimestamp(),
          });
          if (isPay) sentPay += 1;
          else sentRec += 1;
        } catch (e) {
          functions.logger.error("financeVencimento24h FCM", { tenantId, id: doc.id, e });
        }
      }
    }

    functions.logger.info("scheduledFinanceVencimento24h done", { sentPay, sentRec });
    return null;
  });
