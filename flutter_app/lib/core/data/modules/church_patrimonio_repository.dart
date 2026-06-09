import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

final class ChurchPatrimonioRepository extends ChurchModuleRepositoryBase {
  const ChurchPatrimonioRepository()
      : super(moduleLabel: 'Patrimônio', subcollection: ChurchDataPaths.patrimonio);

  static const ChurchPatrimonioRepository instance = ChurchPatrimonioRepository();
}
