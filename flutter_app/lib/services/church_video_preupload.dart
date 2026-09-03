import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Executa o envio do vídeo e devolve o resultado (ou `null` em falha).
///
/// O tipo do resultado é livre — Eventos devolvem `VideoUploadResult`,
/// Avisos devolvem o par de paths no Storage.
typedef ChurchVideoPreuploadRunner =
    Future<Object?> Function(void Function(double progress));

/// Envio antecipado do vídeo de Avisos/Eventos.
///
/// Antes, o vídeo só começava a subir quando o utilizador tocava em
/// «Publicar» — ou seja, todo o tempo de encode + rede era espera visível na
/// barra «A publicar mídia…». O vídeo é anexado no início do formulário e o
/// utilizador ainda tem de preencher título, data e local: essa janela é
/// tempo de rede desperdiçado.
///
/// Aqui o envio arranca **no momento em que o vídeo é anexado**, para o mesmo
/// caminho definitivo no Storage (o id do post já existe antes de publicar).
/// Na publicação, [claim] devolve o que já está pronto — normalmente instantâneo.
///
/// O ficheiro é escrito num caminho determinístico por post/slot, portanto um
/// envio repetido apenas sobrescreve — nunca duplica objetos no bucket.
abstract final class ChurchVideoPreupload {
  ChurchVideoPreupload._();

  static final Map<String, _PreuploadEntry> _entries = {};

  /// Arranca o envio antecipado de [localPath].
  ///
  /// [tag] identifica o destino (igreja + post + slot): a publicação só
  /// aproveita o resultado quando o destino é exatamente o mesmo.
  /// [onAbandonedCleanup] corre quando o envio termina depois de o vídeo já ter
  /// sido removido/descartado — apaga o objeto órfão do Storage.
  static void start({
    required String localPath,
    required String tag,
    required ChurchVideoPreuploadRunner run,
    Future<void> Function()? onAbandonedCleanup,
  }) {
    final key = localPath.trim();
    if (key.isEmpty) return;
    final existing = _entries[key];
    if (existing != null && existing.tag == tag && !existing.abandoned) return;
    if (existing != null) abandon(key);

    final entry = _PreuploadEntry(
      tag: tag,
      onAbandonedCleanup: onAbandonedCleanup,
    );
    _entries[key] = entry;
    entry.future = () async {
      try {
        final result = await run(entry.report);
        entry.report(1);
        return result;
      } catch (e) {
        // Falha aqui nunca pode rebentar: a publicação repete o envio pelo
        // caminho normal e é lá que o erro chega ao utilizador.
        if (kDebugMode) debugPrint('church_video_preupload_falhou: $e');
        return null;
      }
    }();
    // Envio abandonado (vídeo removido / editor fechado) → limpar o órfão.
    unawaited(
      entry.future.then((_) async {
        entry.completed = true;
        if (!entry.abandoned) return;
        if (identical(_entries[key], entry)) _entries.remove(key);
        await entry.runCleanup();
      }),
    );
  }

  /// `true` enquanto houver envio antecipado ativo para [localPath].
  static bool isActive(String localPath) {
    final e = _entries[localPath.trim()];
    return e != null && !e.abandoned && !e.completed;
  }

  /// Progresso 0–1 do envio antecipado (0 quando não existe).
  static double progressOf(String localPath) =>
      _entries[localPath.trim()]?.progress ?? 0.0;

  /// Teto da espera pelo envio antecipado.
  ///
  /// O encode nativo (`video_compress`) não tem tempo máximo: quando ele
  /// emperra, `await entry.future` nunca resolvia e a publicação inteira
  /// ficava pendurada — barra parada, aviso nunca gravado. Ao estourar, o
  /// chamador trata como falha de vídeo e publica o aviso sem ele.
  static const Duration kClaimTimeout = Duration(minutes: 5);

  /// Aguarda o envio antecipado de [localPath] para o destino [tag].
  ///
  /// Devolve `null` quando não há envio aproveitável — o chamador segue então
  /// pelo caminho normal de upload.
  static Future<T?> claim<T extends Object>({
    required String localPath,
    required String tag,
    void Function(double progress)? onProgress,
    Duration timeout = kClaimTimeout,
  }) async {
    final key = localPath.trim();
    final entry = _entries[key];
    if (entry == null || entry.abandoned || entry.tag != tag) return null;
    StreamSubscription<double>? sub;
    if (onProgress != null) {
      onProgress(entry.progress);
      sub = entry.progressStream.listen(onProgress);
    }
    try {
      final result = await entry.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'O envio do vídeo demorou demais.',
          timeout,
        ),
      );
      return result is T ? result : null;
    } finally {
      await sub?.cancel();
      _entries.remove(key);
      entry.dispose();
    }
  }

  /// Descarta o envio antecipado: o resultado deixa de ser usado e o objeto
  /// que eventualmente chegar ao Storage é apagado.
  static void abandon(String localPath) {
    final key = localPath.trim();
    final entry = _entries[key];
    if (entry == null) return;
    entry.abandoned = true;
    // Já tinha terminado antes de ser descartado: o objeto está no bucket e
    // ninguém o vai usar — apagar agora (senão ficava lixo pago no Storage).
    if (entry.completed) {
      _entries.remove(key);
      unawaited(entry.runCleanup());
    }
  }
}

class _PreuploadEntry {
  _PreuploadEntry({required this.tag, this.onAbandonedCleanup});

  final String tag;
  final Future<void> Function()? onAbandonedCleanup;
  final StreamController<double> _progress =
      StreamController<double>.broadcast();

  late final Future<Object?> future;
  double progress = 0.0;
  bool abandoned = false;
  bool completed = false;
  bool _cleaned = false;

  Future<void> runCleanup() async {
    if (_cleaned) return;
    _cleaned = true;
    dispose();
    try {
      await onAbandonedCleanup?.call();
    } catch (_) {}
  }

  Stream<double> get progressStream => _progress.stream;

  void report(double p) {
    final v = p.isNaN ? 0.0 : p.clamp(0.0, 1.0).toDouble();
    progress = v;
    if (!_progress.isClosed) _progress.add(v);
  }

  void dispose() {
    if (!_progress.isClosed) _progress.close();
  }
}
