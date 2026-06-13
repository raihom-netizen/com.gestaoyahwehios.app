import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Progresso bloqueante durante upload/gravação de comprovante financeiro.
abstract final class FinanceComprovanteUi {
  FinanceComprovanteUi._();

  static Future<T> runWithProgress<T>(
    BuildContext context, {
    required String label,
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
                            label,
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
                      '${(p * 100).clamp(5, 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
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

    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      return await action((p) {
        progress.value = p.clamp(0.0, 1.0);
      });
    } finally {
      progress.dispose();
      closeDialog();
    }
  }
}
