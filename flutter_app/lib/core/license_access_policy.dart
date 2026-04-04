import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/app_constants.dart';

/// Regras de bloqueio do painel da igreja (carência, trial, assinatura).
/// Extraído do [AuthGate] para uso em shells sem import circular com `auth_gate.dart`.
class LicenseAccessPolicy {
  LicenseAccessPolicy._();

  /// Fim do período de acesso considerando doc da igreja (trial 30 dias, licença paga, etc.).
  static DateTime? churchAccessEnd(Map<String, dynamic>? church) {
    if (church == null) return null;
    DateTime? best;
    void takeLater(Timestamp? ts) {
      if (ts == null) return;
      final d = ts.toDate();
      if (best == null || d.isAfter(best!)) best = d;
    }

    takeLater(church['licenseExpiresAt'] as Timestamp?);
    takeLater(church['trialEndsAt'] as Timestamp?);
    final c = church['createdAt'];
    if (c is Timestamp) {
      final d = c.toDate().add(const Duration(days: 30));
      if (best == null || d.isAfter(best!)) best = d;
    }
    return best;
  }

  /// Bloqueio do painel da igreja: master bloqueou, ou (vencimento + 3 dias de carência), ou assinatura ACTIVE vencida.
  /// Igreja FREE ou `license.isFree` nunca bloqueia por pagamento.
  static bool licenseAccessBlocked({
    required Map<String, dynamic>? subscription,
    required Map<String, dynamic>? church,
  }) {
    if (church != null) {
      if (church['adminBlocked'] == true) return true;
      if (church['ativa'] == false) return true;
      if (church['masterInactive'] == true) return true;
      if (church['siteDisabled'] == true) return true;
      final lic = church['license'];
      if (lic is Map) {
        if (lic['adminBlocked'] == true) return true;
        if (lic['active'] == false) return true;
        if (lic['isFree'] == true) return false;
      }
      final plano = (church['plano'] ?? '').toString().toLowerCase();
      if (plano == 'free') return false;

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
