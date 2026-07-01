import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatUploadErrorForUser, isFirebaseNoAppError;
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Progresso bloqueante — avisos, eventos, património, etc. (padrão Ecofire).
abstract final class EcofirePublishProgressUi {
  EcofirePublishProgressUi._();

  /// Publicação estilo WhatsApp: fecha o editor de imediato e mostra barra global
  /// ([GlobalUploadProgress] / [StorageUploadProgressIndicator] no feed).
  static Future<T> runInBackgroundNonBlocking<T>({
    required BuildContext context,
    required String uploadLabel,
    required String saveLabel,
    required String distributeLabel,
    required String successMessage,
    required VoidCallback closeEditor,
    required Future<T> Function(void Function(double progress)) action,
    String Function(Object error)? formatError,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    closeEditor();
    GlobalUploadProgress.instance.start(uploadLabel);
    var phaseLabel = uploadLabel;

    void reportProgress(double p) {
      final next = p < 0.78
          ? uploadLabel
          : p < 0.94
              ? saveLabel
              : distributeLabel;
      if (next != phaseLabel) {
        phaseLabel = next;
        GlobalUploadProgress.instance.updateLabel(next);
      }
      GlobalUploadProgress.instance.update(p);
    }

    try {
      await YahwehModuleMediaGate.assertReadyForUploadAction();
      final result = await _runPublishActionWithNoAppRetry(action, reportProgress);
      messenger?.showSnackBar(
        ThemeCleanPremium.successSnackBar(successMessage),
      );
      return result;
    } catch (e) {
      final msg = formatError?.call(e) ?? formatUploadErrorForUser(e);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Tentar novamente',
            textColor: Colors.white,
            onPressed: () {
              unawaited(
                _retryPublishOnly(
                  messenger: messenger,
                  uploadLabel: uploadLabel,
                  saveLabel: saveLabel,
                  distributeLabel: distributeLabel,
                  successMessage: successMessage,
                  action: action,
                  formatError: formatError,
                ),
              );
            },
          ),
        ),
      );
      rethrow;
    } finally {
      GlobalUploadProgress.instance.end();
    }
  }

  static Future<T> _runPublishActionWithNoAppRetry<T>(
    Future<T> Function(void Function(double progress)) action,
    void Function(double progress) reportProgress,
  ) async {
    try {
      return await action(reportProgress);
    } catch (e) {
      if (!isFirebaseNoAppError(e)) rethrow;
      await YahwehModuleMediaGate.recoverNoAppAfterPublishError(e);
      await YahwehModuleMediaGate.assertReadyForUploadAction();
      return action(reportProgress);
    }
  }

  static Future<void> _retryPublishOnly<T>({
    required ScaffoldMessengerState? messenger,
    required String uploadLabel,
    required String saveLabel,
    required String distributeLabel,
    required String successMessage,
    required Future<T> Function(void Function(double progress)) action,
    String Function(Object error)? formatError,
  }) async {
    GlobalUploadProgress.instance.start(uploadLabel);
    var phaseLabel = uploadLabel;

    void reportProgress(double p) {
      final next = p < 0.78
          ? uploadLabel
          : p < 0.94
              ? saveLabel
              : distributeLabel;
      if (next != phaseLabel) {
        phaseLabel = next;
        GlobalUploadProgress.instance.updateLabel(next);
      }
      GlobalUploadProgress.instance.update(p);
    }

    try {
      await YahwehModuleMediaGate.assertReadyForUploadAction();
      await _runPublishActionWithNoAppRetry(action, reportProgress);
      messenger?.showSnackBar(
        ThemeCleanPremium.successSnackBar(successMessage),
      );
    } catch (e) {
      final msg = formatError?.call(e) ?? formatUploadErrorForUser(e);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      GlobalUploadProgress.instance.end();
    }
  }

  /// Fire-and-forget — não bloqueia o chamador após fechar o editor.
  static void schedule<T>({
    required BuildContext context,
    required String uploadLabel,
    required String saveLabel,
    required String distributeLabel,
    required String successMessage,
    required VoidCallback closeEditor,
    required Future<T> Function(void Function(double progress)) action,
    String Function(Object error)? formatError,
  }) {
    unawaited(
      runInBackgroundNonBlocking<T>(
        context: context,
        uploadLabel: uploadLabel,
        saveLabel: saveLabel,
        distributeLabel: distributeLabel,
        successMessage: successMessage,
        closeEditor: closeEditor,
        action: action,
        formatError: formatError,
      ),
    );
  }

  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String uploadLabel,
    required String saveLabel,
    required String distributeLabel,
    required Future<T> Function(void Function(double progress)) action,
  }) async {
    if (!context.mounted) {
      return action((_) {});
    }

    final progress = ValueNotifier<double>(0.05);
    var closed = false;

    void closeDialog() {
      if (closed) return;
      closed = true;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            ),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, p, __) {
                final pct = (p * 100).clamp(5, 100).round();
                final phase = p < 0.78
                    ? uploadLabel
                    : p < 0.94
                        ? saveLabel
                        : distributeLabel;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            phase,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: p.clamp(0.05, 1.0),
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    try {
      return await action((p) {
        if (progress.value != p) progress.value = p;
      });
    } finally {
      closeDialog();
      progress.dispose();
    }
  }
}

/// Alias legado — avisos.
typedef AvisoPublishUi = EcofirePublishProgressUi;
