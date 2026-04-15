"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.gerarReceitasRecorrentesPendentesForTenant = gerarReceitasRecorrentesPendentesForTenant;
const admin = __importStar(require("firebase-admin"));
function competenciaFinanceira(d) {
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}`;
}
function idLancamentoRecorrencia(receitaRecorrenteId, competencia) {
    return `rec_${receitaRecorrenteId}_${competencia}`;
}
function toDateMaybe(v) {
    if (v == null)
        return undefined;
    if (v instanceof admin.firestore.Timestamp)
        return v.toDate();
    const any = v;
    if (typeof any.toDate === "function")
        return any.toDate();
    return undefined;
}
/**
 * Espelha `gerarReceitasRecorrentesPendentes` em
 * `flutter_app/lib/services/receitas_recorrentes_geracao_service.dart` — idempotente por docId fixo.
 */
async function gerarReceitasRecorrentesPendentesForTenant(tenantId) {
    const db = admin.firestore();
    const ig = db.collection("igrejas").doc(tenantId);
    const recSnap = await ig.collection("receitas_recorrentes").get();
    const fin = ig.collection("finance");
    const now = new Date();
    const mesAtual = new Date(now.getFullYear(), now.getMonth(), 1);
    let criados = 0;
    for (const rd of recSnap.docs) {
        const m = rd.data();
        if (m.ativo === false)
            continue;
        const memberDocId = String(m.memberDocId ?? "").trim();
        const memberNome = String(m.memberNome ?? "").trim();
        const memberTelefone = String(m.memberTelefone ?? "").trim();
        if (!memberDocId)
            continue;
        const valor = m.valor ?? 0;
        const v = typeof valor === "number" ? valor : parseFloat(String(valor)) || 0;
        if (v <= 0)
            continue;
        const categoria = String(m.categoria ?? "Dízimos").trim();
        const contaDestinoId = String(m.contaDestinoId ?? "").trim();
        const contaDestinoNome = String(m.contaDestinoNome ?? "").trim();
        const di = toDateMaybe(m.dataInicio);
        const df = toDateMaybe(m.dataFim);
        const indeterminado = m.indeterminado === true;
        if (!di)
            continue;
        const inicioM = new Date(di.getFullYear(), di.getMonth(), 1);
        let fimLoop;
        if (indeterminado || df == null) {
            fimLoop = mesAtual;
        }
        else {
            const dfM = new Date(df.getFullYear(), df.getMonth(), 1);
            fimLoop = dfM.getTime() > mesAtual.getTime() ? mesAtual : dfM;
        }
        if (inicioM.getTime() > fimLoop.getTime())
            continue;
        let cursor = new Date(inicioM);
        while (cursor.getTime() <= fimLoop.getTime()) {
            const comp = competenciaFinanceira(cursor);
            const docId = idLancamentoRecorrencia(rd.id, comp);
            const ref = fin.doc(docId);
            const exist = await ref.get();
            if (!exist.exists) {
                const labelMes = `${String(cursor.getMonth() + 1).padStart(2, "0")}/${cursor.getFullYear()}`;
                const payload = {
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
                if (memberTelefone)
                    payload.memberTelefone = memberTelefone;
                if (contaDestinoId)
                    payload.contaDestinoId = contaDestinoId;
                if (contaDestinoNome)
                    payload.contaDestinoNome = contaDestinoNome;
                await ref.set(payload);
                criados++;
            }
            cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
        }
    }
    return criados;
}
//# sourceMappingURL=receitasRecorrentesScheduled.js.map