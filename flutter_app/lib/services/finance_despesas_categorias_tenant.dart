import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Categorias de despesa padr├úo (seed). Alinhado ao m├│dulo financeiro.
const kCategoriasDespesaPadrao = [
  '├ügua',
  'Ajuda Social',
  'Energia El├®trica',
  'Eventos',
  'Impostos',
  'Internet',
  'Investimentos em M├¡dia',
  'Manuten├º├úo',
  'Material de Limpeza',
  'Oferta Mission├íria',
  'Pagamento de Obreiros',
  'Prebenda',
  'Sal├írios',
  'Material de Escrit├│rio',
  'Transporte',
  'Alimenta├º├úo',
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

/// Categorias de despesa do tenant, com cria├º├úo dos documentos padr├úo se a cole├º├úo estiver vazia.
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
