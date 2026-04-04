import 'package:cloud_firestore/cloud_firestore.dart';

class JimsaboresDB {
  final _db = FirebaseFirestore.instance;

  // Lógica de gravação para motoristas
  Future<void> registrarAbastecimento(Map<String, dynamic> dados) async {
    await _db.collection('abastecimentos').add({
      ...dados,
      'status': 'pendente',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
