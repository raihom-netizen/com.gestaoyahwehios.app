import 'package:cloud_firestore/cloud_firestore.dart';

/// Resultado padronizado de leitura — Web = Android = iOS.
class ChurchDataListResult<T> {
  const ChurchDataListResult({
    required this.churchId,
    required this.collectionPath,
    required this.items,
    required this.readAt,
    this.fromCache = false,
    this.error,
  });

  final String churchId;
  final String collectionPath;
  final List<T> items;
  final DateTime readAt;
  final bool fromCache;
  final String? error;

  int get count => items.length;
  bool get ok => error == null;
}

class ChurchDataDocResult {
  const ChurchDataDocResult({
    required this.churchId,
    required this.documentPath,
    required this.data,
    required this.exists,
    required this.readAt,
    this.fromCache = false,
    this.error,
  });

  final String churchId;
  final String documentPath;
  final Map<String, dynamic> data;
  final bool exists;
  final DateTime readAt;
  final bool fromCache;
  final String? error;

  bool get ok => error == null && exists;
}

/// Conversão de snapshot Firestore → lista de docs.
ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>
    churchDataListFromSnapshot({
  required String churchId,
  required String collectionPath,
  required QuerySnapshot<Map<String, dynamic>> snap,
  String? error,
}) {
  return ChurchDataListResult(
    churchId: churchId,
    collectionPath: collectionPath,
    items: snap.docs,
    readAt: DateTime.now(),
    fromCache: snap.docs.isNotEmpty && snap.docs.first.metadata.isFromCache,
    error: error,
  );
}
