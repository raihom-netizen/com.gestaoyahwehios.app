import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firestore_cursor_pagination.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Feed do site público com paginação global (20 por vez, `startAfterDocument`).
abstract final class ChurchPublicFeedService {
  ChurchPublicFeedService._();

  static const int pageSize = YahwehPerformanceV4.publicFeedPageSize;

  static Future<FirestoreCursorPage<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchAvisosPage({
    required String tenantId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final base = ChurchOperationalPaths.churchDoc(op)
        .collection(ChurchTenantPostsCollections.avisos)
        .where('publicSite', isEqualTo: true)
        .orderBy('createdAt', descending: true);
    return FirestoreCursorPagination.fetchDocumentsPage(
      baseQuery: base,
      startAfter: startAfter,
      pageSize: pageSize,
    );
  }

  static Future<FirestoreCursorPage<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchUpcomingEventosPage({
    required String tenantId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final base = ChurchOperationalPaths.churchDoc(op)
        .collection(ChurchTenantPostsCollections.eventos)
        .where('type', isEqualTo: 'evento')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('startAt', descending: false);
    return FirestoreCursorPagination.fetchDocumentsPage(
      baseQuery: base,
      startAfter: startAfter,
      pageSize: YahwehPerformanceV4.upcomingEventsLimit,
    );
  }
}
