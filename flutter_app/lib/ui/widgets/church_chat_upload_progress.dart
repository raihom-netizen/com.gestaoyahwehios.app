import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Indicador de envio (0–1) — bolha local ou stub Firestore sem URL.
class ChurchChatUploadProgressIndicator extends StatelessWidget {
  const ChurchChatUploadProgressIndicator({
    super.key,
    required this.progress,
    required this.label,
    this.icon = Icons.cloud_upload_rounded,
    this.compact = false,
  });

  final double? progress;
  final String label;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = progress?.clamp(0.0, 1.0);
    final showBar = p != null && p > 0 && p < 1;
    final pct = p != null ? (p * 100).round().clamp(0, 100) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 18 : 22,
              color: ThemeCleanPremium.primary,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                pct != null && showBar ? '$label · $pct%' : label,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!showBar) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        if (showBar) ...[
          SizedBox(height: compact ? 6 : 8),
          LinearProgressIndicator(
            value: p,
            minHeight: compact ? 3 : 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ],
    );
  }
}
