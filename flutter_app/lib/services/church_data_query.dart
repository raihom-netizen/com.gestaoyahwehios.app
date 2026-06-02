import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_list_limits.dart';
import 'package:gestao_yahweh/services/church_data_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Consultas Firestore com `orderBy` + `limit` (evita `.get()` / streams ilimitados).
abstract final class ChurchDataQuery {
  ChurchDataQuery._();

  static const String defaultOrderField = 'createdAt';

  static Query<Map<String, dynamic>> recentOrdered(
    CollectionReference<Map<String, dynamic>> collection, {
    String orderField = defaultOrderField,
    bool descending = true,
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) {
    return collection.orderBy(orderField, descending: descending).limit(limit);
  }

  /// `get()` pontual com limite (cache → rede).
  static Future<QuerySnapshot<Map<String, dynamic>>> getRecentPage({
    required CollectionReference<Map<String, dynamic>> collection,
    String orderField = defaultOrderField,
    bool descending = true,
    int limit = ChurchTenantListLimits.defaultPageSize,
    String? cacheKey,
  }) {
    final q = recentOrdered(
      collection,
      orderField: orderField,
      descending: descending,
      limit: limit,
    );
    if (cacheKey != null && cacheKey.trim().isNotEmpty) {
      return FirestoreReadResilience.getQuery(q, cacheKey: cacheKey.trim());
    }
    return q.get();
  }

  /// Stream limitado (lista inicial — nunca `snapshots()` sem `limit`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentPage({
    required CollectionReference<Map<String, dynamic>> collection,
    String orderField = defaultOrderField,
    bool descending = true,
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) {
    return recentOrdered(
      collection,
      orderField: orderField,
      descending: descending,
      limit: limit,
    ).snapshots();
  }

  /// Stream resiliente (broadcast + último bom) para painel / mural.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentPageResilient({
    required String tenantId,
    required String collection,
    String orderField = defaultOrderField,
    bool descending = true,
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) {
    final col = ChurchDataService.tenantCollection(tenantId, collection);
    return FirestoreStreamUtils.resilientQuery(
      watchRecentPage(
        collection: col,
        orderField: orderField,
        descending: descending,
        limit: limit,
      ),
    );
  }
}
