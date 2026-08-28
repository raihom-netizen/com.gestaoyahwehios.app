import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';

/// Resultado da exclusão total de uma igreja.
class MasterChurchDeleteResult {
  const MasterChurchDeleteResult({
    required this.tenantId,
    required this.storageFilesDeleted,
    required this.indexesCleaned,
  });

  final String tenantId;
  final int storageFilesDeleted;
  final List<String> indexesCleaned;
}

/// Exclusão **total** de uma igreja — Firestore, Storage e índices globais.
///
/// Corre numa Cloud Function (`deleteChurchCompletely`) e não no cliente: só o
/// Admin SDK tem `recursiveDelete` (apanha subcoleções que a app nem conhece) e
/// acesso ao bucket para apagar `igrejas/{id}/` inteiro. A exclusão que existia
/// antes corria aqui no cliente, com uma lista fixa de coleções — o que fosse
/// criado depois ficava para trás, e a mídia no Storage nunca era apagada.
abstract final class MasterChurchDeleteService {
  MasterChurchDeleteService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Apaga a igreja [tenantId]. [confirmTenantId] tem de ser igual — a função
  /// recusa se não bater, para um clique no cartão errado não levar tudo.
  static Future<MasterChurchDeleteResult> deleteChurch({
    required String tenantId,
    required String confirmTenantId,
  }) async {
    final id = tenantId.trim();
    if (id.isEmpty) {
      throw StateError('Igreja não identificada.');
    }
    final callable = _functions.httpsCallable(
      'deleteChurchCompletely',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    final res = await callable.call<Map<String, dynamic>>({
      'tenantId': id,
      'confirmTenantId': confirmTenantId.trim(),
    });
    final data = res.data;
    // A lista do master guarda cópias em memória e em SharedPreferences: sem
    // limpar as duas, a igreja apagada voltava a aparecer na abertura seguinte.
    await MasterChurchesListService.invalidateAll();
    return MasterChurchDeleteResult(
      tenantId: (data['tenantId'] ?? id).toString(),
      storageFilesDeleted:
          int.tryParse('${data['storageFilesDeleted'] ?? 0}') ?? 0,
      indexesCleaned: [
        for (final e in (data['indexesCleaned'] as List? ?? const []))
          e.toString(),
      ],
    );
  }
}
