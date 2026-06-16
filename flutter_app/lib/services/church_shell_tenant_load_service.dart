import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';

/// Bootstrap do doc `igrejas/{churchId}` ao abrir [IgrejaCleanShell].
///
/// **Sem** `snapshots()` / StreamBuilder — uma leitura `.get()` (web/mobile).
/// Reutiliza [ChurchCadastroLoadService] (cache → sessão → Firestore directo).
abstract final class ChurchShellTenantLoadService {
  ChurchShellTenantLoadService._();

  static Future<ChurchCadastroLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) =>
      ChurchCadastroLoadService.load(
        seedTenantId: seedTenantId,
        forceRefresh: forceRefresh,
      );

  static Future<ChurchCadastroLoadResult?> tryLocal({
    required String seedTenantId,
  }) =>
      ChurchCadastroLoadService.tryLocalSources(seedTenantId: seedTenantId);

  static Future<void> persistAfterLoad(ChurchCadastroLoadResult result) =>
      ChurchCadastroLoadService.persistAfterLoad(result);

  static bool isUsable(ChurchCadastroLoadResult result) =>
      result.data.isNotEmpty && result.churchId.trim().isNotEmpty;

  static bool hasSessionFor(String churchId) {
    final ctx = ChurchContextService.currentChurchId?.trim() ?? '';
    final data = ChurchContextService.currentChurchData;
    return ctx == churchId.trim() &&
        data != null &&
        data.isNotEmpty;
  }
}
