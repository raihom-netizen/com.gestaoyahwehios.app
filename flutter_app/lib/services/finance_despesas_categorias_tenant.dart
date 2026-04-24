import 'package:cloud_firestore/cloud_firestore.dart';

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
  final col = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('categorias_despesas');
  var snap = await col.orderBy('nome').get();
  if (snap.docs.isEmpty) {
    for (final nome in kCategoriasDespesaPadrao) {
      await col
          .add({'nome': nome, 'ordem': kCategoriasDespesaPadrao.indexOf(nome)});
    }
    snap = await col.orderBy('nome').get();
  }
  final nomes = snap.docs
      .map((d) => (d.data()['nome'] ?? '').toString())
      .where((s) => s.isNotEmpty);
  final seen = <String>{};
  return nomes.where((n) => seen.add(n)).toList();
}
