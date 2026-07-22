import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart' show Characters, StringCharacters;

/// Grava nome/sobrenome exibidos no painel — sincroniza `users/{uid}` e Auth.
/// Padrão Controle Total: nome editável direto na barra superior.
class UserDisplayNameService {
  UserDisplayNameService._();
  static final UserDisplayNameService instance = UserDisplayNameService._();

  static const int maxPartLength = 40;

  static String sanitizeNamePart(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    if (t.characters.length > maxPartLength) {
      t = t.characters.take(maxPartLength).string;
    }
    return t;
  }

  static String composeParts(String firstName, String lastName) {
    final fn = sanitizeNamePart(firstName);
    final ln = sanitizeNamePart(lastName);
    return [fn, ln].where((p) => p.isNotEmpty).join(' ').trim();
  }

  /// Divide o nome atual em (nome, sobrenome) para pré-preencher o formulário.
  static (String, String) splitDisplayName(String full) {
    final t = full.trim();
    if (t.isEmpty) return ('', '');
    final idx = t.indexOf(' ');
    if (idx <= 0) return (t, '');
    return (t.substring(0, idx).trim(), t.substring(idx + 1).trim());
  }

  Future<String> saveDisplayNameParts({
    required String firstName,
    required String lastName,
  }) async {
    final fn = sanitizeNamePart(firstName);
    final ln = sanitizeNamePart(lastName);
    final full = composeParts(fn, ln);
    if (full.isEmpty) {
      throw ArgumentError('Informe ao menos o nome ou sobrenome.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sessão expirada. Entre novamente.');
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'displayFirstName': fn,
        'displayLastName': ln,
        'name': full,
        'displayName': full,
        'nome': full,
        'displayNameUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    try {
      await user.updateDisplayName(full);
      await user.reload();
    } catch (_) {}

    return full;
  }
}
