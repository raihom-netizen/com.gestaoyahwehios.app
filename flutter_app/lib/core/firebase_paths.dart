import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Fachada de paths Firebase (Firestore + Storage) para uso em UI/serviços.
///
/// Regra: sempre resolve [churchId] dinamicamente; nunca hardcode de tenant.
abstract final class FirebasePaths {
  FirebasePaths._();

  static String _id(String churchId) => ChurchRepository.churchId(churchId.trim());

  // --- Firestore ---
  static String igreja(String churchId) => ChurchDataPaths.churchRoot(_id(churchId));

  static String departamentos(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.departamentos);

  static String departamentoDoc(String churchId, String deptId) =>
      '${departamentos(churchId)}/${deptId.trim()}';

  static String membros(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.membros);

  static String configMercadoPago(String churchId) =>
      '${ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.config)}/mercado_pago';

  static String finance(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.financeiro);

  static String financeDoc(String churchId, String financeId) =>
      '${finance(churchId)}/${financeId.trim()}';

  static String financeLogs(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.financeLogs);

  static String financeMpNotifications(String churchId) =>
      ChurchDataPaths.subcollection(
        _id(churchId),
        ChurchDataPaths.financeMpNotifications,
      );

  // --- Storage ---
  static String storageLogoPath(String churchId) =>
      ChurchStorageLayout.churchIdentityLogoPath(_id(churchId));
}

