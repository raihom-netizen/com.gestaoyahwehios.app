import 'dart:async';

import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';

/// Um único pré-aquecimento por sessão/tenant — evita callables duplicados (login + splash + AuthGate).
abstract final class PanelPreheatCoordinator {
  PanelPreheatCoordinator._();

  static String? _inFlightTenant;
  static Future<void>? _inFlight;

  static Future<void> preheatOnce({
    String? tenantIdHint,
    bool force = false,
  }) async {
    final tid = (tenantIdHint ?? '').trim();
    if (tid.isEmpty) {
      await ChurchAutoSessionService.preheatPanelCaches(
        tenantIdHint: tenantIdHint,
      );
      return;
    }
    if (!force &&
        _inFlightTenant == tid &&
        _inFlight != null) {
      return _inFlight!;
    }
    _inFlightTenant = tid;
    _inFlight = ChurchAutoSessionService.preheatPanelCaches(
      tenantIdHint: tid,
    );
    try {
      await _inFlight;
    } finally {
      if (_inFlightTenant == tid) {
        _inFlight = null;
      }
    }
  }

  static void resetForAccountSwitch() {
    _inFlightTenant = null;
    _inFlight = null;
    ChurchTenantOfflineWarmupService.instance.resetForNewSession();
  }
}
