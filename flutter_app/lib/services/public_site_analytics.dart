import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

/// Analytics Firebase — site público (igreja + divulgação). Falhas silenciosas.
abstract final class PublicSiteAnalytics {
  PublicSiteAnalytics._();

  static FirebaseAnalytics? _a;
  static FirebaseAnalyticsObserver? _observer;

  static FirebaseAnalyticsObserver? get navigatorObserver => _observer;

  static Future<void> ensureInitialized() async {
    if (_a != null) return;
    try {
      _a = FirebaseAnalytics.instance;
      await _a!.setAnalyticsCollectionEnabled(true);
      _observer = FirebaseAnalyticsObserver(analytics: _a!);
    } catch (_) {
      _a = null;
      _observer = null;
    }
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _a;
    if (analytics == null) return;
    final safeName = name.length > 40 ? name.substring(0, 40) : name;
    try {
      await analytics.logEvent(
        name: safeName,
        parameters: _sanitizeParams(parameters),
      );
    } catch (_) {}
  }

  static Map<String, Object>? _sanitizeParams(Map<String, Object>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final out = <String, Object>{};
    for (final e in raw.entries) {
      if (out.length >= 24) break;
      var k = e.key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      if (k.length > 40) k = k.substring(0, 40);
      final v = e.value;
      if (v is String) {
        final s = v.length > 100 ? '${v.substring(0, 97)}...' : v;
        out[k] = s;
      } else if (v is num || v is bool) {
        out[k] = v;
      }
    }
    return out.isEmpty ? null : out;
  }

  /// Entrada na página pública da igreja (slug conhecido cedo).
  static Future<void> logChurchPublicOpen({
    required String slug,
    String? tenantId,
  }) {
    return logEvent(
      'church_public_open',
      parameters: {
        'slug': slug,
        if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      },
    );
  }

  static Future<void> logChurchPublicAction(String action,
      {String? slug, String? tenantId}) {
    return logEvent(
      'church_public_action',
      parameters: {
        'action': action,
        if (slug != null && slug.isNotEmpty) 'slug': slug,
        if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
      },
    );
  }

  static Future<void> logMarketingAction(String action) {
    return logEvent(
      'marketing_site_action',
      parameters: {'action': action},
    );
  }
}
