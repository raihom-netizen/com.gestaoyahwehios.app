import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Upload de comprovante — barra global (Controle Total), sem bloquear o ecrã.
abstract final class FinanceComprovanteUi {
  FinanceComprovanteUi._();

  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String label,
    required Future<T> Function(void Function(double progress)) action,
    VoidCallback? closeEditor,
    String? successMessage,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    closeEditor?.call();
    GlobalUploadProgress.instance.start(label);

    void reportProgress(double p) {
      GlobalUploadProgress.instance.update(p);
    }

    try {
      await ChurchMediaUploadFacade.ensureReady();
      final result = await action(reportProgress);
      if (successMessage != null && successMessage.isNotEmpty) {
        messenger?.showSnackBar(
          ThemeCleanPremium.successSnackBar(successMessage),
        );
      }
      return result;
    } finally {
      GlobalUploadProgress.instance.end();
    }
  }

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
