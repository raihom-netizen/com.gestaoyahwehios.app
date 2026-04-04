import 'package:cloud_firestore/cloud_firestore.dart';

class UserRepository {
  UserRepository({
    FirebaseFirestore? firestore,
    required this.tenantId,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final String tenantId;

  CollectionReference<Map<String, dynamic>> get _usersIndex =>
      _db.collection('igrejas').doc(tenantId).collection('usersIndex');

  DocumentReference<Map<String, dynamic>> userDocByCpf(String cpf) =>
      _usersIndex.doc(cpf);

  // ========= Helpers =========

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    if (v is num) return v == 1;
    return false;
  }

  // ========= Lookups =========

  /// Busca dados do usuário pelo CPF (docId = CPF).
  Future<Map<String, dynamic>?> getUserByCpf(String cpfDigits) async {
    final doc = await userDocByCpf(cpfDigits).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  /// Busca e-mail real pelo CPF.
  Future<String?> getEmailByCpf(String cpfDigits) async {
    final data = await getUserByCpf(cpfDigits);
    if (data == null) return null;
    final email = (data['email'] ?? '').toString().trim();
    return email.isEmpty ? null : email;
  }

  /// Verifica se usuário está ativo (aceita bool / "true" / 1).
  Future<bool> isActiveByCpf(String cpfDigits) async {
    final data = await getUserByCpf(cpfDigits);
    if (data == null) return false;
    return _asBool(data['active']);
  }

  /// MUST_CHANGE_PASS (se você usar esse campo no usersIndex).
  Future<bool> mustChangePassByCpf(String cpfDigits) async {
    final data = await getUserByCpf(cpfDigits);
    if (data == null) return false;
    return _asBool(data['mustChangePass']);
  }

  /// 🔥 Importante pro AuthGate: achar CPF pelo email logado (quando já está autenticado).
  Future<String?> getCpfByEmail(String email) async {
    final q = await _usersIndex.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id; // docId = CPF
  }

  /// (Opcional) ler usuário pelo email (para checar active/mustChangePass depois do login)
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final q = await _usersIndex.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.data();
  }
}
