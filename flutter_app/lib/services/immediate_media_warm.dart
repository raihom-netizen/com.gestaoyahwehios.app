import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';

/// Pré-aquecimento único (Controle Total) — evita 2.º/3.º upload repetir bootstrap lento.
abstract final class ImmediateMediaWarm {
  ImmediateMediaWarm._();

  static Future<void>? _feedWarm;
  static Future<void>? _patrimonioWarm;

  static Future<void> warmFeed() {
    return _feedWarm ??= FastMediaPublishBootstrap.warmForFeedPublish()
        .timeout(const Duration(seconds: 16))
        .catchError((_) {});
  }

  static Future<void> warmPatrimonio() {
    return _patrimonioWarm ??= FastMediaPublishBootstrap.warmForPatrimonioSave()
        .timeout(const Duration(seconds: 16))
        .catchError((_) {});
  }

  /// Espera uploads em segundo plano antes de «Publicar»/«Salvar» (máx. ~40s).
  static Future<void> drainInFlight(int Function() inFlightCount) async {
    var ticks = 0;
    while (inFlightCount() > 0 && ticks < 320) {
      await Future<void>.delayed(const Duration(milliseconds: 125));
      ticks++;
    }
  }
}
