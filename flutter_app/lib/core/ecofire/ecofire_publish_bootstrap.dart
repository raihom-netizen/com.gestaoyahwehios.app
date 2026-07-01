import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';

/// Bootstrap EcoFire — Firebase + Storage **sempre ligados** antes de upload.
///
/// [strict]: true (default) — exige sessão Auth activa antes do `put`.
abstract final class EcoFirePublishBootstrap {
  EcoFirePublishBootstrap._();

  /// Garante app [DEFAULT] + Storage bucket + Auth antes de upload/gravação.
  static Future<void> ensureHard({
    String logLabel = 'ecofire_publish',
    bool strict = true,
  }) =>
      DirectStorageUrlPublish.ensureReady(requireAuth: strict);
}
