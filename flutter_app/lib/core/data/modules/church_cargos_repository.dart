import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Cargos (funções) — listar / criar / editar / excluir / vincular membros.
final class ChurchCargosRepository extends ChurchModuleRepositoryBase {
  const ChurchCargosRepository()
      : super(
          moduleLabel: 'Cargos',
          subcollection: ChurchDataPaths.cargos,
        );

  static const ChurchCargosRepository instance = ChurchCargosRepository();
}
