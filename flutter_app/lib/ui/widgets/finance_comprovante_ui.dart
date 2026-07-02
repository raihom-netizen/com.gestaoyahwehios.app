import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
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
        await DirectStorageUrlPublish.ensureReady();
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
