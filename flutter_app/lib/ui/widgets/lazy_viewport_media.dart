import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Só monta [builder] depois que o widget entra no viewport (scroll).
/// Mantém o filho após a primeira vez visível para não refazer download ao rolar.
class LazyViewportBuilder extends StatefulWidget {
  const LazyViewportBuilder({
    super.key,
    required this.visibilityKey,
    required this.placeholder,
    required this.builder,
    this.visibleFractionThreshold = 0.06,
  });

  final String visibilityKey;
  final Widget placeholder;
  final Widget Function() builder;
  final double visibleFractionThreshold;

  @override
  State<LazyViewportBuilder> createState() => _LazyViewportBuilderState();
}

class _LazyViewportBuilderState extends State<LazyViewportBuilder> {
  bool _activated = false;

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('lazy-vp-${widget.visibilityKey}'),
      onVisibilityChanged: (info) {
        if (_activated) return;
        if (info.visibleFraction >= widget.visibleFractionThreshold) {
          setState(() => _activated = true);
        }
      },
      child: _activated ? widget.builder() : widget.placeholder,
    );
  }
}
