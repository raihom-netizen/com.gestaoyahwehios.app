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

  /// Espera uploads em segundo plano — por defeito **máx. 2s** (Firestore não pode esperar 40s).
  static Future<void> drainInFlight(
    int Function() inFlightCount, {
    Duration maxWait = const Duration(seconds: 2),
  }) async {
    if (inFlightCount() <= 0) return;
    final maxTicks = (maxWait.inMilliseconds / 125).ceil().clamp(1, 320);
    var ticks = 0;
    while (inFlightCount() > 0 && ticks < maxTicks) {
      await Future<void>.delayed(const Duration(milliseconds: 125));
      ticks++;
    }
  }
}
