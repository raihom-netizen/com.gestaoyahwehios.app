/// Busca de utilizadores no painel master/admin (lista 360°, contagem, telemetria).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

final RegExp _kAdminCompleteEmailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

/// Utilizador real: documento com e-mail completo (não fantasma).
bool adminUserHasCompleteEmail(Map<String, dynamic> data) {
  final email = (data['email'] ?? data['EMAIL'] ?? '').toString().trim().toLowerCase();
  if (email.isEmpty) return false;
  return _kAdminCompleteEmailRe.hasMatch(email);
}

/// Consulta base: só documentos com campo `email` preenchido (exclui fantasmas).
Query<Map<String, dynamic>> adminUsersWithEmailQuery(
  CollectionReference<Map<String, dynamic>> col,
) {
  return col.where('email', isGreaterThan: '');
}

/// Só atualiza `users/{uid}` se o perfil já existir com e-mail completo (evita fantasma).
Future<bool> patchUsersDocIfIdentified({
  required FirebaseFirestore db,
  required String uid,
  required Map<String, dynamic> patch,
}) async {
  final id = uid.trim();
  if (id.isEmpty) return false;
  final ref = db.collection('users').doc(id);
  final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
  if (!snap.exists) return false;
  if (!adminUserHasCompleteEmail(snap.data() ?? const {})) return false;
  await ref.set(
    {
      ...patch,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
  return true;
}

String adminUserDisplayName(Map<String, dynamic> data) {
  final name = (data['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final nome = (data['nome'] ?? '').toString().trim();
  if (nome.isNotEmpty) return nome;
  return (data['displayName'] ?? '').toString().trim();
}
