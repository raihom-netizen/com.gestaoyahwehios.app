import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/ui/widgets/aviso_publish_ui.dart';

/// Upload de comprovante — barra global estilo WhatsApp (não bloqueia o ecrã).
abstract final class FinanceComprovanteUi {
  FinanceComprovanteUi._();

  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String label,
    required Future<T> Function(void Function(double progress)) action,
    VoidCallback? closeEditor,
    String? successMessage,
  }) {
    return EcofirePublishProgressUi.runInBackgroundNonBlocking<T>(
      context: context,
      uploadLabel: label,
      saveLabel: 'A gravar comprovante…',
      distributeLabel: 'A finalizar…',
      successMessage: successMessage ?? 'Comprovante enviado.',
      closeEditor: closeEditor ?? () {},
      action: (report) async {
        final ok = await YahwehModuleMediaGate.prepareForPublishUpload(
          context: context,
          module: YahwehMediaModule.financeiro,
          logLabel: 'finance_comprovante_ui',
        );
        if (!ok) {
          throw StateError(
            'Firebase não inicializou (core/no-app).',
          );
        }
        return action(report);
      },
    );
  }

  /// Fire-and-forget após fechar o formulário financeiro.
  static void schedule<T>({
    required BuildContext context,
    required String label,
    required Future<T> Function(void Function(double progress)) action,
    VoidCallback? closeEditor,
    String? successMessage,
  }) {
    unawaited(
      runWithProgress<T>(
        context,
        label: label,
        action: action,
        closeEditor: closeEditor,
        successMessage: successMessage,
      ),
    );
  }
}
