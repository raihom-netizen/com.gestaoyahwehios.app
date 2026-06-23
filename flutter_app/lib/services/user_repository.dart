import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

class UserRepository {
  UserRepository({
    FirebaseFirestore? firestore,
    required this.tenantId,
  }) : _db = firestore ?? firebaseDefaultFirestore;

  final FirebaseFirestore _db;
  final String tenantId;

  Future<CollectionReference<Map<String, dynamic>>> _usersIndex() async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId);
    return ChurchOperationalPaths.churchDoc(op).collection('usersIndex');
  }

  Future<DocumentReference<Map<String, dynamic>>> userDocByCpf(String cpf) async =>
      (await _usersIndex()).doc(cpf);

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
    final doc = await (await userDocByCpf(cpfDigits)).get();
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
    final col = await _usersIndex();
    final q = await col.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id; // docId = CPF
  }

  /// (Opcional) ler usuário pelo email (para checar active/mustChangePass depois do login)
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final col = await _usersIndex();
    final q = await col.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.data();
  }
}
