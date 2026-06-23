import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Categorias de despesa padrão (seed). Alinhado ao módulo financeiro.
const kCategoriasDespesaPadrao = [
  'Água',
  'Ajuda Social',
  'Energia Elétrica',
  'Eventos',
  'Impostos',
  'Internet',
  'Investimentos em Mídia',
  'Manutenção',
  'Material de Limpeza',
  'Oferta Missionária',
  'Pagamento de Obreiros',
  'Prebenda',
  'Salários',
  'Material de Escritório',
  'Transporte',
  'Alimentação',
  'Outros',
];

/// Categorias de despesa do tenant, com criação dos documentos padrão se a coleção estiver vazia.
Future<List<String>> getCategoriasDespesaForTenant(String tenantId) async {
  try {
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    if (op.isEmpty) return List<String>.from(kCategoriasDespesaPadrao);
    final col = ChurchOperationalPaths.churchDoc(op)
        .collection('categorias_despesas');
    var snap = await col.orderBy('nome').get();
    if (snap.docs.isEmpty) {
      for (final nome in kCategoriasDespesaPadrao) {
        await col.add(
            {'nome': nome, 'ordem': kCategoriasDespesaPadrao.indexOf(nome)});
      }
      snap = await col.orderBy('nome').get();
    }
    final nomes = snap.docs
        .map((d) => (d.data()['nome'] ?? '').toString())
        .where((s) => s.isNotEmpty);
    final seen = <String>{};
    final list = nomes.where((n) => seen.add(n)).toList();
    return list.isEmpty ? List<String>.from(kCategoriasDespesaPadrao) : list;
  } catch (_) {
    return List<String>.from(kCategoriasDespesaPadrao);
  }
}
