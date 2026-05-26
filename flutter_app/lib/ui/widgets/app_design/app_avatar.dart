import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/app_design/app_cached_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:shimmer/shimmer.dart';

/// Avatar circular padronizado.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.photoUrl,
    this.size = 48,
    this.initials,
    this.memCacheWidth,
  });

  final String? photoUrl;
  final double size;
  final String? initials;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    if (url.isNotEmpty) {
      return AppCachedImage(
        imageUrl: url,
        width: size,
        height: size,
        memCacheWidth: memCacheWidth ?? size.round() * 2,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(size / 2),
        placeholder: Shimmer.fromColors(
          baseColor: const Color(0xFFE2E8F0),
          highlightColor: const Color(0xFFF8FAFC),
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    final init = (initials ?? '?').trim();
    final letter =
        init.isNotEmpty ? init.substring(0, 1).toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: ThemeCleanPremium.primary,
        ),
      ),
    );
  }
}
