import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

final class ChurchDoacoesRepository extends ChurchModuleRepositoryBase {
  const ChurchDoacoesRepository()
      : super(moduleLabel: 'Doações', subcollection: ChurchDataPaths.doacoes);

  static const ChurchDoacoesRepository instance = ChurchDoacoesRepository();
}
