import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Barra fina no topo do editor (avisos/eventos) — progresso local ou global, sem congelar a tela.
class AsyncUploadProgressStrip extends StatelessWidget {
  const AsyncUploadProgressStrip({
    super.key,
    this.localActive = false,
    this.localLabel = 'A preparar mídia…',
    this.localProgress,
  });

  final bool localActive;
  final String localLabel;
  final double? localProgress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlobalUploadProgressState?>(
      valueListenable: GlobalUploadProgress.instance.state,
      builder: (context, global, _) {
        final showGlobal = global != null;
        final showLocal = localActive && !showGlobal;
        if (!showGlobal && !showLocal) return const SizedBox.shrink();

        final label = showGlobal ? global!.label : localLabel;
        final progress = showGlobal
            ? global!.progress
            : (localProgress != null ? localProgress!.clamp(0.0, 1.0) : null);

        return Material(
          elevation: 2,
          color: ThemeCleanPremium.cardBackground,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: progress != null && progress > 0 && progress < 1
                    ? progress
                    : null,
                minHeight: 3,
                color: ThemeCleanPremium.primary,
                backgroundColor:
                    ThemeCleanPremium.primary.withValues(alpha: 0.12),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
