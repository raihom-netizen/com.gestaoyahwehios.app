import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Departamentos — listar / criar / editar / excluir / líder / membros.
final class ChurchDepartamentosRepository extends ChurchModuleRepositoryBase {
  const ChurchDepartamentosRepository()
      : super(
          moduleLabel: 'Departamentos',
          subcollection: ChurchDataPaths.departamentos,
        );

  static const ChurchDepartamentosRepository instance =
      ChurchDepartamentosRepository();
}
