import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Feedback imediato ao escolher ficheiro — padrão Controle Total.
abstract final class ImmediateMediaAttachFeedback {
  ImmediateMediaAttachFeedback._();

  static String shortFileName(String name, {int max = 42}) {
    final n = name.trim();
    if (n.isEmpty) return 'ficheiro';
    if (n.length <= max) return n;
    return '${n.substring(0, max - 1)}…';
  }

  /// Formata tamanho em KB/MB a partir de bytes.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(bytes / kb).round()} KB';
  }

  /// Cache — evita re-decode em cada rebuild (teclado / MediaQuery).
  static final Map<int, Future<String?>> _resolutionCache = {};

  /// Lê largura×altura de forma assíncrona (melhor-esforço) para exibir resolução.
  static Future<String?> readResolution(Uint8List bytes) {
    if (bytes.isEmpty) return Future.value(null);
    final key = Object.hash(identityHashCode(bytes), bytes.length);
    final hit = _resolutionCache[key];
    if (hit != null) return hit;

    final completer = Completer<String?>();
    try {
      ui.decodeImageFromList(bytes, (image) {
        if (!completer.isCompleted) {
          completer.complete('${image.width}×${image.height}');
        }
      });
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    final fut = completer.future;
    _resolutionCache[key] = fut;
    // Limita crescimento do cache em sessões longas com muitas fotos.
    if (_resolutionCache.length > 48) {
      final keys = _resolutionCache.keys.take(16).toList();
      for (final k in keys) {
        _resolutionCache.remove(k);
      }
    }
    return fut;
  }

  /// SnackBar de sucesso (verde) com nome + tamanho + resolução (se disponível).
  static void showFotoAdicionadaSucesso(
    BuildContext context, {
    required String fileName,
    int? sizeBytes,
    String? resolution,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final name = shortFileName(fileName);
    final lines = <String>[
      '✓ Foto adicionada com sucesso',
      'Nome: $name',
      if (sizeBytes != null) formatBytes(sizeBytes),
      if (resolution != null && resolution.isNotEmpty) resolution,
    ];
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lines.join('\n'),
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Compatibilidade: mantém chamadas antigas (sem detalhes).
  static void showArquivoAnexado(BuildContext context, String fileName) {
    showFotoAdicionadaSucesso(context, fileName: fileName);
  }

  static void showEnviadoEVinculado(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ficheiro enviado e vinculado.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}
