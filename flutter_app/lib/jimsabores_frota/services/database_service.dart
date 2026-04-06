import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/jimsabores_frota/core/frota_firestore_paths.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Lógica de Abastecimento
  Future<void> salvarAbastecimento(Map<String, dynamic> dados) async {
    await FrotaFirestorePaths.abastecimentos().add({
      ...dados,
      'data_hora': FieldValue.serverTimestamp(),
    });
  }

  // Cadastro de Veículo com Frota Automática
  Future<void> cadastrarVeiculo(String placa, String desc, String obs) async {
    var snap = await FrotaFirestorePaths.veiculos().get();
    String proxFrota = (snap.docs.length + 1).toString().padLeft(3, '0');
    await FrotaFirestorePaths.veiculos().add({
      'frota': proxFrota,
      'placa': placa.toUpperCase(),
      'descricao': desc,
      'observacao': obs,
    });
  }
}
