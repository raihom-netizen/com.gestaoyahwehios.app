import 'package:flutter/material.dart';

/// Fora da web o mural usa player nativo; este widget não deve ser montado.
class PremiumHtmlFeedVideo extends StatelessWidget {
  const PremiumHtmlFeedVideo({
    super.key,
    required this.videoUrl,
    required this.visibilityKey,
    this.showControls = true,
    this.onMostlyVisible,
    this.posterUrl,
    this.startLoadingImmediately = false,
    this.videoObjectFitContain = true,
  });

  final String videoUrl;
  final String visibilityKey;
  final bool showControls;
  final VoidCallback? onMostlyVisible;
  final String? posterUrl;
  final bool startLoadingImmediately;
  final bool videoObjectFitContain;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
