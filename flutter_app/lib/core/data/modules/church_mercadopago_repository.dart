import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';

final class ChurchMercadoPagoRepository extends ChurchModuleRepositoryBase {
  const ChurchMercadoPagoRepository()
      : super(moduleLabel: 'Mercado Pago', subcollection: ChurchDataPaths.mercadopago);

  static const ChurchMercadoPagoRepository instance = ChurchMercadoPagoRepository();
}
