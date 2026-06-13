import 'package:gestao_yahweh/services/finance_despesas_categorias_tenant.dart';

/// Infere `entrada` / `saida` / `transferencia` quando `type`/`tipo` estão ausentes (legado).
String financeInferTipo(Map<String, dynamic> data) {
  final explicit = (data['type'] ?? data['tipo'] ?? '').toString().trim().toLowerCase();
  if (explicit.isNotEmpty) {
    if (explicit == 'transferencia' || explicit == 'transferência') {
      return 'transferencia';
    }
    if (explicit.contains('entrada') ||
        explicit.contains('receita') ||
        explicit == 'income') {
      return 'entrada';
    }
    if (explicit.contains('saida') ||
        explicit.contains('saída') ||
        explicit.contains('despesa') ||
        explicit == 'expense') {
      return 'saida';
    }
    return explicit;
  }

  final origem = (data['contaOrigemId'] ?? '').toString().trim();
  final destino =
      (data['contaDestinoId'] ?? data['contaId'] ?? '').toString().trim();
  if (origem.isNotEmpty && destino.isNotEmpty) return 'transferencia';
  if (origem.isNotEmpty && destino.isEmpty) return 'saida';
  if (destino.isNotEmpty && origem.isEmpty) return 'entrada';

  final cat = (data['categoria'] ?? '').toString().trim().toLowerCase();
  if (cat.isNotEmpty) {
    for (final d in kCategoriasDespesaPadrao) {
      if (d.toLowerCase() == cat) return 'saida';
    }
    if (cat.contains('despesa') ||
        cat.contains('pagamento') ||
        cat.contains('alimentação') ||
        cat.contains('alimentacao') ||
        cat.contains('água') ||
        cat.contains('agua') ||
        cat.contains('luz') ||
        cat.contains('internet') ||
        cat.contains('salário') ||
        cat.contains('salario') ||
        cat.contains('imposto') ||
        cat.contains('manutenção') ||
        cat.contains('manutencao')) {
      return 'saida';
    }
    if (cat.contains('oferta') ||
        cat.contains('dízim') ||
        cat.contains('dizim') ||
        cat.contains('doação') ||
        cat.contains('doacao') ||
        cat.contains('receita') ||
        cat.contains('dízimo') ||
        cat.contains('dizimo')) {
      return 'entrada';
    }
  }

  final docId = (data['id'] ?? '').toString().toLowerCase();
  if (docId.startsWith('mp_donation')) return 'entrada';

  return 'entrada';
}

bool financeIsEntrada(Map<String, dynamic> data) {
  final t = financeInferTipo(data);
  return t.contains('entrada') || t.contains('receita');
}

bool financeIsSaida(Map<String, dynamic> data) {
  final t = financeInferTipo(data);
  return t.contains('saida') ||
      t.contains('saída') ||
      t.contains('despesa');
}
