import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Padrão Controle Total: cache local primeiro, depois stream seguro.
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
  yield* query.watchSafe().map((snap) => snap.docs.map(mapDoc).toList());
}
