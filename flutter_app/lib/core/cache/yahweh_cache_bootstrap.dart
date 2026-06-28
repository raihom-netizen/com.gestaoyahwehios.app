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
    unawaited(_ensurePhase1Background(cid));
  }

  static Future<void> _ensurePhase1Background(String churchId) async {
    try {
      await YahwehModuleCaches.ensurePhase1(churchId).timeout(
        const Duration(seconds: 12),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YahwehCacheBootstrap phase1: $e');
    }
  }

  /// Chamado após tenant resolvido no shell (churchId conhecido).
  static void scheduleTenantWarm(String churchId) {
    unawaited(warmTenantAfterLogin(churchId));
  }
}
