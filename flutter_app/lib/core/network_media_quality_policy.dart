import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';

/// Qualidade WebP/JPEG adaptada à rede (Wi‑Fi vs 4G vs rede fraca).
abstract final class NetworkMediaQualityPolicy {
  NetworkMediaQualityPolicy._();

  static const int qualityWifi = 85;
  static const int qualityCellular = 70;
  static const int qualityLow = 50;

  /// Tier atual com base em [ConnectivityResult].
  static Future<NetworkMediaTier> currentTier() async {
    if (!AppConnectivityService.instance.isOnline) {
      return NetworkMediaTier.low;
    }
    try {
      final list = await Connectivity().checkConnectivity();
      if (list.contains(ConnectivityResult.wifi) ||
          list.contains(ConnectivityResult.ethernet)) {
        return NetworkMediaTier.wifi;
      }
      if (list.contains(ConnectivityResult.mobile)) {
        return NetworkMediaTier.cellular;
      }
      if (list.every((r) => r == ConnectivityResult.none)) {
        return NetworkMediaTier.low;
      }
    } catch (_) {}
    return NetworkMediaTier.cellular;
  }

  static int webpQualityForTier(NetworkMediaTier tier) => switch (tier) {
        NetworkMediaTier.wifi => qualityWifi,
        NetworkMediaTier.cellular => qualityCellular,
        NetworkMediaTier.low => qualityLow,
      };

  /// Qualidade para compressão imediata (upload).
  static Future<int> webpQualityForCurrentNetwork() async {
    return webpQualityForTier(await currentTier());
  }

  /// Limita paralelismo de upload conforme rede.
  static Future<int> maxConcurrentUploads() async {
    final tier = await currentTier();
    return switch (tier) {
      NetworkMediaTier.wifi => 3,
      NetworkMediaTier.cellular => 2,
      NetworkMediaTier.low => 1,
    };
  }
}

enum NetworkMediaTier { wifi, cellular, low }
