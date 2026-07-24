import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Upload de comprovante — padrão Controle Total (silencioso, sem faixa %).
abstract final class FinanceComprovanteUi {
  FinanceComprovanteUi._();

  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String label,
    required Future<T> Function(void Function(double progress) onProgress)
        action,
    VoidCallback? closeEditor,
    String? successMessage,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    closeEditor?.call();

    void reportProgress(double _) {}

    try {
      await ChurchMediaUploadFacade.ensureReady();
      final result = await action(reportProgress);
      if (successMessage != null && successMessage.isNotEmpty) {
        messenger?.showSnackBar(
          ThemeCleanPremium.successSnackBar(successMessage),
        );
      }
      return result;
    } finally {}
  }

  static void schedule<T>({
    required BuildContext context,
    required String label,
    required Future<T> Function(void Function(double progress) onProgress)
        action,
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
