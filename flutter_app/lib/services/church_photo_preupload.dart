import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Executa o envio de uma foto e devolve a URL pública (vazio = falhou).
typedef ChurchPhotoPreuploadRunner = Future<String> Function();

/// Envio antecipado das fotos de Avisos/Eventos.
///
/// Mesma ideia do [ChurchVideoPreupload]: o envio arranca **no momento em que
/// a foto é anexada**, para o caminho definitivo no Storage (o id do post já
/// existe antes de publicar). O tempo que o utilizador leva a escrever título,
/// data e local passa a ser tempo de rede aproveitado.
///
/// **Regra de segurança — reaproveitamento tudo-ou-nada.** O caminho de cada
/// foto no Storage é `…_{slot}`, e o slot é a posição da foto na publicação.
/// Remover uma foto do meio desloca o slot de todas as seguintes: um
/// reaproveitamento parcial publicaria a foto errada naquela posição. Por isso
/// [claimAll] só devolve URLs quando **todas** as fotos da publicação têm
/// pré-envio concluído para exatamente o caminho esperado — basta uma falhar e
/// o lote inteiro é descartado, e a publicação sobe tudo pelo caminho normal.
///
/// A chave do registo é a própria instância de bytes (`Uint8List` não
/// sobrescreve `==`, portanto a comparação é por identidade): a foto anexada
/// pelo editor e a foto entregue à publicação são o mesmo objeto, e uma foto
/// diferente nunca colide com o registo de outra.
abstract final class ChurchPhotoPreupload {
  ChurchPhotoPreupload._();

  static final Map<Uint8List, _PhotoEntry> _entries = {};

  /// Arranca o envio antecipado de [bytes] para [storagePath].
  ///
  /// [onAbandonedCleanup] apaga o objeto do Storage quando o envio deixa de
  /// ser aproveitável (foto removida, slots deslocados, editor fechado).
  static void start({
    required Uint8List bytes,
    required String storagePath,
    required ChurchPhotoPreuploadRunner run,
    required Future<void> Function() onAbandonedCleanup,
  }) {
    final path = storagePath.trim();
    if (bytes.isEmpty || path.isEmpty) return;
    final existing = _entries[bytes];
    if (existing != null) {
      if (existing.storagePath == path) return;
      // Mesma foto, destino diferente (os slots deslocaram): o objeto no
      // caminho antigo deixa de ser usado — apagar antes de reenviar.
      unawaited(_abandonEntry(bytes, existing));
    }

    final entry = _PhotoEntry(
      storagePath: path,
      onAbandonedCleanup: onAbandonedCleanup,
    );
    _entries[bytes] = entry;
    entry.future = () async {
      try {
        final url = (await run()).trim();
        entry.url = url;
        return url;
      } catch (e) {
        // Falhar aqui nunca pode rebentar: a publicação repete o envio pelo
        // caminho normal e é lá que o erro chega ao utilizador.
        if (kDebugMode) debugPrint('church_photo_preupload_falhou: $e');
        return '';
      }
    }();
    unawaited(
      entry.future.then((_) async {
        entry.completed = true;
        if (!entry.abandoned) return;
        if (identical(_entries[bytes], entry)) _entries.remove(bytes);
        await entry.runCleanup();
      }),
    );
  }

  /// Realinha o lote inteiro com os destinos [desired], pela ordem final.
  ///
  /// **Apaga primeiro, envia depois.** Quando uma foto sai do meio, todas as
  /// seguintes recuam um slot: a foto do slot 2 passa a ir para o 1 e a do 1
  /// para o 0. Se cada uma limpasse o seu slot antigo por sua conta, a limpeza
  /// do slot 1 (feita pela foto que saiu dele) podia correr **depois** do
  /// envio da outra foto para esse mesmo slot 1 — e apagá-la. Por isso todas
  /// as limpezas são concluídas antes de qualquer envio novo arrancar.
  static Future<void> syncBatch(
    List<
      ({
        Uint8List bytes,
        String storagePath,
        ChurchPhotoPreuploadRunner run,
        Future<void> Function() cleanup,
      })
    >
    desired,
  ) async {
    final moved = <Uint8List>[];
    for (final item in desired) {
      final entry = _entries[item.bytes];
      if (entry != null &&
          !entry.abandoned &&
          entry.storagePath != item.storagePath.trim()) {
        moved.add(item.bytes);
      }
    }
    if (moved.isNotEmpty) await abandonAll(moved);
    for (final item in desired) {
      start(
        bytes: item.bytes,
        storagePath: item.storagePath,
        run: item.run,
        onAbandonedCleanup: item.cleanup,
      );
    }
  }

