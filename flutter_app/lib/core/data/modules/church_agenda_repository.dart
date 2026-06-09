import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

final class ChurchAgendaRepository extends ChurchModuleRepositoryBase {
  const ChurchAgendaRepository()
      : super(moduleLabel: 'Agenda', subcollection: ChurchDataPaths.agenda);

  static const ChurchAgendaRepository instance = ChurchAgendaRepository();
}
