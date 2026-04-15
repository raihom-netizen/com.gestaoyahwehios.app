import * as admin from "firebase-admin";

function competenciaFinanceira(d: Date): string {
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}`;
}

function idLancamentoRecorrencia(receitaRecorrenteId: string, competencia: string): string {
  return `rec_${receitaRecorrenteId}_${competencia}`;
}

function toDateMaybe(v: unknown): Date | undefined {
  if (v == null) return undefined;
  if (v instanceof admin.firestore.Timestamp) return v.toDate();
  const any = v as { toDate?: () => Date };
  if (typeof any.toDate === "function") return any.toDate();
  return undefined;
}

/**
 * Espelha `gerarReceitasRecorrentesPendentes` em
 * `flutter_app/lib/services/receitas_recorrentes_geracao_service.dart` — idempotente por docId fixo.
 */
export async function gerarReceitasRecorrentesPendentesForTenant(tenantId: string): Promise<number> {
  const db = admin.firestore();
  const ig = db.collection("igrejas").doc(tenantId);
  const recSnap = await ig.collection("receitas_recorrentes").get();
  const fin = ig.collection("finance");
  const now = new Date();
  const mesAtual = new Date(now.getFullYear(), now.getMonth(), 1);
  let criados = 0;

  for (const rd of recSnap.docs) {
    const m = rd.data();
    if (m.ativo === false) continue;
    const memberDocId = String(m.memberDocId ?? "").trim();
    const memberNome = String(m.memberNome ?? "").trim();
    const memberTelefone = String(m.memberTelefone ?? "").trim();
    if (!memberDocId) continue;
    const valor = m.valor ?? 0;
    const v = typeof valor === "number" ? valor : parseFloat(String(valor)) || 0;
    if (v <= 0) continue;
    const categoria = String(m.categoria ?? "Dízimos").trim();
    const contaDestinoId = String(m.contaDestinoId ?? "").trim();
    const contaDestinoNome = String(m.contaDestinoNome ?? "").trim();

    const di = toDateMaybe(m.dataInicio);
    const df = toDateMaybe(m.dataFim);
    const indeterminado = m.indeterminado === true;

    if (!di) continue;

    const inicioM = new Date(di.getFullYear(), di.getMonth(), 1);

    let fimLoop: Date;
    if (indeterminado || df == null) {
      fimLoop = mesAtual;
    } else {
      const dfM = new Date(df.getFullYear(), df.getMonth(), 1);
      fimLoop = dfM.getTime() > mesAtual.getTime() ? mesAtual : dfM;
    }
    if (inicioM.getTime() > fimLoop.getTime()) continue;

    let cursor = new Date(inicioM);
    while (cursor.getTime() <= fimLoop.getTime()) {
      const comp = competenciaFinanceira(cursor);
      const docId = idLancamentoRecorrencia(rd.id, comp);
      const ref = fin.doc(docId);
      const exist = await ref.get();
      if (!exist.exists) {
        const labelMes = `${String(cursor.getMonth() + 1).padStart(2, "0")}/${cursor.getFullYear()}`;
        const payload: Record<string, unknown> = {
          type: "entrada",
          amount: v,
          categoria,
          descricao: `${categoria} — ${memberNome} (${labelMes}) · recorrente`,
          recebimentoConfirmado: false,
          pendenteConciliacaoRecorrencia: true,
          recorrenciaId: rd.id,
          competencia: comp,
          memberDocId,
          memberNome,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (memberTelefone) payload.memberTelefone = memberTelefone;
        if (contaDestinoId) payload.contaDestinoId = contaDestinoId;
        if (contaDestinoNome) payload.contaDestinoNome = contaDestinoNome;
        await ref.set(payload);
        criados++;
      }
      cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
    }
  }
  return criados;
}
