import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

/// Financeiro — receitas, despesas, lançamentos em `igrejas/{id}/finance`.
final class ChurchFinanceiroRepository extends ChurchModuleRepositoryBase {
  const ChurchFinanceiroRepository()
      : super(
          moduleLabel: 'Financeiro',
          subcollection: ChurchDataPaths.financeiro,
        );

  static const ChurchFinanceiroRepository instance = ChurchFinanceiroRepository();
}
