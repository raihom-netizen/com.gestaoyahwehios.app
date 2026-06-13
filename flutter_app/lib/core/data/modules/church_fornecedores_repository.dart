import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Fornecedores — cadastros em `igrejas/{id}/fornecedores`.
final class ChurchFornecedoresRepository extends ChurchModuleRepositoryBase {
  const ChurchFornecedoresRepository()
      : super(
          moduleLabel: 'Fornecedores',
          subcollection: ChurchDataPaths.fornecedores,
        );

  static const ChurchFornecedoresRepository instance =
      ChurchFornecedoresRepository();

  @override
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
        module: TenantModuleKeys.fornecedores,
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
}
