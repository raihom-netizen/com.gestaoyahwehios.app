import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/app_constants.dart';

/// Regras de bloqueio do painel da igreja (carência, trial, assinatura).
/// Extraído do [AuthGate] para uso em shells sem import circular com `auth_gate.dart`.
class LicenseAccessPolicy {
  LicenseAccessPolicy._();

  /// Fim do período de acesso considerando doc da igreja (trial, licença paga, master, etc.).
  /// Usa sempre a data **mais favorável** (mais tardia) entre os campos conhecidos.
  static DateTime? churchAccessEnd(Map<String, dynamic>? church) {
    if (church == null) return null;
    final lic = church['license'] is Map
        ? Map<String, dynamic>.from(church['license'] as Map)
        : null;
    final billing = church['billing'] is Map
        ? Map<String, dynamic>.from(church['billing'] as Map)
        : null;

    DateTime? best;
    var hasExplicitLicenseEnd = false;

    void takeLater(Object? raw, {bool explicit = true}) {
      final d = _toDate(raw);
      if (d == null) return;
      if (explicit) hasExplicitLicenseEnd = true;
      if (best == null || d.isAfter(best!)) best = d;
    }

    takeLater(church['licenseExpiresAt']);
    takeLater(church['expiresAt']);
    takeLater(church['data_vencimento']);
    takeLater(church['trialEndsAt']);
    if (lic != null) {
      takeLater(lic['expiresAt']);
      takeLater(lic['licenseExpiresAt']);
      takeLater(lic['trialEndsAt']);
    }
    if (billing != null) {
      takeLater(billing['nextChargeAt']);
      takeLater(billing['currentPeriodEnd']);
      takeLater(billing['paidUntil']);
    }

    if (!hasExplicitLicenseEnd) {
      final c = church['createdAt'];
      if (c is Timestamp) {
        final d = c.toDate().add(const Duration(days: 30));
        if (best == null || d.isAfter(best!)) best = d;
      }
    }
    return best;
  }

  static DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      if (sec is num) {
        return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
      }
    }
    return DateTime.tryParse(raw.toString());
  }

  static bool churchIsFree(Map<String, dynamic>? church) {
    if (church == null) return false;
    final lic = church['license'];
    final planKey =
        (church['plano'] ?? church['planId'] ?? '').toString().toLowerCase();
    return planKey == 'free' ||
        church['isFree'] == true ||
        (lic is Map && lic['isFree'] == true);
  }

  /// Bloqueio do painel da igreja: master bloqueou, ou (vencimento + 3 dias de carência), ou assinatura ACTIVE vencida.
  /// Igreja FREE ou `license.isFree` nunca bloqueia por pagamento.
  static bool licenseAccessBlocked({
    required Map<String, dynamic>? subscription,
    required Map<String, dynamic>? church,
  }) {
    if (church != null) {
      final lic = church['license'];
      if (churchIsFree(church)) {
        if (church['adminBlocked'] == true) return true;
        if (lic is Map && lic['adminBlocked'] == true) return true;
        return false;
      }
      if (church['adminBlocked'] == true) return true;
      if (church['ativa'] == false) return true;
      if (church['masterInactive'] == true) return true;
      if (church['siteDisabled'] == true) return true;
      if (lic is Map) {
        if (lic['adminBlocked'] == true) return true;
        if (lic['active'] == false) return true;
      }

      final accessEnd = churchAccessEnd(church);
      if (accessEnd != null) {
        final graceEnd = accessEnd.add(const Duration(days: AppConstants.subscriptionGraceDays));
        if (DateTime.now().isBefore(graceEnd)) return false;
      }
    }

    final sub = subscription;
    if (sub == null) {
      final end = churchAccessEnd(church);
      if (end == null) return false;
      final graceEnd = end.add(const Duration(days: AppConstants.subscriptionGraceDays));
      return DateTime.now().isAfter(graceEnd);
    }

    final status = (sub['status'] ?? '').toString().toUpperCase();
    if (status == 'BLOCKED') return true;
    if (status == 'ACTIVE') {
      final endDate = _subscriptionEndDate(sub);
      if (endDate == null) return false;
      final graceEnd = endDate.add(const Duration(days: AppConstants.subscriptionGraceDays));
      return DateTime.now().isAfter(graceEnd);
    }

    final endDate = _subscriptionEndDate(sub);
    if (endDate == null) return false;
    final graceEnd = endDate.add(const Duration(days: AppConstants.subscriptionGraceDays));
    return DateTime.now().isAfter(graceEnd);
  }

  static DateTime? _subscriptionEndDate(Map<String, dynamic> sub) {
    Object? ts = sub['trialEndsAt'] ?? sub['nextChargeAt'] ?? sub['currentPeriodEnd'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is Map) {
      final sec = ts['seconds'] ?? ts['_seconds'];
      if (sec != null) {
        final ms = (sec is int) ? sec * 1000 : (sec as num).toInt() * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return null;
  }
}
