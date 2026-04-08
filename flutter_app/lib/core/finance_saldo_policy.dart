/// Regras para lançamentos financeiros entrarem no **saldo das contas** e nos totais “efetivados”.
///
/// - **Transferência**: sempre movimenta saldo (valor já saiu de uma conta e entrou na outra).
/// - **Receita** (`entrada`): só após `recebimentoConfirmado == true`. Ausente = legado → conta como recebido.
/// - **Despesa** (`saida`): só após `pagamentoConfirmado == true`. Ausente = legado → conta como pago.
bool financeLancamentoEfetivadoParaSaldo(Map<String, dynamic> data) {
  final tipo = (data['type'] ?? '').toString().toLowerCase();
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
