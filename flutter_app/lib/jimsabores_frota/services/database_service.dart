import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Lógica de Abastecimento
  Future<void> salvarAbastecimento(Map<String, dynamic> dados) async {
    await _db.collection('abastecimentos').add({
      ...dados,
      'data_hora': FieldValue.serverTimestamp(),
    });
  }

  // Cadastro de Veículo com Frota Automática
  Future<void> cadastrarVeiculo(String placa, String desc, String obs) async {
    var snap = await _db.collection('veiculos').get();
    String proxFrota = (snap.docs.length + 1).toString().padLeft(3, '0');
    await _db.collection('veiculos').add({
      'frota': proxFrota,
      'placa': placa.toUpperCase(),
      'descricao': desc,
      'observacao': obs,
    });
  }
}