  /// Destino registado para [bytes] (null quando não há envio aproveitável).
  static String? storagePathOf(Uint8List bytes) {
    final e = _entries[bytes];
    if (e == null || e.abandoned) return null;
    return e.storagePath;
  }

  /// `true` se há envio antecipado em curso ou concluído para [bytes].
  static bool isActive(Uint8List bytes) {
    final e = _entries[bytes];
    return e != null && !e.abandoned;
  }

  /// Quantos dos [list] têm envio antecipado registado (para a UI do editor).
  static int activeCount(Iterable<Uint8List> list) =>
      list.where(isActive).length;

  /// Quantos já terminaram com URL válida.
  static int readyCount(Iterable<Uint8List> list) => list
      .where((b) => (_entries[b]?.url ?? '').isNotEmpty)
      .length;

  /// Reaproveitamento **tudo-ou-nada** (ver nota da classe).
  ///
  /// [expected] é a lista `(bytes, storagePath)` na ordem exata da publicação.
  /// Devolve as URLs na mesma ordem, ou `null` se qualquer foto não tiver
  /// pré-envio concluído para o caminho esperado — nesse caso os pré-envios
  /// que existirem são descartados e os objetos órfãos apagados do Storage,
  /// para o caminho normal poder reescrever os slots sem deixar lixo.
  static Future<List<String>?> claimAll(
    List<({Uint8List bytes, String storagePath})> expected,
  ) async {
    if (expected.isEmpty) return const [];

    final urls = <String>[];
    var ok = true;
    for (final item in expected) {
      final entry = _entries[item.bytes];
      if (entry == null ||
          entry.abandoned ||
          entry.storagePath != item.storagePath.trim()) {
        ok = false;
        break;
      }
      final url = await entry.future;
      if (url.isEmpty) {
        ok = false;
        break;
      }
      urls.add(url);
    }

    if (!ok) {
      await abandonAll(expected.map((e) => e.bytes));
      return null;
    }
    // Aproveitado: o objeto no Storage passa a pertencer ao post publicado —
    // esquecer sem apagar.
    forget(expected.map((e) => e.bytes));
    return urls;
  }

  /// Descarta o pré-envio de [bytes] e apaga o objeto que já tenha chegado ao
  /// Storage. Aguarda a limpeza — quem remove uma foto tem de saber que o
  /// bucket ficou limpo antes de a publicação escrever nos mesmos slots.
  static Future<void> abandon(Uint8List bytes) async {
    final entry = _entries[bytes];
    if (entry == null) return;
    await _abandonEntry(bytes, entry);
  }

  static Future<void> abandonAll(Iterable<Uint8List> list) async {
    final snapshot = list.toList();
    await Future.wait(snapshot.map(abandon));
  }

  /// Esquece os registos sem apagar nada do Storage (publicação concluída).
  static void forget(Iterable<Uint8List> list) {
    for (final b in list.toList()) {
      _entries.remove(b);
    }
  }

  static Future<void> _abandonEntry(Uint8List bytes, _PhotoEntry entry) async {
    entry.abandoned = true;
    if (identical(_entries[bytes], entry)) _entries.remove(bytes);
    if (!entry.completed) {
      // Ainda a subir: esperar para não apagar antes de o objeto existir.
      try {
        await entry.future;
      } catch (_) {}
    }
    await entry.runCleanup();
  }
}

class _PhotoEntry {
  _PhotoEntry({required this.storagePath, required this.onAbandonedCleanup});

  final String storagePath;
  final Future<void> Function() onAbandonedCleanup;

  late final Future<String> future;
  String url = '';
  bool abandoned = false;
  bool completed = false;
  bool _cleaned = false;

  Future<void> runCleanup() async {
    if (_cleaned) return;
    _cleaned = true;
    try {
      await onAbandonedCleanup();
    } catch (_) {}
  }
}
