import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bootstrap central — espelha WISDOMAPP main.dart warmUp (~800 ms cap).
abstract final class YahwehCacheBootstrap {
  YahwehCacheBootstrap._();

  static const Duration kWarmCap = Duration(milliseconds: 800);

  /// Antes do 1.º frame — aquece SharedPreferences (todos os módulos).
  static Future<void> warmUpPrefs() async {
    try {
      await SharedPreferences.getInstance().timeout(kWarmCap);
    } catch (_) {}
  }

  /// Após tenant resolvido no shell — cache local + prefetch SWR Hive.
  static Future<void> warmTenantAfterLogin(String churchId) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    try {
      await YahwehModuleCaches.warmUpTenant(cid).timeout(kWarmCap);
    } catch (_) {}
    unawaited(_ensureProductionBackground(cid));
  }

  static Future<void> _ensureProductionBackground(String churchId) async {
    try {
      // Só Phase1 no hot path — Phase2/3 competiam com o dashboard na abertura.
      await YahwehModuleCaches.ensurePhase1(churchId).timeout(
        const Duration(seconds: 10),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YahwehCacheBootstrap production: $e');
    }
  }

  /// Chamado após tenant resolvido no shell (churchId conhecido).
  static void scheduleTenantWarm(String churchId) {
    unawaited(warmTenantAfterLogin(churchId));
  }
}
