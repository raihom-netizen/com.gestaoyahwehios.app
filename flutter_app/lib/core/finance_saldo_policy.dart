import 'package:cloud_firestore/cloud_firestore.dart';

/// Regras para lançamentos financeiros entrarem no **saldo das contas** e nos totais “efetivados”.
///
/// - **Transferência**: sempre movimenta saldo (valor já saiu de uma conta e entrou na outra).
/// - **Receita** (`entrada`): só após `recebimentoConfirmado == true`. Ausente = legado → conta como recebido.
/// - **Despesa** (`saida`): só após `pagamentoConfirmado == true`. Ausente = legado → conta como pago.
String _financeTipoLower(Map<String, dynamic> data) =>
    (data['type'] ?? data['tipo'] ?? '').toString().toLowerCase();

/// Receita registrada mas ainda **não confirmada** como recebida (`recebimentoConfirmado == false`).
bool financeLancamentoPendenteRecebimento(Map<String, dynamic> data) {
  final tipo = _financeTipoLower(data);
  if (tipo == 'transferencia') return false;
  if (tipo.contains('entrada') || tipo.contains('receita')) {
    return data['recebimentoConfirmado'] == false;
  }
  return false;
}

/// Despesa registrada mas ainda **não confirmada** como paga (`pagamentoConfirmado == false`).
bool financeLancamentoPendentePagamento(Map<String, dynamic> data) {
  final tipo = _financeTipoLower(data);
  if (tipo == 'transferencia') return false;
  if (tipo.contains('saida') || tipo.contains('despesa')) {
    return data['pagamentoConfirmado'] == false;
  }
  return false;
}

bool financeLancamentoEfetivadoParaSaldo(Map<String, dynamic> data) {
  final tipo = _financeTipoLower(data);
  if (tipo == 'transferencia') return true;

  final isEntrada =
      tipo.contains('entrada') || tipo.contains('receita');
  if (isEntrada) {
    if (data['recebimentoConfirmado'] == false) return false;
    return true;
  }

  final isSaida =
      tipo.contains('saida') || tipo.contains('despesa');
  if (isSaida) {
    if (data['pagamentoConfirmado'] == false) return false;
    return true;
  }

  return true;
}

/// Conta de destino de receitas: padrão `contaDestinoId`; `contaId` só legado (ex.: doações MP antigas).
String financeContaDestinoReceitaId(Map<String, dynamic> data) {
  final a = (data['contaDestinoId'] ?? '').toString().trim();
  if (a.isNotEmpty) return a;
  return (data['contaId'] ?? '').toString().trim();
}

/// Data do lançamento: `date` / `dataCompetencia` (ex.: PIX/cartão aprovado) têm prioridade sobre `createdAt`.
DateTime? financeLancamentoDate(Map<String, dynamic> data) {
  final raw =
      data['date'] ?? data['dataCompetencia'] ?? data['createdAt'];
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is Map) {
    final sec = raw['seconds'] ?? raw['_seconds'];
    if (sec != null) {
      final n = sec is num ? sec.toInt() : int.tryParse(sec.toString());
      if (n != null) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
    }
  }
  return DateTime.tryParse(raw.toString());
}

double financeParseValorBr(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0;
}

/// Saldo de cada conta considerando lançamentos **efetivados** com data ≤ [ateInclusive]
/// (saldo acumulado até o fim do período — arrasta saldos anteriores automaticamente).
Map<String, double> financeSaldoPorContaAteInclusive({
  required Set<String> contaIdsAtivas,
  required Iterable<Map<String, dynamic>> lancamentos,
  required DateTime ateInclusive,
}) {
  final saldoPorConta = {for (final id in contaIdsAtivas) id: 0.0};
  for (final data in lancamentos) {
    final dt = financeLancamentoDate(data);
    if (dt == null) continue;
    if (dt.isAfter(ateInclusive)) continue;
    if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
    final tipo =
        (data['type'] ?? data['tipo'] ?? '').toString().toLowerCase();
    final valor = financeParseValorBr(data['amount'] ?? data['valor']);
    if (tipo == 'transferencia') {
      final origemId = (data['contaOrigemId'] ?? '').toString();
      final destinoId = (data['contaDestinoId'] ?? '').toString();
      if (destinoId.isNotEmpty && saldoPorConta.containsKey(destinoId)) {
        saldoPorConta[destinoId] =
            (saldoPorConta[destinoId] ?? 0) + valor;
      }
      if (origemId.isNotEmpty && saldoPorConta.containsKey(origemId)) {
        saldoPorConta[origemId] = (saldoPorConta[origemId] ?? 0) - valor;
      }
      continue;
    }
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      final destinoId = financeContaDestinoReceitaId(data);
      if (destinoId.isNotEmpty && saldoPorConta.containsKey(destinoId)) {
        saldoPorConta[destinoId] =
            (saldoPorConta[destinoId] ?? 0) + valor;
      }
    } else {
      final origemId = (data['contaOrigemId'] ?? '').toString();
      if (origemId.isNotEmpty && saldoPorConta.containsKey(origemId)) {
        saldoPorConta[origemId] =
            (saldoPorConta[origemId] ?? 0) - valor;
      }
    }
  }
  return saldoPorConta;
}
