import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';

/// Base para repositórios de módulo — CRUD + listagem unificada.
abstract class ChurchModuleRepositoryBase {
  const ChurchModuleRepositoryBase({
    required this.moduleLabel,
    required this.subcollection,
  });

  final String moduleLabel;
  final String subcollection;

  String churchId([String? hint]) => ChurchFirestoreAccess.resolveChurchId(hint);

  String pathFor(String churchId) =>
      ChurchFirestoreAccess.collectionPath(churchId, subcollection);

  /// Cache Hive → rede (padrão obrigatório nas telas de módulo).
  Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      listCacheFirst({
    String? churchIdHint,
    int limit = 120,
    String? firestoreCacheKey,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) {
      return ChurchDataListResult(
        churchId: '',
        collectionPath: '',
        items: const [],
        readAt: DateTime.now(),
        error: 'churchId vazio',
      );
    }
    final cacheKey =
        firestoreCacheKey ?? 'data_${id}_${subcollection}_$limit';
    try {
      final snap = await TenantStaleWhileRevalidate.loadQuery(
        tenantId: id,
        module: subcollection,
        firestoreCacheKey: cacheKey,
        networkFetch: () => ChurchFirestoreAccess.listOnce(
          module: moduleLabel,
          churchId: id,
          subcollectionName: subcollection,
          limit: limit,
          cacheKey: cacheKey,
        ),
      );
      return churchDataListFromSnapshot(
        churchId: id,
        collectionPath: pathFor(id),
        snap: snap,
      );
    } catch (e) {
      return ChurchDataListResult(
        churchId: id,
        collectionPath: pathFor(id),
        items: const [],
        readAt: DateTime.now(),
        error: '$e',
      );
    }
  }

  Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      list({
    String? churchIdHint,
    int limit = 120,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) {
      return ChurchDataListResult(
        churchId: '',
        collectionPath: '',
        items: const [],
        readAt: DateTime.now(),
        error: 'churchId vazio',
      );
    }
    try {
      final snap = await ChurchFirestoreAccess.listOnce(
        module: moduleLabel,
        churchId: id,
        subcollectionName: subcollection,
        limit: limit,
      );
      return churchDataListFromSnapshot(
        churchId: id,
        collectionPath: pathFor(id),
        snap: snap,
      );
    } catch (e) {
      return ChurchDataListResult(
        churchId: id,
        collectionPath: pathFor(id),
        items: const [],
        readAt: DateTime.now(),
        error: '$e',
      );
    }
  }

  Future<ChurchDataDocResult> get({
    required String docId,
    String? churchIdHint,
  }) async {
    final id = churchId(churchIdHint);
    try {
      final snap = await ChurchFirestoreAccess.getDocument(
        module: moduleLabel,
        churchId: id,
        subcollectionName: subcollection,
        docId: docId,
      );
      return ChurchDataDocResult(
        churchId: id,
        documentPath: snap.reference.path,
        data: snap.data() ?? {},
        exists: snap.exists,
        readAt: DateTime.now(),
        fromCache: snap.metadata.isFromCache,
      );
    } catch (e) {
      return ChurchDataDocResult(
        churchId: id,
        documentPath: '${pathFor(id)}/$docId',
        data: const {},
        exists: false,
        readAt: DateTime.now(),
        error: '$e',
      );
    }
  }

  Future<String> create({
    required Map<String, dynamic> data,
    String? churchIdHint,
  }) async {
    final id = churchId(churchIdHint);
    final col = ChurchFirestoreAccess.collectionRef(id, subcollection);
    final ref = await col.add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update({
    required String docId,
    required Map<String, dynamic> data,
    String? churchIdHint,
    bool merge = true,
  }) async {
    await ChurchFirestoreAccess.setDocument(
      module: moduleLabel,
      churchId: churchId(churchIdHint),
      subcollectionName: subcollection,
      docId: docId,
      data: {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      merge: merge,
    );
  }

  Future<void> delete({
    required String docId,
    String? churchIdHint,
  }) async {
    await ChurchFirestoreAccess.deleteDocument(
      module: moduleLabel,
      churchId: churchId(churchIdHint),
      subcollectionName: subcollection,
      docId: docId,
    );
  }
}
