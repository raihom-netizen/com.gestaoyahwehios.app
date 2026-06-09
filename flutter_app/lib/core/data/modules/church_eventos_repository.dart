import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Eventos — CRUD + mídia (até 5 fotos, 1 vídeo) via serviços de publish.
final class ChurchEventosRepository extends ChurchModuleRepositoryBase {
  const ChurchEventosRepository()
      : super(
          moduleLabel: 'Eventos',
          subcollection: ChurchDataPaths.eventos,
        );

  static const ChurchEventosRepository instance = ChurchEventosRepository();

  /// Fallback legado `noticias` até migração total.
  Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      listWithLegacy({
    String? churchIdHint,
    int limit = 80,
  }) async {
    final primary = await list(churchIdHint: churchIdHint, limit: limit);
    if (primary.count > 0) return primary;
    final id = churchId(churchIdHint);
    if (id.isEmpty) return primary;
    try {
      final legacy = await ChurchFirestoreAccess.listOnce(
        module: 'Eventos-legado',
        churchId: id,
        subcollectionName: ChurchDataPaths.legacyEventosNoticias,
        limit: limit,
        cacheKey: 'data_${id}_legacy_noticias_$limit',
      );
      return churchDataListFromSnapshot(
        churchId: id,
        collectionPath: ChurchFirestoreAccess.collectionPath(
          id,
          ChurchDataPaths.legacyEventosNoticias,
        ),
        snap: legacy,
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
