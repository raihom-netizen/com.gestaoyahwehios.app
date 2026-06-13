import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Progresso bloqueante — avisos, eventos, património, etc. (padrão Ecofire).
abstract final class EcofirePublishProgressUi {
  EcofirePublishProgressUi._();

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
