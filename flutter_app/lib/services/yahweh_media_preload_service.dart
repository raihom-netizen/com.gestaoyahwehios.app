import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show preloadNetworkImages;

/// Pré-carregamento global ao abrir ecrãs (usa pipeline Storage-safe, não `NetworkImage` cru na web).
abstract final class YahwehMediaPreloadService {
  YahwehMediaPreloadService._();

  static Future<void> preloadForScreen(
    BuildContext context,
    Iterable<String> urls, {
    int? maxItems,
  }) async {
    if (!context.mounted) return;
    final list = urls.where((u) => u.trim().isNotEmpty).toList();
    if (list.isEmpty) return;
    await preloadNetworkImages(
      context,
      list,
      maxItems: maxItems ?? YahwehPerformanceV4.preloadScreenMaxUrls,
    );
  }
}
