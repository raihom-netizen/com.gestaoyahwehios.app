import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Resolve caminho completo `igrejas/.../doc` → [DocumentReference].
abstract final class OfflineFirestorePath {
  OfflineFirestorePath._();

  static DocumentReference<Map<String, dynamic>> document(String fullPath) {
    final parts = fullPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2 || parts.length.isOdd) {
      throw ArgumentError('Caminho Firestore inválido: $fullPath');
    }
    DocumentReference<Map<String, dynamic>> ref = firebaseDefaultFirestore
        .collection(parts[0])
        .doc(parts[1]);
    for (var i = 2; i + 1 < parts.length; i += 2) {
      ref = ref.collection(parts[i]).doc(parts[i + 1]);
    }
    return ref;
  }
}
