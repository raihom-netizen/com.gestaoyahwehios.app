import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Barra de progresso real de upload (Storage [UploadTask.snapshotEvents] via [GlobalUploadProgress]).
class StorageUploadProgressIndicator extends StatelessWidget {
  const StorageUploadProgressIndicator({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlobalUploadProgressState?>(
      valueListenable: GlobalUploadProgress.instance.state,
      builder: (context, state, _) {
        if (state == null) return const SizedBox.shrink();
        final progress = state.progress.clamp(0.0, 1.0);
        if (compact) {
          return LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 3,
            backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
            color: ThemeCleanPremium.primary,
          );
        }
        return Material(
          elevation: 6,
          color: ThemeCleanPremium.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.displayLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor:
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  color: ThemeCleanPremium.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
