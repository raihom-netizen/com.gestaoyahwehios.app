import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_design_system.dart';
import 'package:shimmer/shimmer.dart';

/// Placeholders e erro de imagem **alinhados** ao design system (site público, painel, divulgação).
abstract final class YahwehMediaPlaceholder {
  YahwehMediaPlaceholder._();

  static Widget shimmerBox({
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    final r =
        borderRadius ?? BorderRadius.circular(YahwehDesignSystem.radiusMd);
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: r,
        ),
      ),
    );
  }

  /// Mesmo visual de “imagem indisponível” em qualquer frente.
  static Widget imageError({
    double? iconSize,
    Color? backgroundColor,
  }) {
    return Container(
      color: backgroundColor ?? Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_rounded,
        size: iconSize ?? 40,
        color: Colors.grey.shade500,
      ),
    );
  }
}
