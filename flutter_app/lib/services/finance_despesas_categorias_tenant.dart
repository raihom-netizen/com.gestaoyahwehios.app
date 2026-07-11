import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

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

Future<void> _seedCategoriasDespesaFirestore(
  CollectionReference<Map<String, dynamic>> col,
) async {
  try {
    final probe = await col.limit(1).get();
    if (probe.docs.isNotEmpty) return;
    for (final nome in kCategoriasDespesaPadrao) {
      await col.add(
          {'nome': nome, 'ordem': kCategoriasDespesaPadrao.indexOf(nome)});
    }
  } catch (_) {}
}

/// Categorias de despesa do tenant, com criação dos documentos padrão se a coleção estiver vazia.
Future<List<String>> getCategoriasDespesaForTenant(String tenantId) async {
  try {
    final op = ChurchRepository.churchId(tenantId.trim());
    if (op.isEmpty) return List<String>.from(kCategoriasDespesaPadrao);
    final col = ChurchUiCollections.churchDoc(op)
        .collection('categorias_despesas');
    final snap = await col.orderBy('nome').get();
    if (snap.docs.isEmpty) {
      unawaited(_seedCategoriasDespesaFirestore(col));
      return List<String>.from(kCategoriasDespesaPadrao);
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
