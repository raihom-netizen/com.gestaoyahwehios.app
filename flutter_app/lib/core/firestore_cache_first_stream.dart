import 'package:cloud_firestore/cloud_firestore.dart';

/// Padrão Controle Total: 1.º frame do cache local, depois stream em tempo real.
Stream<List<T>> firestoreCacheFirstList<T>({
  required Query<Map<String, dynamic>> query,
  required T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) mapDoc,
}) async* {
  try {
    final cached = await query.get(const GetOptions(source: Source.cache));
    if (cached.docs.isNotEmpty) {
      yield cached.docs.map(mapDoc).toList();
    }
  } catch (_) {}
  yield* query.snapshots().map((snap) => snap.docs.map(mapDoc).toList());
}
