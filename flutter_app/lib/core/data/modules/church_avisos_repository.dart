import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Avisos — CRUD + até 5 imagens (compressão via pipeline de mídia).
final class ChurchAvisosRepository extends ChurchModuleRepositoryBase {
  const ChurchAvisosRepository()
      : super(
          moduleLabel: 'Avisos',
          subcollection: ChurchDataPaths.avisos,
        );

  static const ChurchAvisosRepository instance = ChurchAvisosRepository();
}
