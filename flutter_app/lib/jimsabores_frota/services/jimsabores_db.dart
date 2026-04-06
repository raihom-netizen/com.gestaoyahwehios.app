import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/jimsabores_frota/core/frota_firestore_paths.dart';

class JimsaboresDB {
  final _db = FirebaseFirestore.instance;

  // Lógica de gravação para motoristas
  Future<void> registrarAbastecimento(Map<String, dynamic> dados) async {
    await FrotaFirestorePaths.abastecimentos().add({
      ...dados,
      'status': 'pendente',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
