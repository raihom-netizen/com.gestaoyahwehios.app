import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regista um acesso ao domínio por dia (Flutter web) via Cloud Function → `config/analytics.daily`.
abstract final class DomainDailyHitService {
  DomainDailyHitService._();

  static const _prefsKey = 'gyh_domain_daily_hit_sent_date_v1';

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// No máximo um envio por dia por navegador; ignora Painel Master (`/admin`, `/login_admin`).
  static Future<void> recordIfEligible() async {
    if (!kIsWeb) return;
    final path = Uri.base.path.toLowerCase();
    if (path.startsWith('/admin') || path.startsWith('/login_admin')) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (prefs.getString(_prefsKey) == today) return;

      await _fn.httpsCallable('recordDomainDailyHit').call(<String, dynamic>{
        'dateKey': today,
      });
      await prefs.setString(_prefsKey, today);
    } catch (_) {}
  }
}
