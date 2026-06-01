import 'package:flutter/material.dart';

/// Feedback imediato ao escolher ficheiro — padrão Controle Total («Arquivo anexado: …»).
abstract final class ImmediateMediaAttachFeedback {
  ImmediateMediaAttachFeedback._();

  static String shortFileName(String name, {int max = 42}) {
    final n = name.trim();
    if (n.isEmpty) return 'ficheiro';
    if (n.length <= max) return n;
    return '${n.substring(0, max - 1)}…';
  }

  static void showArquivoAnexado(BuildContext context, String fileName) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Arquivo anexado: ${shortFileName(fileName)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void showEnviadoEVinculado(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Ficheiro enviado e vinculado.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}
