import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Página de resultados Firestore com cursor (`startAfterDocument`).
class FirestoreCursorPage<T> {
  const FirestoreCursorPage({
    required this.items,
    this.lastDocument,
    this.hasMore = false,
  });

  final List<T> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

/// Paginação global reutilizável (avisos, eventos, membros, site, feed).
abstract final class FirestoreCursorPagination {
  FirestoreCursorPagination._();

  static Query<Map<String, dynamic>> applyCursor(
    Query<Map<String, dynamic>> query,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  ) {
    if (startAfter != null) {
      return query.startAfterDocument(startAfter);
    }
    return query;
  }

  /// Uma página de documentos; [pageSize] usa [YahwehPerformanceV4.defaultPageSize] por defeito.
  static Future<FirestoreCursorPage<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchDocumentsPage({
    required Query<Map<String, dynamic>> baseQuery,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int? pageSize,
  }) async {
    final limit = pageSize ?? YahwehPerformanceV4.defaultPageSize;
    final q = applyCursor(baseQuery, startAfter).limit(limit);
    final snap = await q.get();
    final docs = snap.docs;
    return FirestoreCursorPage(
      items: docs,
      lastDocument: docs.isEmpty ? startAfter : docs.last,
      hasMore: docs.length >= limit,
    );
  }

  /// Mapeia documentos para modelos leves.
  static Future<FirestoreCursorPage<R>> fetchMappedPage<R>({
    required Query<Map<String, dynamic>> baseQuery,
    required R Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) map,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int? pageSize,
  }) async {
    final page = await fetchDocumentsPage(
      baseQuery: baseQuery,
      startAfter: startAfter,
      pageSize: pageSize,
    );
    return FirestoreCursorPage<R>(
      items: page.items.map(map).toList(growable: false),
      lastDocument: page.lastDocument,
      hasMore: page.hasMore,
    );
  }
}
